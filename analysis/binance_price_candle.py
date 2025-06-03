import requests
import time
import csv
from datetime import datetime

def previous_hours_to_interval(hours): 
    end_time = int(time.time() * 1000)
    start_time = end_time - hours * 60 * 60 * 1000
    return (start_time, end_time)

def get_recent_24h_klines(start_time, end_time, limit, interval, output_file, symbol="BTCUSDT"):
    url = "https://api.binance.com/api/v3/klines"

    params = {
        "symbol": symbol,
        "interval": interval,
        "startTime": start_time,
        "endTime": end_time,
        "limit": limit,
    }

    response = requests.get(url, params=params)
    response.raise_for_status()
    data = response.json()

    # print(f"共获取 {len(data)} 条记录，保存为 CSV: {output_file}")

    # 写入 CSV 文件
    with open(output_file, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(
            ["timestamp_ms", "open_time","open", "high", "low", "close", "volume(Volatile)", "volume(USDT)"])

        for kline in data:
            open_time = datetime.fromtimestamp(kline[0] / 1000)
            open_price = float(kline[1])
            high_price = kline[2]
            low_price = kline[3]
            close_price = float(kline[4])
            volume = kline[5]
            quote_asset_volume = kline[7]

            row = [
                kline[0],
                open_time.strftime("%Y-%m-%d %H:%M:%S"),
                f"{open_price:.2f}",
                high_price,
                low_price,
                f"{close_price:.2f}",
                volume,
                quote_asset_volume,
            ]
            writer.writerow(row)

