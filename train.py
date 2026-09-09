# train.py
import sys
sys.stdout.reconfigure(line_buffering=True)
import torch
import torch.nn as nn
from torch.utils.data import DataLoader
from model import ResNet18_CRNN, NUM_CLASSES
from dataset import TextDataset, collate_fn

BATCH_SIZE = 16  # Width is 800, 16 fits comfortably in 8GB VRAM
EPOCHS = 20
LEARNING_RATE = 3e-4

def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Training on device: {device} ({torch.cuda.get_device_name(0)})")

    train_dataset = TextDataset("data/train.csv", "data/images", target_height=32, target_width=800)
    val_dataset = TextDataset("data/val.csv", "data/images", target_height=32, target_width=800)

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True, collate_fn=collate_fn, num_workers=0, pin_memory=True)
    val_loader = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False, collate_fn=collate_fn, num_workers=0, pin_memory=True)

    model = ResNet18_CRNN(num_classes=NUM_CLASSES).to(device)
    criterion = nn.CTCLoss(blank=0, zero_infinity=True)
    optimizer = torch.optim.AdamW(model.parameters(), lr=LEARNING_RATE, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=2)

    best_loss = float("inf")

    for epoch in range(1, EPOCHS + 1):
        model.train()
        total_train_loss = 0.0
        
        for images, targets, target_lengths in train_loader:
            images = images.to(device)
            targets = targets.to(device)
            
            optimizer.zero_grad()
            logits = model(images)  # Shape: (Batch, TimeSteps, Classes)
            
            batch_size = images.size(0)
            time_steps = logits.size(1)
            input_lengths = torch.full(size=(batch_size,), fill_value=time_steps, dtype=torch.long, device=device)
            
            log_probs = logits.log_softmax(2).permute(1, 0, 2)
            loss = criterion(log_probs, targets, input_lengths, target_lengths)
            
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            
            total_train_loss += loss.item()
            
        avg_train_loss = total_train_loss / len(train_loader)
        
        model.eval()
        total_val_loss = 0.0
        with torch.no_grad():
            for images, targets, target_lengths in val_loader:
                images = images.to(device)
                targets = targets.to(device)
                
                logits = model(images)
                batch_size = images.size(0)
                input_lengths = torch.full(size=(batch_size,), fill_value=logits.size(1), dtype=torch.long, device=device)
                
                log_probs = logits.log_softmax(2).permute(1, 0, 2)
                loss = criterion(log_probs, targets, input_lengths, target_lengths)
                total_val_loss += loss.item()
                
        avg_val_loss = total_val_loss / len(val_loader)
        scheduler.step(avg_val_loss)
        
        print(f"Epoch [{epoch:02d}/{EPOCHS:02d}] - Train Loss: {avg_train_loss:.4f} | Val Loss: {avg_val_loss:.4f}")
        
        if avg_val_loss < best_loss:
            best_loss = avg_val_loss
            torch.save(model.state_dict(), "best_crnn.pth")
            print(f"  --> Saved new best checkpoint (Val Loss: {best_loss:.4f})")

    print("Training finished. File saved as best_crnn.pth")

if __name__ == '__main__':
    main()
