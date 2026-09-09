"""Evaluate the trained checkpoint against random validation samples."""
import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)
import cv2
import numpy as np
import pandas as pd
import torch
from contact_scanner_backend.model import IDX_TO_CHAR, ResNet18_CRNN
from contact_scanner_backend.paths import DATA_DIR, DEFAULT_CHECKPOINT

def ctc_greedy_decode(logits):
    preds = torch.argmax(logits, dim=2).squeeze(0).cpu().numpy()
    decoded = []
    prev_idx = 0
    for idx in preds:
        if idx != 0 and idx != prev_idx:
            decoded.append(IDX_TO_CHAR.get(idx, ""))
        prev_idx = idx
    return "".join(decoded)

def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = ResNet18_CRNN(pretrained=False).to(device)
    model.load_state_dict(torch.load(DEFAULT_CHECKPOINT, map_location=device))
    model.eval()

    val_df = pd.read_csv(
        DATA_DIR / "val.csv",
        dtype={"filename": str, "label": str},
        keep_default_na=False,
    )
    sample_rows = val_df.sample(min(5, len(val_df))).to_dict("records")

    print("\n--- Model Inference on Real Handwritten Validation Lines ---")
    with torch.no_grad():
        for row in sample_rows:
            img_path = DATA_DIR / "images" / row["filename"]
            img = cv2.imread(str(img_path))
            if img is None:
                continue

            h, w, _ = img.shape
            scale = 32 / max(h, 1)
            new_w = max(1, min(round(w * scale), 800))
            resized = cv2.resize(img, (new_w, 32))

            canvas = np.full((32, 800, 3), 255, dtype=np.uint8)
            canvas[:, :new_w] = resized

            tensor = torch.tensor(canvas, dtype=torch.float32).permute(2, 0, 1) / 127.5 - 1.0
            tensor = tensor.unsqueeze(0).to(device)

            logits = model(tensor)
            pred_text = ctc_greedy_decode(logits)

            print(f"\nGround Truth : {row['label']}")
            print(f"Prediction   : {pred_text}")


if __name__ == "__main__":
    main()
