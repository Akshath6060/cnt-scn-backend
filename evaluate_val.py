# evaluate_val.py
import sys
sys.stdout.reconfigure(line_buffering=True)
import random
import cv2
import numpy as np
import pandas as pd
import torch
from model import ResNet18_CRNN, CHARS, IDX_TO_CHAR

def ctc_greedy_decode(logits):
    preds = torch.argmax(logits, dim=2).squeeze(0).cpu().numpy()
    decoded = []
    prev_idx = 0
    for idx in preds:
        if idx != 0 and idx != prev_idx:
            decoded.append(IDX_TO_CHAR.get(idx, ""))
        prev_idx = idx
    return "".join(decoded)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model = ResNet18_CRNN().to(device)
model.load_state_dict(torch.load("best_crnn.pth", map_location=device))
model.eval()

val_df = pd.read_csv("data/val.csv")
sample_rows = val_df.sample(5).to_dict("records")

print("\n--- Model Inference on Real Handwritten Validation Lines ---")
with torch.no_grad():
    for row in sample_rows:
        img_path = f"data/images/{row['filename']}"
        img = cv2.imread(img_path)
        if img is None:
            continue
            
        h, w, _ = img.shape
        scale = 32 / max(h, 1)
        new_w = min(int(w * scale), 800)
        resized = cv2.resize(img, (new_w, 32))
        
        canvas = np.full((32, 800, 3), 255, dtype=np.uint8)
        canvas[:, :new_w] = resized
        
        tensor = torch.tensor(canvas, dtype=torch.float32).permute(2, 0, 1) / 127.5 - 1.0
        tensor = tensor.unsqueeze(0).to(device)
        
        logits = model(tensor)
        pred_text = ctc_greedy_decode(logits)
        
        print(f"\nGround Truth : {row['label']}")
        print(f"Prediction   : {pred_text}")
