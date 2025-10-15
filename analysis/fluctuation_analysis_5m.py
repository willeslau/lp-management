import pandas as pd
import numpy as np
import math
from datetime import datetime, timedelta
from binance_price_candle import previous_hours_to_interval, get_recent_24h_klines_dataframe

def rolling_ohlc(df_1m: pd.DataFrame, window: int) -> pd.DataFrame:
    return pd.DataFrame({
        'timestamp':   df_1m['timestamp'].rolling(window).min(),
        'open':  df_1m['open'].rolling(window).apply(lambda x: x[0], raw=True),
        'high':  df_1m['high'].rolling(window).max(),
        'low':   df_1m['low'].rolling(window).min(),
        'close': df_1m['close'].rolling(window).apply(lambda x: x[-1], raw=True),
    }).dropna().reset_index(drop=True)

def gk_ewma_volatility(df, lambda_=0.94, conf_level=0.8):
    h_l = np.log(df['high'] / df['low'])
    c_o = np.log(df['close'] / df['open'])
    
    # Calculate GK components
    gk = 0.5 * (h_l ** 2) - (2 * np.log(2) - 1) * (c_o ** 2)
    gk[gk < 0] = np.abs(gk[gk < 0])  # Handle negatives
    
    # Compute EWMA variance
    ewma_var = gk.ewm(alpha=1-lambda_, adjust=False).mean()
    vol = np.sqrt(ewma_var.iloc[-1])

    z_score = get_z_score(conf_level)
    return (np.exp(-z_score * vol), np.exp(z_score * vol))

def get_z_score(conf: float) -> float:
    z = {0.68: 1, 0.8: 1.28, 0.95: 1.65, 0.99: 2.33}.get(conf, 1.65)
    return z

def evaluation(row, actual_open, actual_high, actual_low, lower_range, upper_range):
    row['upper_band'] = actual_open * upper_range
    row['lower_band'] = actual_open * lower_range

    row['open'] = actual_open
    row['high'] = actual_high
    row['low'] = actual_low

def evaluate_vol_model(df):
    """Evaluates volatility model performance on 5-min candle data"""

    # 1. Band coverage metrics
    metrics = {
        'coverage_high': (df['high'] <= df['upper_band']).mean(),
        'coverage_low': (df['low'] >= df['lower_band']).mean(),
        'full_coverage': ((df['high'] <= df['upper_band']) & 
                         (df['low'] >= df['lower_band'])).mean()
    }
    
    # 2. Breach magnitude
    df['upper_breach'] = np.where(df['high'] > df['upper_band'],
                                 (df['high'] - df['upper_band']) / df['open'],
                                 0)
    df['lower_breach'] = np.where(df['low'] < df['lower_band'],
                                 (df['lower_band'] - df['low']) / df['open'],
                                 0)
    upper_breach = df[df['upper_breach'] > 0]
    lower_breach = df[df['lower_breach'] > 0]

    metrics.update({
        'num_upper_breach': len(upper_breach),
        'avg_upper_breach': upper_breach['upper_breach'].mean(),
        'avg_lower_breach': lower_breach['lower_breach'].mean(),
        'max_upper_breach': df['upper_breach'].max(),
        'max_lower_breach': df['lower_breach'].max()
    })
    
    # 3. Range efficiency
    captured_range = np.minimum(df['upper_band'], df['high']) - \
                           np.maximum(df['lower_band'], df['low'])
    true_range = df['high'] - df['low']
    metrics['range_efficiency'] = (captured_range / true_range).mean()

    # 4. Directional bias
    metrics['asymmetry_ratio'] = (df['high'] > df['upper_band']).mean() / \
                                 max(0.001, (df['low'] < df['lower_band']).mean())
    
    # 5. Economic impact
    df['slippage_cost'] = np.where(df['upper_breach'] > 0, df['upper_breach'],
                                  np.where(df['lower_breach'] > 0, df['lower_breach'], 0))
    metrics['avg_slippage_cost'] = df['slippage_cost'].mean()
    
    # # 6. Volatility regime analysis
    # df['vol_regime'] = pd.qcut(df['vol_pred'], [0, 0.3, 0.7, 1], 
    #                           labels=['low', 'medium', 'high'])
    # regime_stats = df.groupby('vol_regime')['slippage_cost'].mean()
    # metrics.update({f'slippage_{k}': v for k,v in regime_stats.items()})
    
    return metrics

def to_ticks(value):
    x = 0.0
    if value > 1:
        x = np.log(value) - np.log(1)
    else:
        x = np.log(1) - np.log(value)
    y = np.round(x / np.log(1.0001), decimals = 0)
    return int(y)

def run_detection():
    start_time, end_time = previous_hours_to_interval(3)
    interval = "1m"
    limit = 180

    df = get_recent_24h_klines_dataframe(start_time, end_time, limit, interval, "BNBBTC")

    df = rolling_ohlc(df, 5)

    decay = 0.94
    conf = 0.8

    df = df.sort_values("timestamp").reset_index(drop=True)

    best_look_back = 1
    best_metrics = {'coverage_high': 0}

    end = len(df)
    for look_back in range(1, 15):
        records = []
        for i in range(look_back, end):
            train = df[i - look_back : i]

            (lower, higher) = gk_ewma_volatility(train, lambda_ = decay, conf_level = conf)
            row = {'estimator': 'GK_EWMA', 'lower_range': lower, 'higher_range': higher}

            next_row = df.iloc[i]
            evaluation(row, next_row['open'], next_row['high'], next_row['low'], lower, higher)
            records.append(row)

        summary = pd.DataFrame(records)
        metrics = evaluate_vol_model(summary)

        if metrics['coverage_high'] > best_metrics['coverage_high']:
            best_look_back = look_back
            best_metrics = metrics
            # mean_tick = math.ceil(summary['higher_range'].apply(lambda x: to_ticks(x)).mean())
            mean_tick = summary['higher_range'].mean() - 1
    
    return {
        "metrics": metrics, "duration": best_look_back, "range": mean_tick
    }
