import time

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from binance_price_candle import previous_hours_to_interval, get_recent_24h_klines

def gk_ewma_sigma(df, lambda_=0.94):
    h_l = np.log(df['high'] / df['low'])
    c_o = np.log(df['close'] / df['open'])

    # Calculate GK components
    gk = 0.5 * (h_l ** 2) - (2 * np.log(2) - 1) * (c_o ** 2)
    gk[gk < 0] = np.abs(gk[gk < 0])  # Handle negatives

    # Compute EWMA variance
    ewma_var = gk.ewm(alpha=1-lambda_, adjust=False).mean()
    return np.sqrt(ewma_var)

def rolling_ohlc(df: pd.DataFrame, window: int) -> pd.DataFrame:
    return pd.DataFrame({
        'timestamp_ms':   df['timestamp_ms'].shift(1).rolling(window).min(),
        'open':  df['open'].shift(1).rolling(window).apply(lambda x: x[0], raw=True),
        'high':  df['high'].shift(1).rolling(window).max(),
        'low':   df['low'].shift(1).rolling(window).min(),
        'close': df['close'].shift(1).rolling(window).apply(lambda x: x[-1], raw=True),
    }).dropna()

def z_score(series, window):
    mean = series.shift(1).rolling(window).mean()
    std  = series.shift(1).rolling(window).std()
    return (series - mean) / std

def run(df: pd.DataFrame, window_size: int, threshold_1v6: float, threshold_1v12: float):
    decay = 0.94

    one_window_sigma = gk_ewma_sigma(df, lambda_ = decay)

    six_window_df = rolling_ohlc(df, 6)
    six_window_sigma = gk_ewma_sigma(six_window_df, lambda_ = decay)

    twelve_window_df = rolling_ohlc(df, 12)
    twelve_window_sigma = gk_ewma_sigma(twelve_window_df, lambda_ = decay)

    gks = pd.concat([one_window_sigma, six_window_sigma, twelve_window_sigma, df['close']], axis=1)
    gks = gks.dropna()
    # gks = gks.reset_index(drop = True)
    gks = gks.rename(columns={0: 'gk_1', 1: 'gk_6', 2: 'gk_12'})

    gks['ratio_1v6'] = gks['gk_1'] / gks['gk_6']
    gks['ratio_1v12'] = gks['gk_1'] / gks['gk_12']

    gks['z_1v6'] = z_score(gks['ratio_1v6'], window_size)
    gks['z_1v12'] = z_score(gks['ratio_1v12'], window_size)

    # gks['change_coming'] = (gks['z_1v6'] > threshold_1v6) & (gks['z_1v12'] > threshold_1v12)
    gks['fwd_return'] = np.abs(df['close'].pct_change(3).shift(-3)) > 0.002

    # TP = ((gks['change_coming'] == 1) & (gks['result'] == 1)).sum() / len(gks) * 100
    # FP = ((gks['change_coming'] == 1) & (gks['result'] == 0)).sum() / len(gks) * 100
    # TN = ((gks['change_coming'] == 0) & (gks['result'] == 0)).sum() / len(gks) * 100
    # FN = ((gks['change_coming'] == 0) & (gks['result'] == 1)).sum() / len(gks) * 100
    # print(TP, FP, TN, FN)

    fig, ax1 = plt.subplots(figsize=(12, 5))

    # Plot open and close price (left y-axis)
    # ax1.plot(df.index, df['open'], label='Open Price', color='tab:blue', alpha=0.7)
    ax1.plot(gks.index, gks['fwd_return'], label='Close Price', color='tab:cyan', alpha=0.7)
    ax1.set_ylabel("Price", color='tab:blue')
    ax1.tick_params(axis='y', labelcolor='tab:blue')
    ax1.set_xlabel("Timestamp")

    # Create right y-axis for volatility ratios
    ax2 = ax1.twinx()
    ax2.plot(gks.index, gks['z_1v6'], label='Change coming', color='tab:red', linewidth=1.2)
    ax2.plot(gks.index, gks['z_1v12'],  label='5m / 1h Vol Ratio',  color='tab:orange', linewidth=1.2)
    ax2.set_ylabel("GK Volatility Ratio", color='tab:red')
    ax2.tick_params(axis='y', labelcolor='tab:red')

    # Combine legends
    lines_1, labels_1 = ax1.get_legend_handles_labels()
    lines_2, labels_2 = ax2.get_legend_handles_labels()
    ax1.legend(lines_1 + lines_2, labels_1 + labels_2, loc='upper left')

    plt.title("Open/Close Price + GK Volatility Ratios")
    plt.grid(True)
    plt.tight_layout()
    plt.show()

if __name__ == "__main__":
    # start_time, end_time = previous_hours_to_interval(30)
    # interval = "5m"
    # output_file="./bnb_5m_klines.csv"
    # limit = 360

    # get_recent_24h_klines(start_time, end_time, limit, interval, output_file, "BNBUSDT")

    df = pd.read_csv("./bnb_5m_klines.csv", parse_dates=["open_time"])

    # df = df.drop('volume(Volatile)', axis = 1)
    df = df.drop('volume(USDT)', axis = 1)

    run(df, 6, 1.8, 1.8)