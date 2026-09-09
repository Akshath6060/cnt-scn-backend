"""
Step 6: Fine-tune the existing best_crnn.pth on the combined dataset
(IAM + synthetic digit strings), oversampling digit rows with a
WeightedRandomSampler so they aren't drowned out by IAM's letter-heavy lines.

Install this project in editable mode before running the command.

Usage:
    python scripts/training/finetune.py --combined_dir data/combined \
        --checkpoint artifacts/checkpoints/best_crnn.pth \
        --out artifacts/checkpoints/best_crnn_finetuned.pth --epochs 6 --digit_oversample 8
"""
import argparse
import pandas as pd
import torch
from torch.utils.data import DataLoader, WeightedRandomSampler

from contact_scanner_backend.model import NUM_CLASSES, ResNet18_CRNN
from contact_scanner_backend.dataset import TextDataset, collate_fn


def build_weighted_sampler(csv_path, digit_oversample):
    if digit_oversample <= 0:
        raise ValueError("digit_oversample must be greater than zero")
    df = pd.read_csv(csv_path, dtype={"source": str}, keep_default_na=False)
    if "source" not in df.columns:
        raise ValueError(f"{csv_path} is missing required column: source")
    weights = df["source"].apply(lambda s: digit_oversample if s == "digits" else 1.0).values
    return WeightedRandomSampler(weights=weights, num_samples=len(weights), replacement=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--combined_dir", required=True)
    parser.add_argument("--checkpoint", required=True, help="Path to existing best_crnn.pth")
    parser.add_argument("--out", required=True, help="Path to save the fine-tuned checkpoint")
    parser.add_argument("--epochs", type=int, default=6)
    parser.add_argument("--lr", type=float, default=1e-4, help="Lower LR than original training run")
    parser.add_argument("--batch_size", type=int, default=16)
    parser.add_argument("--digit_oversample", type=float, default=8.0,
                         help="Relative sampling weight for digit-source rows vs IAM rows")
    args = parser.parse_args()

    if args.epochs <= 0 or args.batch_size <= 0 or args.lr <= 0:
        parser.error("--epochs, --batch_size, and --lr must be greater than zero")

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    train_csv = f"{args.combined_dir}/train.csv"
    val_csv = f"{args.combined_dir}/val.csv"
    img_dir = f"{args.combined_dir}/images"

    train_dataset = TextDataset(train_csv, img_dir)
    val_dataset = TextDataset(val_csv, img_dir)

    sampler = build_weighted_sampler(train_csv, args.digit_oversample)
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, sampler=sampler,
                               num_workers=0, pin_memory=True, collate_fn=collate_fn)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False,
                             num_workers=0, pin_memory=True, collate_fn=collate_fn)

    # The checkpoint replaces every parameter, so downloading ImageNet weights
    # here is unnecessary and makes fine-tuning fail in offline environments.
    model = ResNet18_CRNN(num_classes=NUM_CLASSES, pretrained=False).to(device)
    model.load_state_dict(torch.load(args.checkpoint, map_location=device))

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=1e-4)
    criterion = torch.nn.CTCLoss(blank=0, zero_infinity=True)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="min", factor=0.5, patience=2)

    best_val_loss = float("inf")

    for epoch in range(1, args.epochs + 1):
        model.train()
        train_loss = 0.0
        for images, targets, target_lengths in train_loader:
            images, targets = images.to(device), targets.to(device)
            optimizer.zero_grad()

            logits = model(images)  # (B, T, C)
            log_probs = logits.log_softmax(2).permute(1, 0, 2)  # (T, B, C) for CTCLoss
            input_lengths = torch.full((images.size(0),), log_probs.size(0), dtype=torch.long)

            loss = criterion(log_probs, targets, input_lengths, target_lengths)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            train_loss += loss.item()

        train_loss /= len(train_loader)

        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for images, targets, target_lengths in val_loader:
                images, targets = images.to(device), targets.to(device)
                logits = model(images)
                log_probs = logits.log_softmax(2).permute(1, 0, 2)
                input_lengths = torch.full((images.size(0),), log_probs.size(0), dtype=torch.long)
                loss = criterion(log_probs, targets, input_lengths, target_lengths)
                val_loss += loss.item()
        val_loss /= len(val_loader)

        scheduler.step(val_loss)
        print(f"Epoch [{epoch:02d}/{args.epochs}] - Train Loss: {train_loss:.4f} | Val Loss: {val_loss:.4f}")

        if val_loss < best_val_loss:
            best_val_loss = val_loss
            torch.save(model.state_dict(), args.out)
            print(f"  --> Saved best fine-tuned checkpoint to {args.out}")


if __name__ == "__main__":
    main()
