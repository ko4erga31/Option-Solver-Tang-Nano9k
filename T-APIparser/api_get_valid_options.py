import os
from datetime import *
import time
from dotenv import load_dotenv
import pytz
from t_tech.invest import Client


load_dotenv()
TOKEN = os.environ["INVEST_TOKEN"]

BASE_ASSET_POSITION_UID = '4f9d0c81-cdf9-4735-8295-bacbfa3b8a51'  # GAZP
MIN_OPTION_PRICE = 0.01          # руб.
MIN_DAYS_TO_EXPIRY = 1           # минимум 1 день до экспирации
EXPIRY_CUTOFF = datetime(2029, 1, 1, tzinfo=pytz.utc)
MAX_INSTRUMENTS_PER_BATCH = 500  # лимит get_last_prices
BATCH_DELAY = 0.3                # задержка между батчами цен (сек)

def main():
    with Client(TOKEN) as client:
        # 1. Все опционы на базовый актив
        all_options = client.instruments.options().instruments
        print(f"Всего опционов в ответе: {len(all_options)}")

        now_utc = datetime.now(pytz.utc)

        # 2. Предварительный фильтр по базовому активу, дате, доступности торгов
        candidates = []
        for instr in all_options:
            if instr.basic_asset_position_uid != BASE_ASSET_POSITION_UID:
                continue
            exp_dt = instr.expiration_date.replace(tzinfo=pytz.utc)
            if exp_dt <= now_utc or exp_dt > EXPIRY_CUTOFF:
                continue
            if not instr.api_trade_available_flag:
                continue
            T = (exp_dt - now_utc).total_seconds() / (365.25 * 24 * 3600)
            if T < MIN_DAYS_TO_EXPIRY / 365.25:
                continue
            candidates.append(instr)

        print(f"Кандидатов после базовых фильтров: {len(candidates)}")

        # 3. Запрос цен пачками
        uid_to_price = {}
        uids = [instr.uid for instr in candidates]
        for start in range(0, len(uids), MAX_INSTRUMENTS_PER_BATCH):
            batch = uids[start:start + MAX_INSTRUMENTS_PER_BATCH]
            try:
                resp = client.market_data.get_last_prices(instrument_id=batch)
                for item in resp.last_prices:
                    price = item.price.units + item.price.nano / 1e9
                    uid_to_price[item.instrument_uid] = price
            except Exception as e:
                print(f"Ошибка при запросе цен: {e}")
            if start + MAX_INSTRUMENTS_PER_BATCH < len(uids):
                time.sleep(BATCH_DELAY)

        # 4. Финальный отбор: только те, у кого есть цена > MIN_OPTION_PRICE
        final_uids = []
        for instr in candidates:
            price = uid_to_price.get(instr.uid)
            if price is None or price < MIN_OPTION_PRICE:
                continue
            final_uids.append(instr.uid)
            print(f"{instr.ticker} | {instr.name} | цена={price:.4f} руб. | expiry={instr.expiration_date.date()}")


        f = open("option_uids.txt", "w+")
        print(f"\nОтобрано опционов: {len(final_uids)}")
        for i in range(len(final_uids)):
            if i == len(final_uids) - 1:
                f.write(f'{final_uids[i]}')
            else:
                f.write(f'{final_uids[i]},')
        f.close()

if __name__ == "__main__":
    main()