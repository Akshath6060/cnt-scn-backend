# convert_direct.py
import sys
sys.stdout.reconfigure(line_buffering=True)
import os
import torch
import tensorflow as tf
from contact_scanner_backend.model import NUM_CLASSES, ResNet18_CRNN
from contact_scanner_backend.paths import DEFAULT_CHECKPOINT

print("Step 1: Loading PyTorch trained weights...")
pt_model = ResNet18_CRNN(num_classes=NUM_CLASSES, pretrained=False)
pt_model.load_state_dict(torch.load(DEFAULT_CHECKPOINT, map_location="cpu"))
pt_model.eval()

print("Step 2: Building equivalent Keras/TensorFlow model...")
# Input: (Batch, 32, 800, 3) for channels_last in TFLite/TF
# Or channels_first: (Batch, 3, 32, 800)
# Let's use (1, 3, 32, 800) so input format matches PyTorch exactly!

inputs = tf.keras.Input(shape=(3, 32, 800), batch_size=1, name="image_input", dtype=tf.float32)

# ResNet-18 feature extractor recreation in TF
# Or we can build standard TF model with PyTorch weights transferred!
# Let's inspect weights:
sd = pt_model.state_dict()
print(f"PyTorch state_dict has {len(sd)} weight tensors.")
