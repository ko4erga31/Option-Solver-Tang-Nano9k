import asyncio
import os
import subprocess
import struct
from datetime import datetime, timezone, timedelta
from collections import deque
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import matplotlib.ticker as ticker
from statsmodels.nonparametric.smoothers_lowess import lowess

from t_tech.invest import AsyncClient
from t_tech.invest.async_services import AsyncServices
from t_tech.invest.grpc.instruments_pb2 import OPTION_DIRECTION_CALL
from t_tech.invest.schemas import InstrumentIdType
from dotenv import load_dotenv
from main import implied_vol

# ================= НАСТРОЙКИ =================
load_dotenv()
TOKEN = os.environ["INVEST_TOKEN"]
GAZP_UID = '962e2a95-02a9-4171-abd7-aa198dbe643a'
MOSCOW_TZ = timezone(timedelta(hours=3))
UPDATE_INTERVAL = 5  # Увеличил интервал, т.к. запуск симулятора занимает время
MAX_PRICE_HISTORY = 100
MIN_T = 0.00274
MIN_PRICE_RUB = 0.05  # Минимальная цена опциона в РУБЛЯХ
UART_TIMEOUT = 10

SIMULATOR_CMD = ["vvp", "/home/kniv/BS-model/tb_top"]

REQ_FILE = "/home/kniv/BS-model/uart_request.bin"
RESP_FILE = "/home/kniv/BS-model/uart_response.bin"

MAX_CONCURRENT_INSTRUMENT = 5
sem_instr = asyncio.Semaphore(MAX_CONCURRENT_INSTRUMENT)
option_params_cache = {}
LAST_PARAMS_UPDATE = 0
PARAMS_UPDATE_INTERVAL = 1000

OSS_CAD_SUITE_PATH = Path.home() / "Загрузки" / "oss-cad-suite" / "bin"


# ================= ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ =================
def quotation_to_float(q):
    return float(q.units + q.nano / 1e9)


def float_to_q1616_bin(x: float) -> bytes:
    """Конвертирует float в 4 байта Q16.16 (Big-Endian)."""
    scale = 65536.0
    if x < -32768.0 or x > 32767.9999:
        print(f"WARNING: {x} вне диапазона Q16.16!")
    int_val = int(round(x * scale))
    uint32 = int_val & 0xFFFFFFFF
    return struct.pack('>i', uint32)  # >I = Big-Endian Unsigned 32-bit


def q1616_bytes_to_float(data: bytes) -> float:
    """Конвертирует 4 байта Q16.16 (Big-Endian) во float."""
    uint32 = struct.unpack('<i', data)[0]
    if uint32 & 0x80000000:
        int32 = uint32 - 0x100000000
    else:
        int32 = uint32
    return int32 / 65536.0


async def update_option_params_many(client: AsyncServices, uid_list: list[str]):
    global option_params_cache, LAST_PARAMS_UPDATE
    print(f"Обновляем параметры опционов ({len(uid_list)} шт)...")
    BATCH_SIZE = 50  # UID в одном батче
    BATCH_DELAY = 15  # секунд между батчами (чтобы не выбрать лимит 200/мин)
    if len(uid_list) < 200:
        BATCH_SIZE = len(uid_list)
        BATCH_DELAY = 1


    async def fetch_one(uid):
        async with sem_instr:
            try:
                opt = await client.instruments.option_by(
                    id_type=InstrumentIdType.INSTRUMENT_ID_TYPE_UID,
                    id=uid
                )
                instr = opt.instrument
                exp_dt = instr.expiration_date
                if exp_dt.tzinfo is None:
                    exp_dt = exp_dt.replace(tzinfo=MOSCOW_TZ)
                return uid, {
                    "type": instr.direction,
                    "strike_rub": quotation_to_float(instr.strike_price),
                    "expiration": exp_dt,
                }
            except Exception as e:
                print(f"Ошибка параметров {uid}: {e}")
                return uid, None

    for i in range(0, len(uid_list), BATCH_SIZE):
        batch = uid_list[i:i + BATCH_SIZE]
        tasks = [fetch_one(uid) for uid in batch]
        results = await asyncio.gather(*tasks)
        for uid, params in results:
            if params:
                option_params_cache[uid] = params
        if i + BATCH_SIZE < len(uid_list):
            print(f"Батч {i // BATCH_SIZE + 1} обработан, пауза {BATCH_DELAY} сек...")
            await asyncio.sleep(BATCH_DELAY)

    LAST_PARAMS_UPDATE = datetime.now().timestamp()
    print(f"Кэш обновлён ({len(option_params_cache)} опционов)")

async def get_all_prices_many(client: AsyncServices, all_uids: list[str]) -> dict[str, float | None]:
    """Собирает цены пачками до 500 uid, возвращает словарь {uid: price_rub или None}."""
    BATCH_SIZE = 500
    prices = {}
    for i in range(0, len(all_uids), BATCH_SIZE):
        batch = all_uids[i:i + BATCH_SIZE]
        try:
            resp = await client.market_data.get_last_prices(instrument_id=batch)
            for item in resp.last_prices:
                prices[item.instrument_uid] = quotation_to_float(item.price)
        except Exception as e:
            print(f"Ошибка получения цен в батче {i // BATCH_SIZE}: {e}")
            # При ошибке помечаем все uid из батча как None
            for uid in batch:
                prices[uid] = None
        # Небольшая пауза для соблюдения лимитов (600 запросов/мин)
        if i + BATCH_SIZE < len(all_uids):
            await asyncio.sleep(0.2)  # 200 мс
    # Добавляем None для uid, которые по какой-то причине отсутствуют в ответе
    for uid in all_uids:
        if uid not in prices:
            prices[uid] = None
    return prices


def run_simulator(body: bytes) -> float:
    """Записывает файл, запускаает симулятор, читает ответ."""
    # 1. Пишем запрос
    with open(REQ_FILE, "wb") as f:
        f.write(body)

    # 2. Удаляем старый ответ, если есть
    if os.path.exists(RESP_FILE):
        os.remove(RESP_FILE)

    env = os.environ.copy()
    # Добавляем oss-cad-suite в начало PATH (приоритет над системными утилитами)
    if OSS_CAD_SUITE_PATH.exists():
        env["PATH"] = str(OSS_CAD_SUITE_PATH) + os.pathsep + env.get("PATH", "")
    else:
        print(f"WARNING: oss-cad-suite не найден по пути {OSS_CAD_SUITE_PATH}")

    # 3. Запускаем симулятор (блокирующий вызов)
    try:
        # Если vvp не найден, убедитесь, что он в PATH, или укажите полный путь
        result = subprocess.run(SIMULATOR_CMD,
                                capture_output=True,
                                text=True,
                                timeout=15,
                                env=env,
                                cwd=os.getcwd())
        #print(result.stdout)
        if result.returncode != 0:
            print(f"Simulator Error:\n{result.stderr}")
            return -1.0
        #print(result)
    except subprocess.TimeoutExpired:
        print("Simulator Timeout!")
        return -1.0
    except FileNotFoundError:
        print("ОШИБКА: Симулятор (vvp) не найден! Скомпилируйте testbench.")
        return -1.0

    # 4. Читаем ответ
    if os.path.exists(RESP_FILE):
        with open(RESP_FILE, "rb") as f:
            reply = f.read()
        if len(reply) == 4:
            return q1616_bytes_to_float(reply)
    return -1.0


# ================= ОСНОВНОЙ ЦИКЛ =================
async def main():
    uid_list = []
    try:
        with open("option_uids.txt", "r") as f:
            line = f.readline().strip()
            if line:
                uid_list = [u.strip() for u in line.split(',') if u.strip()]
    except FileNotFoundError:
        print("Файл option_uids.txt не найден")
        return

    if not uid_list:
        print("Список опционов пуст")
        return

    print(f"Загружено {len(uid_list)} UID опционов")

    plt.ion()
    fig, (ax_price, ax_vol) = plt.subplots(2, 1, figsize=(12, 10))
    ax_price.set_ylabel("Цена GAZP, руб.")
    ax_price.set_title("Динамика цены базового актива")
    ax_vol.set_xlabel("Спот / Страйк")
    ax_vol.set_ylabel("Вменённая волатильность, %")
    ax_vol.set_title("Volatility smile")

    price_times = deque(maxlen=MAX_PRICE_HISTORY)
    price_values = deque(maxlen=MAX_PRICE_HISTORY)

    async with AsyncClient(TOKEN) as client:
        all_price_uids = [GAZP_UID] + uid_list
        await update_option_params_many(client, uid_list)
        start_time = datetime.now().timestamp()

        while True:
            now_ts = datetime.now().timestamp()
            if now_ts - LAST_PARAMS_UPDATE > PARAMS_UPDATE_INTERVAL:
                await update_option_params_many(client, uid_list)

            prices = await get_all_prices_many(client, all_price_uids)
            spot_rub = prices.get(GAZP_UID)
            if spot_rub is None or spot_rub <= 0:
                await asyncio.sleep(UPDATE_INTERVAL)
                continue

            price_times.append(now_ts - start_time)
            price_values.append(spot_rub)

            now_dt = datetime.now(MOSCOW_TZ)
            call_points, put_points = [], []

            for uid in uid_list:
                price_rub = prices.get(uid)
                if price_rub is None or price_rub < MIN_PRICE_RUB: continue

                params = option_params_cache.get(uid)
                if not params: continue

                T = (params["expiration"] - now_dt).total_seconds() / (365.25 * 24 * 3600)
                if T <= MIN_T: continue

                opt_type = 0 if params['type'] == OPTION_DIRECTION_CALL else 1
                strike_rub = params["strike_rub"]

                body = (opt_type.to_bytes(1, 'big') +
                        float_to_q1616_bin(spot_rub) +
                        float_to_q1616_bin(strike_rub) +
                        float_to_q1616_bin(T) +
                        float_to_q1616_bin(price_rub))
                start_calc = datetime.now().timestamp()
                sigma = await asyncio.to_thread(run_simulator, body)
                end_calc = datetime.now().timestamp()
                print(sigma, "vs", implied_vol(opt_type, spot_rub, strike_rub, 0.15, T, price_rub))
                #print("Время выполнения: ", end_calc - start_calc)

                if sigma > 0 and sigma < 500:
                    moneyness = spot_rub / strike_rub
                    if opt_type == 0:
                        call_points.append((moneyness, sigma * 100))
                    else:
                        put_points.append((moneyness, sigma * 100))

            ax_price.clear()
            ax_price.plot(price_times, price_values, color='black')
            ax_price.set_ylabel("Цена GAZP, руб.")
            ax_price.set_title("Динамика цены базового актива")
            ax_price.grid(True)
            ax_price.ticklabel_format(axis='y', useOffset=False, style='plain')
            ax_price.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.2f'))


            ax_vol.clear()


            if call_points:
                c_strikes, c_sigmas = zip(*call_points)
                ax_vol.scatter(c_strikes, c_sigmas, alpha=0.7, s=15, c='green')  # Call
            if put_points:
                p_strikes, p_sigmas = zip(*put_points)
                ax_vol.scatter(p_strikes, p_sigmas, alpha=0.7, s=15, c='red')  # Put

            all_strikes = np.array([p[0] for p in call_points] + [p[0] for p in put_points])
            all_sigmas = np.array([p[1] for p in call_points] + [p[1] for p in put_points])

            if len(all_strikes) >= 3:
                coeffs = np.polyfit(all_strikes, all_sigmas, 3)
                x_line = np.linspace(min(all_strikes), max(all_strikes), 100)
                y_line = np.polyval(coeffs, x_line)
                ax_vol.plot(x_line, y_line, 'y--')

            # Вертикальная линия текущей цены базового актива
            ax_vol.axvline(x=1, color='black', linestyle='-', linewidth=1, alpha=0.8,
                           label=f'GAZP: {spot_rub:.2f} руб.')

            ax_vol.set_xlabel("Спот / Страйк")
            ax_vol.set_ylabel("Вменённая волатильность, %")
            ax_vol.set_title("Volatility smile")
            ax_vol.grid(True)
            ax_vol.legend(loc='upper right')

            plt.draw()
            plt.pause(UPDATE_INTERVAL)


if __name__ == "__main__":
    asyncio.run(main())
