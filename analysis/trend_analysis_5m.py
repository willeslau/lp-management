import pandas as pd
import numpy as np
import math
# from datetime import datetime, timedelta
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

def gk_ewma_volatility(df: pd.DataFrame, lambda_=0.94):
    h_l = np.log(df['high'] / df['low'])
    c_o = np.log(df['close'] / df['open'])

    # Calculate GK components
    gk = 0.5 * (h_l ** 2) - (2 * np.log(2) - 1) * (c_o ** 2)
    gk = np.maximum(gk, 0)

    # Compute EWMA variance
    ewma_var = gk.ewm(alpha=1-lambda_, adjust=False).mean()
    return np.sqrt(ewma_var)

def directional_signal(df: pd.DataFrame, sigma: pd.Series, signal_alpha: float = 0.5):
    log_ret = np.log(df["close"] / df["open"])
    body_up = np.maximum(log_ret, 0)
    body_down = np.maximum(-log_ret, 0)
    bull = (body_up / sigma).ewm(alpha=signal_alpha, adjust=False).mean()
    bear = (body_down / sigma).ewm(alpha=signal_alpha, adjust=False).mean()
    return bull, bear

def five_min_trend(
    df: pd.DataFrame,
    gk_lambda: float = 0.94,
    signal_alpha: float = 0.06,
    z_win: int = 10,
    conf_level: float = 0.80,
    signal_z: float = None,
    oppos_z: float = 0.0
):
    if signal_z is None:
        signal_z = get_z_score(conf_level)

    sigma = gk_ewma_volatility(df, lambda_=gk_lambda)
    bull, bear = directional_signal(df, sigma, signal_alpha)

    df['intra_vol'] = (df['high'] / df['low'] - 1).rolling(3).mean()
    bull = bull / df['intra_vol']  # Normalize by recent volatility
    bear = bear / df['intra_vol']

    # z_bull = (bull - bull.rolling(z_win).mean()) / (bull.rolling(z_win).std() + 1e-8)
    # z_bear = (bear - bear.rolling(z_win).mean()) / (bear.rolling(z_win).std() + 1e-8)

    # Use rolling min/max instead of mean/std for z-scores
    bull_min = bull.rolling(z_win, min_periods=1).min()
    bull_max = bull.rolling(z_win, min_periods=1).max()
    bear_min = bear.rolling(z_win, min_periods=1).min()
    bear_max = bear.rolling(z_win, min_periods=1).max()
    
    z_bull = (bull - bull_min) / (bull_max - bull_min + 1e-8)
    z_bear = (bear - bear_min) / (bear_max - bear_min + 1e-8)

    # drop previous windows
    z_bull = z_bull.dropna().reset_index(drop=True)
    z_bear = z_bear.dropna().reset_index(drop=True)

    long_pred = (z_bull > 0.8) & (z_bear < 0.2)
    short_pred = (z_bear > 0.8) & (z_bull < 0.2)

    # long_pred  = (z_bull > signal_z) & (z_bear < oppos_z)
    # short_pred = (z_bear > signal_z) & (z_bull < oppos_z)

    direction_pred = np.select(
        [
            long_pred,         # condition 1
            short_pred         # condition 2
        ],
        [
            1,                 # value if long
            -1                 # value if short
        ],
        default = 0            # value if flat
    )

    df['upper'] = df['close'] * np.exp(signal_z * sigma.shift(1))
    df['lower'] = df['close'] * np.exp(-signal_z * sigma.shift(1))

    body_return = np.log(df['close'] / df['open'])
    df['outcome'] = np.select(
        [
            body_return > signal_z * sigma.shift(1),
            body_return < -signal_z * sigma.shift(1)
        ],
        [
            1,
            -1
        ],
        default = 0
    )
    df['body_return'] = body_return
    df = df.drop(df.index[0:z_win-1]).reset_index(drop=True)

    df["direction_pred"] = pd.Series(direction_pred)
    df['long_pred'] = long_pred
    df['short_pred'] = short_pred

    # shift upward by 1 because the current row is the outcome of previous row's prediction
    df['outcome'] = df['outcome'].shift(-1)
    df['result'] = df['outcome'] == df['direction_pred']

    print(df['direction_pred'])
    return df['result'].mean(), df["direction_pred"].iloc[-1]


if __name__ == "__main__":
    start_time, end_time = previous_hours_to_interval(2)
    interval = "1m"
    output_file="./bnb_1m_klines.csv"
    limit = 120

    get_recent_24h_klines(start_time, end_time, limit, interval, output_file, "BNBUSDT")

    df = pd.read_csv("./bnb_1m_klines.csv", parse_dates=["open_time"])

    df = df.drop('volume(Volatile)', axis = 1)
    df = df.drop('volume(USDT)', axis = 1)

    print(five_min_trend(df))
    # print(df['result'].mean())