import asyncio
import os
from datetime import datetime, timezone, timedelta
import math
import matplotlib.pyplot as plt
from collections import deque
from t_tech.invest import AsyncClient
from t_tech.invest.async_services import AsyncServices
from t_tech.invest.grpc.instruments_pb2 import OPTION_DIRECTION_CALL
from t_tech.invest.schemas import InstrumentIdType
from dotenv import load_dotenv
import numpy as np
import matplotlib.ticker as ticker
from statsmodels.nonparametric.smoothers_lowess import lowess

#CALL = 2, PUT = 1

load_dotenv()

TOKEN = os.environ["INVEST_TOKEN"]
GAZP_FIGI = "BBG004730RP0"
RISK_FREE_RATE = 0.15          # 14.5% годовых
MOSCOW_TZ = timezone(timedelta(hours=3))
UPDATE_INTERVAL = 1           # секунд между обновлениями
MAX_PRICE_HISTORY = 100         # сколько последних значений цены хранить и отображать
GAZP_UID = '962e2a95-02a9-4171-abd7-aa198dbe643a'
# Минимальное время до экспирации (1 день)
MIN_T = 0.00274   # 1/365.25
# Минимальная цена опциона в копейках
MIN_PRICE_KOP = 5  # или 5 копеек

# ---------- лимиты ----------
MAX_CONCURRENT_INSTRUMENT = 5
sem_instr = asyncio.Semaphore(MAX_CONCURRENT_INSTRUMENT)

# ---------- кэш параметров опционов ----------
option_params_cache = {}
LAST_PARAMS_UPDATE = 0
PARAMS_UPDATE_INTERVAL = 1000

def to_kopecks(value_rub: float) -> int:
    """Перевод рублей в целые копейки."""
    return round(value_rub * 100)

def quotation_to_float(q):
    """Перевод денежной величины (Quotation) в float."""
    return float(q.units + q.nano / 1e9)

# ---------- Блэк-Шоулз ----------
from scipy.stats import norm

def bs_price(option_type: int, S: float, K: float, r: float, T: float, sigma: float) -> float:
    if T <= 0 or sigma <= 0:
        return 0.0
    d1 = (math.log(S / K) + (r + sigma**2 / 2) * T) / (sigma * math.sqrt(T))
    d2 = d1 - sigma * math.sqrt(T)
    if option_type == OPTION_DIRECTION_CALL:
        return S * norm.cdf(d1) - K * math.exp(-r * T) * norm.cdf(d2)
    else:
        return K * math.exp(-r * T) * norm.cdf(-d2) - S * norm.cdf(-d1)

def implied_vol(option_type: int, S: float, K: float, r: float, T: float, market_price: float) -> float | None:
    if T <= 0 or market_price <= 0:
        return None
    low, high = 0.001, 5.0
    for _ in range(100):
        mid = (low + high) / 2
        price = bs_price(option_type, S, K, r, T, mid)
        if abs(price - market_price) < 1e-8:
            return mid
        if price > market_price:
            high = mid
        else:
            low = mid
    return (low + high) / 2

# ---------- API-запросы ----------
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
                    "strike_kop": to_kopecks(quotation_to_float(instr.strike_price)),
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

async def update_option_params(client: AsyncServices, uid_list: list[str]):
    global option_params_cache, LAST_PARAMS_UPDATE
    print("Обновляем параметры опционов...")
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
                    "strike_kop": to_kopecks(quotation_to_float(instr.strike_price)),
                    "expiration": exp_dt,
                }
            except Exception as e:
                print(f"Ошибка параметров {uid}: {e}")
                return uid, None

    tasks = [fetch_one(uid) for uid in uid_list]
    results = await asyncio.gather(*tasks)
    for uid, params in results:
        if params:
            option_params_cache[uid] = params
    LAST_PARAMS_UPDATE = datetime.now().timestamp()
    print(f"Кэш обновлён ({len(option_params_cache)} опционов)")

async def get_all_prices(client: AsyncServices, all_uids: list[str]) -> dict[str, float | None]:
    """Принимает список UID, возвращает словарь {uid: price_rub или None}."""
    try:
        resp = await client.market_data.get_last_prices(instrument_id=all_uids)
        prices = {}
        for item in resp.last_prices:
            prices[item.instrument_uid] = quotation_to_float(item.price)
        for uid in all_uids:
            if uid not in prices:
                prices[uid] = None
        return prices
    except Exception as e:
        print(f"Ошибка получения цен: {e}")
        return {uid: None for uid in all_uids}

# ---------- главный цикл ----------
async def main():

    uid_list = []
    f = open("option_uids.txt", "r")
    uid_list = f.readline().split(',')
    f.close()

    if not uid_list:
        print("Добавьте список uid_list!")
        return

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
        # Список для запроса цен: UID акции + UID опционов
        all_price_uids = [GAZP_UID] + uid_list

        # Первичная загрузка параметров
        await update_option_params_many(client, uid_list)
        start_time = datetime.now().timestamp()
        while True:
            now_ts = datetime.now().timestamp()
            if now_ts - LAST_PARAMS_UPDATE > PARAMS_UPDATE_INTERVAL:
                await update_option_params_many(client, uid_list)

            prices = await get_all_prices_many(client, all_price_uids)
            spot_rub = prices.get(GAZP_UID)
            if spot_rub is None or spot_rub <= 0:
                print("Нет цены спота, пропуск цикла")
                await asyncio.sleep(UPDATE_INTERVAL)
                continue
            spot_kop = to_kopecks(spot_rub)

            elapsed = now_ts - start_time
            price_times.append(elapsed)
            price_values.append(spot_rub)

            now_dt = datetime.now(MOSCOW_TZ)
            call_points = []  # (strike_rub, sigma)
            put_points = []  # (strike_rub, sigma)

            for uid in uid_list:
                price_rub = prices.get(uid)
                if price_rub is None or price_rub <= 0:
                    continue
                params = option_params_cache.get(uid)
                if not params:
                    continue
                T = (params["expiration"] - now_dt).total_seconds() / (365.25 * 24 * 3600)
                price_kop = to_kopecks(price_rub)

                sigma = implied_vol(params["type"], spot_kop, params["strike_kop"],
                                    RISK_FREE_RATE, T, price_kop)
                if sigma is not None:
                    strike_rub = params["strike_kop"] / 100.0
                    moneyness = spot_rub / strike_rub #нормировка на цену

                    if params["type"] == OPTION_DIRECTION_CALL:
                        call_points.append((moneyness, sigma * 100)) #заменить strike_rub -> moneyness
                    else:
                        put_points.append((moneyness, sigma * 100))

            # Обновление графика цены
            ax_price.clear()
            ax_price.plot(price_times, price_values, color='black')
            ax_price.set_ylabel("Цена GAZP, руб.")
            ax_price.set_title("Динамика цены базового актива")
            ax_price.grid(True)
            ax_price.ticklabel_format(axis='y', useOffset=False, style='plain')
            ax_price.yaxis.set_major_formatter(ticker.FormatStrFormatter('%.2f'))

            # Обновление графика волатильности
            ax_vol.clear()

            # Разделяем точки по типам
            if call_points:
                c_strikes, c_sigmas = zip(*call_points)
                ax_vol.scatter(c_strikes, c_sigmas, alpha=0.7, s=15, c='green') #Call
            if put_points:
                p_strikes, p_sigmas = zip(*put_points)
                ax_vol.scatter(p_strikes, p_sigmas, alpha=0.7, s=15, c='red') #Put

            # Гладкая кривая средних (LOWESS) по всем точкам
            all_strikes = np.array([p[0] for p in call_points] + [p[0] for p in put_points])
            all_sigmas = np.array([p[1] for p in call_points] + [p[1] for p in put_points])

            if len(all_strikes) >= 5:  # нужно хотя бы несколько точек для LOWESS
                # LOWESS: frac задаёт ширину окна (доля точек), можно регулировать гладкость
                lowess_result = lowess(all_sigmas, all_strikes, frac=0.3, return_sorted=True)
                ax_vol.plot(lowess_result[:, 0], lowess_result[:, 1], 'b-')

            if len(all_strikes) >= 3:
                coeffs = np.polyfit(all_strikes, all_sigmas, 3)
                x_line = np.linspace(min(all_strikes), max(all_strikes), 100)
                y_line = np.polyval(coeffs, x_line)
                ax_vol.plot(x_line, y_line, 'y--')

            # Вертикальная линия текущей цены базового актива
            ax_vol.axvline(x=1, color='black', linestyle='-', linewidth=1, alpha=0.8, label=f'GAZP: {spot_rub:.2f} руб.')

            ax_vol.set_xlabel("Спот / Страйк")
            ax_vol.set_ylabel("Вменённая волатильность, %")
            ax_vol.set_title("Volatility smile")
            ax_vol.grid(True)
            ax_vol.legend(loc='upper right')

            plt.draw()
            plt.pause(UPDATE_INTERVAL)


if __name__ == "__main__":
    asyncio.run(main())