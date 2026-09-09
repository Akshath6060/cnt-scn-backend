"""
Step 2b: Merge additional digit datasets (e.g. the Swiss handwritten
digits set, or the "not in MNIST" set) into the same digit_pool.

Both of those Kaggle sets are already organized as folder-per-digit
(0/, 1/, ... 9/) or close to it. If the folder names don't match exactly,
adjust LABEL_MAP below after checking the extracted zip's structure.

Usage:
    python 02_merge_digit_pool.py --src data/kaggle_swiss --out data/digit_pool --prefix swiss
    python 02_merge_digit_pool.py --src data/kaggle_notmnist --out data/digit_pool --prefix nm
"""
import argparse
import os
import shutil


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--src", required=True, help="Root of the extracted dataset (contains 0/,1/,...,9/ folders)")
    parser.add_argument("--out", required=True, help="Shared digit_pool root (same as script 01's --out)")
    parser.add_argument("--prefix", required=True, help="Unique filename prefix to avoid collisions, e.g. 'swiss'")
    args = parser.parse_args()

    for d in range(10):
        src_dir = os.path.join(args.src, str(d))
        dst_dir = os.path.join(args.out, str(d))
        os.makedirs(dst_dir, exist_ok=True)

        if not os.path.isdir(src_dir):
            print(f"WARNING: {src_dir} not found — check the extracted folder structure "
                  f"and rename/adjust if this dataset uses different label folder names.")
            continue

        count = 0
        for fname in os.listdir(src_dir):
            if not fname.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            src_path = os.path.join(src_dir, fname)
            dst_path = os.path.join(dst_dir, f"{args.prefix}_{count:05d}.png")
            shutil.copy(src_path, dst_path)
            count += 1

        print(f"Digit {d}: copied {count} images from {src_dir}")


if __name__ == "__main__":
    main()
