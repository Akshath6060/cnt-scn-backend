# test_forward.py
import torch
from model import ResNet18_CRNN, NUM_CLASSES

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Testing on device: {device}")

model = ResNet18_CRNN().to(device)
model.eval()

# Simulate a batch of 4 cropped text line images (B=4, C=3, H=32, W=280)
dummy_tensor = torch.randn(4, 3, 32, 280, device=device)

with torch.no_grad():
    output = model(dummy_tensor)

print("Forward pass successful.")
print("Output logits shape (Batch, TimeSteps, Classes):", output.shape)
assert output.shape == (4, 35, NUM_CLASSES), f"Unexpected output shape: {output.shape}"
print("Shape verified.")
