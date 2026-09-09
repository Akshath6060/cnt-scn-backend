# export_onnx_static.py
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

# Fixed static shape - no dynamic axes
dummy_input = torch.randn(1, 3, 32, 800, dtype=torch.float32)

torch.onnx.export(
    model,
    dummy_input,
    "crnn_static.onnx",
    export_params=True,
    opset_version=17,
    do_constant_folding=True,
    input_names=["image_input"],
    output_names=["logits"],
    dynamo=False
)
print("Successfully exported static ONNX to crnn_static.onnx")
print(f"Size: {os.path.getsize('crnn_static.onnx') / (1024*1024):.2f} MB")
