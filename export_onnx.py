# export_onnx.py
import sys
import os
os.environ["PYTHONIOENCODING"] = "utf-8"
sys.stdout.reconfigure(encoding='utf-8', line_buffering=True)
sys.stderr.reconfigure(encoding='utf-8')
import torch
from model import ResNet18_CRNN

device = torch.device("cpu")
model = ResNet18_CRNN()
model.load_state_dict(torch.load("best_crnn.pth", map_location=device))
model.eval()

# Dummy input: (Batch=1, Channels=3, Height=32, Width=800)
dummy_input = torch.randn(1, 3, 32, 800, dtype=torch.float32)

# Use legacy TorchScript exporter (dynamo=False) to avoid LSTM dynamic shape issues
torch.onnx.export(
    model,
    dummy_input,
    "crnn_handwritten.onnx",
    export_params=True,
    opset_version=17,
    do_constant_folding=True,
    input_names=["image_input"],
    output_names=["logits"],
    dynamic_axes={
        "image_input": {0: "batch_size", 3: "width"},
        "logits": {0: "batch_size", 1: "time_steps"}
    },
    dynamo=False
)
print("Successfully exported to crnn_handwritten.onnx")

# Verify the exported model
import onnx
onnx_model = onnx.load("crnn_handwritten.onnx")
onnx.checker.check_model(onnx_model)
print(f"ONNX model verified. Size: {os.path.getsize('crnn_handwritten.onnx') / (1024*1024):.2f} MB")
