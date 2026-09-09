# download_iam.py
import os
import cv2
import pandas as pd
from datasets import load_dataset

print("Downloading real handwritten line samples from IAM...")
os.makedirs("data/images", exist_ok=True)

# Load the lines partition of IAM
dataset = load_dataset("Teklia/IAM-line", split="train", streaming=True)

records = []
count = 0
MAX_SAMPLES = 8000  # Pull 8,000 real human lines

for item in dataset:
    text = item["text"].strip()
    image = item["image"]
    
    filename = f"iam_{count:05d}.png"
    filepath = os.path.join("data/images", filename)
    
    # Save the scanned human handwritten strip
    image.save(filepath)
    records.append({"filename": filename, "label": text})
    
    count += 1
    if count % 500 == 0:
        print(f"Processed {count} human handwriting samples...")
    if count >= MAX_SAMPLES:
        break

df = pd.DataFrame(records)
# Split 90% train, 10% val
train_df = df.iloc[: int(0.9 * len(df))]
val_df = df.iloc[int(0.9 * len(df)) :]

train_df.to_csv("data/train.csv", index=False)
val_df.to_csv("data/val.csv", index=False)
print("Real handwritten dataset prepared at data/train.csv and data/val.csv")
