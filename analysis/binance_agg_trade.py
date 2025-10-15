import os
import csv
import requests
import time
from datetime import datetime, timedelta
from dateutil import tz

BASE_URL = "https://api.binance.com"
MAX_LIMIT = 1000

def clear_folder(folder_path, extensions=[".csv"]):
    print(f"Clearing files in {folder_path}...")
    for filename in os.listdir(folder_path):
        if any(filename.endswith(ext) for ext in extensions):
            filepath = os.path.join(folder_path, filename)
            os.remove(filepath)
            print(f"Deleted {filename}")
    print("Folder cleared.")

def ms_to_datetime(ms):
    return datetime.utcfromtimestamp(ms / 1000)

def get_hour_key(ts_ms):
    dt = ms_to_datetime(ts_ms)
    return dt.strftime("%Y-%m-%d_%H")

def ensure_csv_writer(hour_key, symbol, folder, writers):
    """Ensure a CSV writer for the given hour_key (e.g., '2025-06-28_14') exists."""
    if hour_key in writers:
        return writers[hour_key]

    filename = f"{folder}/{hour_key}.csv"
    f = open(filename, 'w', newline='')
    writer = csv.writer(f)
    writer.writerow(["agg_id", "timestamp_ms", "price", "qty", "is_maker"])
    writers[hour_key] = (writer, f)
    return writer, f

def write_trades_to_hourly_csv(trades, symbol, folder, writers):
    for t in trades:
        hour_key = get_hour_key(t["T"])
        writer, _ = ensure_csv_writer(hour_key, symbol, folder, writers)
        writer.writerow([
            t["a"],         # agg ID
            t["T"],         # raw ms timestamp
            t["p"],         # price
            t["q"],         # quantity
            t["m"]          # is buyer the market maker
        ])

def close_all_writers(writers):
    for _, f in writers.values():
        f.close()

def fetch_agg_trades_by_hour(symbol: str, folder: str, start_time: datetime, end_time: datetime):
    start_ts = int(start_time.timestamp() * 1000)
    end_ts = int(end_time.timestamp() * 1000)

    params = {
        "symbol": symbol.upper(),
        "limit": MAX_LIMIT,
        "startTime": start_ts
    }

    print(f"Fetching {symbol} aggTrades from {start_time} to {end_time}...")
    writers = {}

    try:
        while True:
            response = requests.get(BASE_URL + "/api/v3/aggTrades", params=params)
            response.raise_for_status()
            trades = response.json()

            if not trades:
                print("No more trades.")
                break

            write_trades_to_hourly_csv(trades, symbol, folder, writers)

            last_trade = trades[-1]
            last_time = last_trade["T"]
            last_id = last_trade["a"]

            print(f"Wrote {len(trades)} trades up to {last_time} (ms)")

            if last_time >= end_ts:
                break

            params = {
                "symbol": symbol.upper(),
                "limit": MAX_LIMIT,
                "fromId": last_id + 1
            }

            time.sleep(0.2)
    finally:
        close_all_writers(writers)
        print("All files closed. Done.")

def fetch_interval_by_hour(symbol: str, folder: str, duration: timedelta):
    now = datetime.utcnow().replace(tzinfo=tz.UTC)
    start = now - duration
    fetch_agg_trades_by_hour(symbol, folder, start, now)

# 🧪 Example usage:
if __name__ == "__main__":
    symbol = "BNBBTC"

    folder = "./data/trades/" + symbol

    clear_folder(folder)
    fetch_interval_by_hour(symbol, folder, timedelta(hours=6))
