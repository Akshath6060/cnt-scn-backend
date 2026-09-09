# dataset.py
import os
import cv2
import numpy as np
import pandas as pd
import torch
from torch.utils.data import Dataset
from model import CHAR_TO_IDX

class TextDataset(Dataset):
    def __init__(self, csv_path, img_dir, target_height=32, target_width=800):
        self.df = pd.read_csv(csv_path)
        self.img_dir = img_dir
        self.h = target_height
        self.w = target_width

    def __len__(self):
        return len(self.df)

    def __getitem__(self, idx):
        row = self.df.iloc[idx]
        img_name = str(row['filename'])
        label = str(row['label'])
        
        img_path = os.path.join(self.img_dir, img_name)
        img = cv2.imread(img_path)
        if img is None:
            img = np.full((self.h, self.w, 3), 255, dtype=np.uint8)
        
        # Maintain aspect ratio and scale height to 32px
        h, w, _ = img.shape
        scale = self.h / max(h, 1)
        new_w = min(int(w * scale), self.w)
        resized = cv2.resize(img, (new_w, self.h))
        
        # Right pad canvas with white background (255)
        canvas = np.full((self.h, self.w, 3), 255, dtype=np.uint8)
        canvas[:, :new_w] = resized
        
        # Normalize to [-1.0, 1.0]
        tensor_img = torch.tensor(canvas, dtype=torch.float32).permute(2, 0, 1) / 127.5 - 1.0
        
        # Map label characters to indices, skip unknown
        target_indices = [CHAR_TO_IDX[c] for c in label if c in CHAR_TO_IDX]
        if len(target_indices) == 0:
            target_indices = [CHAR_TO_IDX.get(" ", 1)]
            
        return tensor_img, torch.tensor(target_indices, dtype=torch.long)

def collate_fn(batch):
    images, targets = zip(*batch)
    images = torch.stack(images, dim=0)
    target_lengths = torch.tensor([len(t) for t in targets], dtype=torch.long)
    targets_flat = torch.cat(targets)
    return images, targets_flat, target_lengths
