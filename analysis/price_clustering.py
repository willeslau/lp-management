import os
import time
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from dateutil import tz

from sklearn.cluster import DBSCAN
from sklearn.neighbors import NearestNeighbors
from sklearn.neighbors import KernelDensity
from sklearn.mixture import GaussianMixture
from scipy.stats import norm

from sklearn.cluster import MeanShift
from scipy.stats import gaussian_kde

def generate_liquidity_bands(data, bandwidth=0.5):
    """
    Generate liquidity bands using kernel density estimation
    and mean shift clustering with volume-duration weighting
    """
    # Calculate weighted density
    prices = data['price_bin'].values
    weights = data['weight'].values

    # Create weighted KDE
    kde = gaussian_kde(prices, weights=weights)
    
    # Generate evaluation points
    price_range = np.linspace(min(prices)*0.99, max(prices)*1.01, 1000)
    density = kde.evaluate(price_range)
    
    # Find density peaks
    peaks = []
    for i in range(1, len(price_range)-1):
        if density[i] > density[i-1] and density[i] > density[i+1]:
            if density[i] > max(density)*0.1:  # Min peak threshold
                peaks.append(price_range[i])
    print(peaks)
    # Mean shift clustering with peak initialization
    ms = MeanShift(bandwidth=bandwidth, seeds=np.array(peaks).reshape(-1,1))
    ms.fit(prices.reshape(-1,1))
    
    # Extract clusters
    bands = []
    for center in ms.cluster_centers_:
        # Get cluster points
        mask = ms.labels_ == np.where(ms.cluster_centers_ == center)[0][0]
        cluster_prices = prices[mask]
        
        # Create band around cluster
        std_dev = np.std(cluster_prices)
        band_min = max(min(cluster_prices) - 0.5*std_dev, min(prices))
        band_max = min(max(cluster_prices) + 0.5*std_dev, max(prices))
        bands.append((band_min, band_max))
    
    return sorted(bands, key=lambda x: x[0])

# Usage in workflow
def generate_bands(data, current_time):
    # Calculate weights first (as before)
    weighted_data = calculate_weights(data, current_time)
    
    # Generate bands
    return generate_liquidity_bands(weighted_data, bandwidth=1.0)

def weighted_resample(data, n_samples=10000):
    """Resample data based on weights"""
    weights = data['weight'].values

    # Normalize weights to probabilities
    weights = weights / np.sum(weights)
    
    # Resample with replacement
    indices = np.random.choice(
        np.arange(len(data)), 
        size=n_samples, 
        p=weights,
        replace=True
    )
    return data.iloc[indices]['price_bin'].copy()

def gmm_bands(data, n_bands, coverage_threshold=0.9):
    sampled = weighted_resample(data, n_samples = 10 * len(data)).values.reshape(-1, 1)

    # plt.scatter(sampled, sampled)
    # plt.xlabel('X')
    # plt.ylabel('Y')
    # plt.title('Scatter Plot of 2D Array')
    # plt.grid(True)
    # plt.show()

    # Weighted GMM
    gmm = GaussianMixture(n_components=n_bands, covariance_type='full')
    gmm.fit(sampled)
    
    # Extract parameters
    means = gmm.means_.flatten()
    covariances = gmm.covariances_.flatten()
    weights = gmm.weights_
    
    # Create density-based bands
    bands = []
    weighted_bands = []
    for i in range(n_bands):
        std_dev = np.sqrt(covariances[i])
        lower = norm.ppf(0.05, loc=means[i], scale=std_dev)
        upper = norm.ppf(0.95, loc=means[i], scale=std_dev)

        print("ranges", weights[i], lower, upper, "\r")
        weighted_bands.append((weights[i], lower, upper))
        bands.append((lower, upper))

    # # Plot the price time series
    # plt.scatter(data["weight"].values, data["price_bin"].values)

    # # Overlay GMM bands
    # for i, (lower, upper) in enumerate(bands):
    #     plt.axhspan(lower, upper, alpha=0.2, label=f'Band {i+1}')

    # plt.xlabel("Time / Index")
    # plt.ylabel("Price")
    # plt.title("Price vs GMM Bands")
    # plt.legend()
    # plt.grid(True)
    # plt.show()
    return bands

from scipy.integrate import simpson

def kde_bands(data, n_bands = 3, bandwidth=0.003):
    kde = KernelDensity(kernel='gaussian', bandwidth = bandwidth)

    prices = data['price_bin'].values
    prices = prices.reshape(-1, 1)

    weights = data['weight'].values
    weights.reshape(1, -1)
    
    kde.fit(prices, sample_weight = weights)
    
    grid = np.arange(prices.min(), prices.max(), 0.0002).reshape(-1,1)
    pdf  = np.exp(kde.score_samples(grid))

    # 3. Find level that covers 90 % of mass
    cdf = np.cumsum(pdf) / pdf.sum()
    mask = cdf <= 0.90
    level90 = pdf[mask][-1]          # last density inside 90 %

    # 4. Extract contiguous intervals where pdf >= level90
    bands = []
    current = None
    for p, x in zip(pdf, grid.flatten()):
        if p >= level90:
            current = [x] if current is None else current
            last = x
        elif current is not None:
            bands.append((current[0], last))
            current = None
    # Possible tail band still open
    if current is not None:
        bands.append((current[0], last))

    band_masses = []
    for lo, hi in bands:
        mask = (grid.flatten() >= lo) & (grid.flatten() <= hi)
        mass = simpson(pdf[mask], grid.flatten()[mask])
        band_masses.append((mass, (lo, hi)))

    # Sort by mass
    band_masses.sort(reverse=True)
    top_n_bands = [b for _, b in band_masses[:n_bands]]

    # Optional: merge close bands (<0.001 apart in log-price)
    merged_bands = []
    for band in sorted(top_n_bands):
        if not merged_bands:
            merged_bands.append(band)
        else:
            last_lo, last_hi = merged_bands[-1]
            if band[0] - last_hi < 0.001:  # adjustable
                merged_bands[-1] = (last_lo, band[1])
            else:
                merged_bands.append(band)
    return merged_bands
    # # Create density-based bands
    # bands = []
    # weighted_bands = []
    # for i in range(n_bands):
    #     std_dev = np.sqrt(covariances[i])
    #     lower = norm.ppf(0.05, loc=means[i], scale=std_dev)
    #     upper = norm.ppf(0.95, loc=means[i], scale=std_dev)

    #     print("ranges", weights[i], lower, upper, "\r")
    #     weighted_bands.append((weights[i], lower, upper))
    #     bands.append((lower, upper))

    # # Plot the price time series
    # plt.scatter(data["weight"].values, data["price_bin"].values)

    # # Overlay GMM bands
    # for i, (lower, upper) in enumerate(bands):
    #     plt.axhspan(lower, upper, alpha=0.2, label=f'Band {i+1}')

    # plt.xlabel("Time / Index")
    # plt.ylabel("Price")
    # plt.title("Price vs GMM Bands")
    # plt.legend()
    # plt.grid(True)
    # plt.show()
    # return bands
    

from sklearn.preprocessing import StandardScaler


def dbscan_bands(data, min_samples=5, eps=1):
    log_prices = np.log(data['price'])
    X = log_prices.values.reshape(-1, 1)
    X_scaled = StandardScaler().fit_transform(X)

    db = DBSCAN(eps=0.03, min_samples=10).fit(X_scaled)
    labels = db.labels_

    unique_labels = set(labels)
    bands = []

    for label in unique_labels:
        if label == -1:
            continue  # noise
        cluster_prices = np.exp(log_prices[labels == label])
        lo, hi = cluster_prices.min(), cluster_prices.max()
        bands.append((lo, hi))
    return bands

def time_based_split(data, current_time=None):
    """
    Split data into train, test, validation sets based on time windows
    - Training: current_time - 12 hours to current_time - 1 hour
    - Test: current_time - 1 hour to current_time - 30 minutes
    - Validation: current_time - 30 minutes to current_time
    """
    if current_time is None:
        current_time = data['timestamp_ms'].max()

    # Calculate time boundaries
    train_start = current_time - timedelta(hours=12).total_seconds() * 1000
    train_end = current_time - timedelta(minutes=10).total_seconds() * 1000
    test_end = current_time - timedelta(minutes=5).total_seconds() * 1000
    
    # Create masks for filtering
    train_mask = (data['timestamp_ms'] >= train_start) & (data['timestamp_ms'] < train_end)
    test_mask = (data['timestamp_ms'] >= train_end) & (data['timestamp_ms'] < test_end)
    val_mask = (data['timestamp_ms'] >= test_end) & (data['timestamp_ms'] <= current_time)
    
    # Split the data
    train_data = data[train_mask].copy()
    test_data = data[test_mask].copy()
    val_data = data[val_mask].copy()

    return train_data, test_data, val_data

def evaluate_coverage(bands, data):
    """Evaluate duration and volume coverage of bands"""
    total_duration = data['duration'].sum()
    total_volume = data['volume'].sum()

    coverage = []
    for band in bands:
        in_band = data[(data['price'] >= band[0]) & (data['price'] < band[1])]
        dur_coverage = in_band['duration'].sum() / total_duration
        vol_coverage = in_band['volume'].sum() / total_volume
        coverage.append({
            'band': band,
            'duration_coverage': dur_coverage,
            'volume_coverage': vol_coverage
        })
    
    return pd.DataFrame(coverage)

# def calculate_weights(data, current_time, lambda_recency=0.1):
#     """Calculate weights based on volume, duration, and recency"""
#     # Normalize features
#     data['duration_norm'] = data['duration'] / data['duration'].max()
#     data['volume_norm'] = data['volume'] / data['volume'].max()
    
#     # Calculate recency weight (exponential decay)
#     time_diff = (current_time - data['timestamp']).dt.total_seconds()
#     data['recency_weight'] = np.exp(-lambda_recency * time_diff)
    
#     # Combined weight (geometric mean)
#     data['weight'] = (data['duration_norm'] * data['volume_norm'] * data['recency_weight']) ** (1/3)
    
#     return data[['price', 'duration', 'volume', 'timestamp', 'weight']]

def price_to_price_bin(df, is_invert, round_to):
    if is_invert:
        df["price_bin"] = 1 / df["price"].astype(float) // round_to * round_to    
    else:
        df["price_bin"] = df["price"].astype(float) // round_to * round_to

from collections import defaultdict

def calculate_duration(df):
    df["duration"] = df['timestamp_ms'].shift(-1) - df['timestamp_ms']

def data_prep(df, is_invert=False, price_bin_size=0.01):
    price_to_price_bin(df, is_invert, price_bin_size)
    
    latest_time = df.iloc[-1]['timestamp_ms']

    calculate_duration(df)
    df = df.drop(['price', 'timestamp_ms'], axis=1)

    grouped = df.groupby('price_bin').sum()
    grouped = grouped.reset_index()

    return latest_time, grouped

def calculate_weights(data, current_time, lambda_recency=0.1):
    """Calculate weights based on volume, duration, and recency"""
    # Normalize features
    data['duration_norm'] = data['duration'] / data['duration'].max()
    data['volume_norm'] = data['volume'] / data['volume'].max()
    
    # # Calculate recency weight (exponential decay)
    # time_diff = current_time - data['timestamp_ms']
    # data['recency_weight'] = np.exp(-lambda_recency * time_diff / 1000)

    # Combined weight (geometric mean)
    data['weight'] = 0.7 * data['duration_norm'] + 0.3 * data['volume_norm']

    # return data[['price', 'duration', 'volume', 'weight']]
    return data[['price_bin', 'duration', 'volume', 'weight']]

import matplotlib.pyplot as plt

def plot_volume_and_duration(df_vol, df_dur, title="Volume & Duration by Price"):
    # Ensure price is float and sorted
    df_vol["price"] = df_vol["price"].astype(float)
    df_dur["price"] = df_dur["price"].astype(float)

    df = pd.merge(df_vol, df_dur, on="price", how="inner").sort_values("price")

    # Plot
    fig, ax1 = plt.subplots(figsize=(14, 6))

    # Volume on left axis
    ax1.set_xlabel("Price")
    ax1.set_ylabel("Total Volume", color="tab:blue")
    ax1.plot(df["price"], df["total_volume"], label="Total Volume", color="tab:blue", linewidth=2)
    ax1.tick_params(axis='y', labelcolor="tab:blue")

    # Duration on right axis
    ax2 = ax1.twinx()
    ax2.set_ylabel("Duration (seconds)", color="tab:red")
    ax2.plot(df["price"], df["duration_sec"], label="Duration", color="tab:red", linewidth=2, linestyle="dashed")
    ax2.tick_params(axis='y', labelcolor="tab:red")

    # Title and grid
    plt.title(title)
    ax1.grid(True)
    fig.tight_layout()
    plt.show()

# 🧪 Example usage
if __name__ == "__main__":
    symbol = "BNBBTC"
    filepath = "./data/trades/" + symbol + "/1.csv"

    df = pd.read_csv(filepath, usecols=["timestamp_ms", "price", "qty"])
    df = df.rename(columns={'qty': 'volume'})

    # make sure it is ordered ascending by timestamp
    df.sort_values("timestamp_ms")
    df['price'] = 1 / df['price']

    # print(len(df))
    train, test, validation = time_based_split(df)
    calculate_duration(train)

    train_eva = train.copy()
    
    # bands = dbscan_bands(train)
    
    (latest_time, train) = data_prep(train)
    # train.sort_values("price_bin")
    # calculate_weights(train, latest_time)

    # bands = gmm_bands(train, 3)
    # bands = dbscan_bands(train, min_samples = 3)


    # bands = kde_bands(train)

    bands = generate_bands(train, latest_time)
    print(bands)
    test_result = evaluate_coverage(bands, train_eva)
    print(test_result)

    calculate_duration(test)
    test_result = evaluate_coverage(bands, test)
    print(test_result)

    calculate_duration(validation)
    test_result = evaluate_coverage(bands, validation)
    print(test_result)




    # volumn = aggregate_volume_by_price(folder_path="./data/trades/" + symbol, output_file=symbol + "_price_volumn.csv")
    # duration = calculate_price_duration("./data/trades/" + symbol, output_csv=symbol + "_price_duration.csv")

    # plot_volume_and_duration(volumn, duration)

