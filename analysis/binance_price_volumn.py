import os
import pandas as pd

def process_single_file(filepath):
    """Reads a file and returns volume summary by 1-decimal price bins."""
    df = pd.read_csv(filepath, dtype={"price": float, "qty": float, "is_maker": str})
    df["is_maker"] = df["is_maker"].str.lower() == "true"
    price_to_price_bin(df)

    maker_vol = df[df["is_maker"]].groupby("price_bin")["qty"].sum().rename("maker_volume")
    taker_vol = df[~df["is_maker"]].groupby("price_bin")["qty"].sum().rename("taker_volume")

    summary = pd.concat([maker_vol, taker_vol], axis=1).fillna(0)
    summary["total_volume"] = summary["maker_volume"] + summary["taker_volume"]
    return summary

def price_to_price_bin(df):
    df["price_bin"] = (1 / df["price"].astype(float) // 0.05) * 0.05
    # df["price_bin"] = (df["price"].astype(float) // 0.05) * 0.05
    # df["price_bin"] = (df["price"].astype(float) // 0.0000001) * 0.0000001

def aggregate_volume_by_price(folder_path: str, output_file: str):
    all_summaries = []

    for filename in os.listdir(folder_path):
        if not filename.endswith(".csv"):
            continue
        filepath = os.path.join(folder_path, filename)
        print(f"Processing {filename}...")
        summary = process_single_file(filepath)
        all_summaries.append(summary)

    print(f"Combining {len(all_summaries)} partial summaries...")
    full_summary = pd.concat(all_summaries)
    combined = full_summary.groupby(full_summary.index).sum()
    combined["total_volume"] = combined["maker_volume"] + combined["taker_volume"]

    combined = combined.reset_index().rename(columns={"price_bin": "price"})
    combined = combined.sort_values("price")

    # plot_volume_summary(combined)

    combined.to_csv(output_file, index=False)
    print(f"Final summary written to {output_file}")
    return combined

from collections import defaultdict

def calculate_price_duration(folder_path, output_csv="price_duration.csv", round_to=1):
    durations = defaultdict(int)  # {rounded_price: total_duration_ms}

    # Process each file in chronological order (based on filename)
    files = sorted(f for f in os.listdir(folder_path) if f.endswith(".csv"))

    last_price = None
    last_time = None

    for file in files:
        filepath = os.path.join(folder_path, file)
        print(f"Processing {file}...")
        df = pd.read_csv(filepath, usecols=["timestamp_ms", "price"])
        df["timestamp_ms"] = pd.to_numeric(df["timestamp_ms"])
        price_to_price_bin(df)

        for row in df.itertuples():
            curr_time = row.timestamp_ms
            curr_price = row.price_bin

            if last_price is not None:
                duration = curr_time - last_time
                durations[last_price] += duration

            last_price = curr_price
            last_time = curr_time

    # Save to CSV
    result_df = pd.DataFrame([
        {"price": price, "duration_ms": duration, "duration_sec": duration / 1000}
        for price, duration in durations.items()
    ])
    result_df = result_df.sort_values("price")
    result_df.to_csv(output_csv, index=False)
    return result_df

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

    volumn = aggregate_volume_by_price(folder_path="./data/trades/" + symbol, output_file=symbol + "_price_volumn.csv")
    duration = calculate_price_duration("./data/trades/" + symbol, output_csv=symbol + "_price_duration.csv")

    plot_volume_and_duration(volumn, duration)
