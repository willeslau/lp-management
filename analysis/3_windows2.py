import time

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

from binance_price_candle import previous_hours_to_interval, get_recent_24h_klines

Z_SCORES = {
    0.65: 0.93,
    0.70: 1.04,
    0.75: 1.15,
    0.80: 1.28,
    0.85: 1.44,
    0.90: 1.645,
    0.95: 1.96,
}

def get_z_score(conf: float) -> float:
    z = Z_SCORES.get(conf)
    if z is None:
        raise KeyError(f"Missing z-score for confidence level {conf}")
    return z

def gk_variance(df):
    h_l = np.log(df['high'] / df['low'])
    c_o = np.log(df['close'] / df['open'])

    # Calculate GK components
    gk = 0.5 * (h_l ** 2) - (2 * np.log(2) - 1) * (c_o ** 2)
    # gk[gk < 0] = np.abs(gk[gk < 0])  # Handle negatives

    return gk

def gk_ewma_volatility(df, lambda_=0.94, conf_level=0.8):
    gk = gk_variance(df)
    gk[gk < 0] = np.abs(gk[gk < 0])  # Handle negatives
    
    # Compute EWMA variance
    ewma_var = gk.ewm(alpha=1-lambda_, adjust=False).mean()
    vol = np.sqrt(ewma_var)

    z_score = get_z_score(conf_level)
    return np.exp(z_score * vol)

def rolling_ohlc(df: pd.DataFrame, window: int) -> pd.DataFrame:
    return pd.DataFrame({
        'timestamp_ms':   df['timestamp_ms'].rolling(window).min(),
        'open':  df['open'].rolling(window).apply(lambda x: x[0], raw=True),
        'high':  df['high'].rolling(window).max(),
        'low':   df['low'].rolling(window).min(),
        'close': df['close'].rolling(window).apply(lambda x: x[-1], raw=True),
    }).dropna()

def z_score(series, window):
    mean = series.shift(1).rolling(window).mean()
    std  = series.shift(1).rolling(window).std()
    return (series - mean) / std

def run(df: pd.DataFrame, window_size: int, threshold_1v6: float, threshold_1v12: float):
    decay = 0.94

    df['gk_1'] = gk_variance(df)

    df_2 = df.copy()
    df_2['var_5']  = df_2['gk_1'].rolling(5).sum()
    df_2['var_30'] = df_2['gk_1'].shift(5).rolling(30).sum()
    df_2['var_60'] = df_2['gk_1'].shift(35).rolling(60).sum()
    df_2 = df_2.dropna()

    df_2['ratio_5v30'] = df_2['var_5'] / df_2['var_30']
    df_2['ratio_5v60'] = df_2['var_5'] / df_2['var_60']

    # df_2['signal'] = (df_2['ratio_5v30'] > threshold_1v6) & (df_2['ratio_5v60'] > threshold_1v12)
    # print(df_2)

    df_2 = df_2[['ratio_5v30', 'ratio_5v60']]
    ohlc_5 = rolling_ohlc(df, 5)
    vol_5 = gk_ewma_volatility(ohlc_5) - 1

    df['next_close'] = df['close'].shift(-1)

    df = df.dropna().iloc[4:]
    df['vol_5'] = vol_5.iloc[:len(df)]

    # print(vol_5)
    has_opened_pos = False
    predicted_lower_range = 0
    predicted_upper_range = 0
    in_range_slots = []
    in_range_slot = 0
    result = []
    for idx, row in df.iterrows():
        if not has_opened_pos:
            open_price = row['close']
            predicted_lower_range = open_price * (1 - row['vol_5'])
            predicted_upper_range = open_price * (1 + row['vol_5'])

            in_range_slot = 0
            has_opened_pos = True
            result.append(0)
            continue

        # print(predicted_lower_range, row['close'], predicted_upper_range)
        if row['close'] > predicted_upper_range or row['close'] < predicted_lower_range:
            result.append(-1)
            in_range_slots.append(in_range_slot)
            has_opened_pos = False
        else:
            in_range_slot += 1
            result.append(1)

    df['result'] = result
    predicted = df[df['result'] != 0]
    print(predicted['result'].mean())
    print(in_range_slots)
    
    print((1 - df.iloc[-1]['vol_5']) * df.iloc[-1]['close'])
    print((1 + df.iloc[-1]['vol_5']) * df.iloc[-1]['close'])
        
            
    #     print(idx, row)

    # df['actual'] = np.abs((df['close'].shift(-1) - df['open']) / df['open'])
    # df = df.dropna().iloc[4:]

    # df['vol_5'] = vol_5.iloc[0:len(df)]
    # df['is_breach'] = df['actual'] > df['vol_5']

    # print(df['is_breach'].mean())

    # df = df.join(df_2, how = "inner")
    # # pd.set_option("display.max_rows", None)
    # # print(df)


    # # # TP = ((gks['change_coming'] == 1) & (gks['result'] == 1)).sum() / len(gks) * 100
    # # # FP = ((gks['change_coming'] == 1) & (gks['result'] == 0)).sum() / len(gks) * 100
    # # # TN = ((gks['change_coming'] == 0) & (gks['result'] == 0)).sum() / len(gks) * 100
    # # # FN = ((gks['change_coming'] == 0) & (gks['result'] == 1)).sum() / len(gks) * 100
    # # # print(TP, FP, TN, FN)

    # fig, ax1 = plt.subplots(figsize=(12, 5))

    # # Plot open and close price (left y-axis)
    # # ax1.plot(df.index, df['open'], label='Open Price', color='tab:blue', alpha=0.7)
    # ax1.plot(df.index, df['result'], label='Result', color='tab:cyan', alpha=0.7)
    # ax1.set_ylabel("Price", color='tab:blue')
    # ax1.tick_params(axis='y', labelcolor='tab:blue')
    # ax1.set_xlabel("Timestamp")

    # # Create right y-axis for volatility ratios
    # ax2 = ax1.twinx()
    # ax2.plot(df.index, df['ratio_5v30'], label='5m / 30m Vol Ratio', color='tab:red', linewidth=1.2)
    # ax2.plot(df.index, df['ratio_5v60'],  label='5m / 1h Vol Ratio',  color='tab:orange', linewidth=1.2)
    # # ax2.plot(df.index, df['ratio_5v30'],  label='ratio_5v30',  color='tab:green', linewidth=1.2)
    # # ax2.plot(gks.index, gks['change_coming'],  label='change_coming',  color='tab:green', linewidth=1.2)
    # ax2.set_ylabel("GK Volatility Ratio", color='tab:red')
    # ax2.tick_params(axis='y', labelcolor='tab:red')

    # # Combine legends
    # lines_1, labels_1 = ax1.get_legend_handles_labels()
    # lines_2, labels_2 = ax2.get_legend_handles_labels()
    # ax1.legend(lines_1 + lines_2, labels_1 + labels_2, loc='upper left')

    # plt.title("Open/Close Price + GK Volatility Ratios")
    # plt.grid(True)
    # plt.tight_layout()
    # plt.show()

if __name__ == "__main__":
    while True:
        start_time, end_time = previous_hours_to_interval(3)
        interval = "1m"
        output_file="./bnb_1m_klines.csv"
        limit = 360

        get_recent_24h_klines(start_time, end_time, limit, interval, output_file, "BNBUSDT")

        df = pd.read_csv("./bnb_1m_klines.csv", parse_dates=["open_time"])

        df = df.drop('volume(Volatile)', axis = 1)
        # df = df.drop('volume(USDT)', axis = 1)

        run(df, 10, 1.2, 1.0)

        time.sleep(60)