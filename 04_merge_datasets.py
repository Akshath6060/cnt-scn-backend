"""
Step 5: Merge your existing IAM train/val CSVs with the new synthetic
digit-string CSVs into one combined manifest per split, tagging each row
with its source so we can oversample digit rows during fine-tuning.

Adjust COLUMN NAMES below if your existing data/train.csv / data/val.csv
use different headers than "filename,label" (check dataset.py to confirm).

Usage:
    python 04_merge_datasets.py \
        --iam_train data/train.csv --iam_val data/val.csv \
        --iam_img_dir data/images \
        --digits_train data/synthetic_digits/train.csv --digits_val data/synthetic_digits/val.csv \
        --digits_img_dir data/synthetic_digits/images \
        --out data/combined
"""
import argparse
import os
import shutil
import pandas as pd


def merge_split(iam_csv, iam_img_dir, digits_csv, digits_img_dir, out_dir, split_name):
    os.makedirs(os.path.join(out_dir, "images"), exist_ok=True)

    iam_df = pd.read_csv(iam_csv)
    iam_df.columns = ["filename", "label"]  # rename if your headers differ
    iam_df["source"] = "iam"

    digits_df = pd.read_csv(digits_csv)
    digits_df.columns = ["filename", "label"]
    digits_df["source"] = "digits"

    # Copy images into one shared folder, prefixing filenames per source
    # to avoid collisions.
    def copy_and_rename(df, src_dir, prefix):
        new_names = []
        for fname in df["filename"]:
            new_name = f"{prefix}_{fname}"
            shutil.copy(os.path.join(src_dir, fname), os.path.join(out_dir, "images", new_name))
            new_names.append(new_name)
        df["filename"] = new_names
        return df

    iam_df = copy_and_rename(iam_df, iam_img_dir, "iam")
    digits_df = copy_and_rename(digits_df, digits_img_dir, "digits")

    combined = pd.concat([iam_df, digits_df], ignore_index=True)
    combined.to_csv(os.path.join(out_dir, f"{split_name}.csv"), index=False)
    print(f"{split_name}: {len(iam_df)} IAM rows + {len(digits_df)} digit rows = {len(combined)} total")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iam_train", required=True)
    parser.add_argument("--iam_val", required=True)
    parser.add_argument("--iam_img_dir", required=True)
    parser.add_argument("--digits_train", required=True)
    parser.add_argument("--digits_val", required=True)
    parser.add_argument("--digits_img_dir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    merge_split(args.iam_train, args.iam_img_dir, args.digits_train, args.digits_img_dir, args.out, "train")
    merge_split(args.iam_val, args.iam_img_dir, args.digits_val, args.digits_img_dir, args.out, "val")


if __name__ == "__main__":
    main()
