"""
Step 3: Stitch isolated digits (from digit_pool/<0-9>/*.png) into synthetic
10-digit "phone number" line images, matching the project's target format:
  - Height 32px, width up to 800px, aspect-ratio preserved, white-padded remainder
  - Grayscale digits pasted onto a white line canvas with random spacing/jitter

Produces:
  data/synthetic_digits/images/*.png
  data/synthetic_digits/train.csv   (90%)
  data/synthetic_digits/val.csv     (10%)

IMPORTANT: This assumes your existing train.csv/val.csv use columns
"filename,label". If your dataset.py uses different column names,
rename the header line accordingly before merging (Step 5 handles this too).

Usage:
    python 03_stitch_digit_strings.py --pool data/digit_pool --out data/synthetic_digits --num_samples 20000
"""
import argparse
import os
import random
import csv
from PIL import Image, ImageOps
import numpy as np

TARGET_H = 32
TARGET_W = 800
DIGIT_LEN = 10


def load_pool(pool_dir):
    pool = {d: [] for d in range(10)}
    for d in range(10):
        digit_dir = os.path.join(pool_dir, str(d))
        if not os.path.isdir(digit_dir):
            continue
        for fname in os.listdir(digit_dir):
            if fname.lower().endswith((".png", ".jpg", ".jpeg")):
                pool[d].append(os.path.join(digit_dir, fname))
    for d in range(10):
        if len(pool[d]) == 0:
            raise RuntimeError(f"No images found for digit {d} in {pool_dir}")
    return pool


def random_digit_glyph(pool, digit, base_size=40):
    """Load a digit image, invert if needed (MNIST is white-on-black),
    resize to a random cell height, apply light rotation jitter."""
    path = random.choice(pool[digit])
    img = Image.open(path).convert("L")

    # MNIST-style images are white digit on black background; invert to
    # black digit on white background to match handwriting-on-paper look.
    arr = np.array(img)
    if arr.mean() < 127:  # mostly dark background -> invert
        img = ImageOps.invert(img)

    size = base_size + random.randint(-4, 4)
    img = img.resize((size, size), Image.BILINEAR)

    angle = random.uniform(-8, 8)
    img = img.rotate(angle, expand=True, fillcolor=255)
    return img


def build_line_image(pool, digit_string, cell_h=40):
    glyphs = [random_digit_glyph(pool, int(c), base_size=cell_h) for c in digit_string]

    spacing = random.randint(2, 10)
    total_w = sum(g.width for g in glyphs) + spacing * (len(glyphs) - 1) + 20
    total_h = max(g.height for g in glyphs) + 10

    canvas = Image.new("L", (total_w, total_h), color=255)
    x = 10
    baseline_jitter = 4
    for g in glyphs:
        y = (total_h - g.height) // 2 + random.randint(-baseline_jitter, baseline_jitter)
        canvas.paste(g, (x, max(0, y)))
        x += g.width + spacing

    return canvas


def resize_pad_to_target(img):
    """Match the project's dataset.py convention: scale height to 32px,
    proportional width up to 800px, right-pad remainder with white (255)."""
    w, h = img.size
    scale = TARGET_H / h
    new_w = min(TARGET_W, int(w * scale))
    img = img.resize((new_w, TARGET_H), Image.BILINEAR)

    padded = Image.new("L", (TARGET_W, TARGET_H), color=255)
    padded.paste(img, (0, 0))
    return padded


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pool", required=True, help="digit_pool root from steps 01/02")
    parser.add_argument("--out", required=True, help="Output folder for synthetic images + CSVs")
    parser.add_argument("--num_samples", type=int, default=20000)
    parser.add_argument("--val_frac", type=float, default=0.10)
    args = parser.parse_args()

    pool = load_pool(args.pool)
    img_out_dir = os.path.join(args.out, "images")
    os.makedirs(img_out_dir, exist_ok=True)

    rows = []
    for i in range(args.num_samples):
        digit_string = "".join(str(random.randint(0, 9)) for _ in range(DIGIT_LEN))
        line_img = build_line_image(pool, digit_string)
        final_img = resize_pad_to_target(line_img)

        fname = f"synth_digits_{i:06d}.png"
        final_img.save(os.path.join(img_out_dir, fname))
        rows.append((fname, digit_string))

        if (i + 1) % 2000 == 0:
            print(f"Generated {i + 1}/{args.num_samples}")

    random.shuffle(rows)
    val_count = int(len(rows) * args.val_frac)
    val_rows = rows[:val_count]
    train_rows = rows[val_count:]

    for split_name, split_rows in [("train.csv", train_rows), ("val.csv", val_rows)]:
        with open(os.path.join(args.out, split_name), "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["filename", "label"])
            for fname, label in split_rows:
                writer.writerow([fname, label])

    print(f"Wrote {len(train_rows)} train rows and {len(val_rows)} val rows to {args.out}")


if __name__ == "__main__":
    main()
