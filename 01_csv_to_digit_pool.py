"""
Step 2a: Convert the Kaggle 'Digit Recognizer' (MNIST) CSV into a
folder-per-digit image pool: digit_pool/<label>/<idx>.png

Usage:
    python 01_csv_to_digit_pool.py --csv data/kaggle_mnist/train.csv --out data/digit_pool
"""
import argparse
import os
import numpy as np
from PIL import Image
import pandas as pd


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True, help="Path to Kaggle train.csv (label + 784 pixel cols)")
    parser.add_argument("--out", required=True, help="Output root folder for digit_pool/<label>/*.png")
    args = parser.parse_args()

    df = pd.read_csv(args.csv)
    has_label = "label" in df.columns

    for d in range(10):
        os.makedirs(os.path.join(args.out, str(d)), exist_ok=True)

    counters = {d: 0 for d in range(10)}

    for _, row in df.iterrows():
        if not has_label:
            break  # test.csv has no labels, skip
        label = int(row["label"])
        pixels = row.drop("label").values.astype(np.uint8).reshape(28, 28)
        img = Image.fromarray(pixels, mode="L")
        idx = counters[label]
        img.save(os.path.join(args.out, str(label), f"mnist_{idx:05d}.png"))
        counters[label] += 1

    print("Done. Per-digit counts:", counters)


if __name__ == "__main__":
    main()
