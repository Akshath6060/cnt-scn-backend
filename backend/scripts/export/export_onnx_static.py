# export_onnx_static.py
import sys
import os
os.environ["PYTHONIOENCODING"] = "utf-8"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")
import torch
from contact_scanner_backend.model import ResNet18_CRNN
from contact_scanner_backend.paths import DEFAULT_CHECKPOINT, DEFAULT_STATIC_ONNX_MODEL

def main():
    device = torch.device("cpu")
    model = ResNet18_CRNN(pretrained=False)
    model.load_state_dict(torch.load(DEFAULT_CHECKPOINT, map_location=device))
    model.eval()

    dummy_input = torch.randn(1, 3, 32, 800, dtype=torch.float32)
    DEFAULT_STATIC_ONNX_MODEL.parent.mkdir(parents=True, exist_ok=True)

    torch.onnx.export(
        model,
        dummy_input,
        DEFAULT_STATIC_ONNX_MODEL,
        export_params=True,
        opset_version=17,
        do_constant_folding=True,
        input_names=["image_input"],
        output_names=["logits"],
        dynamo=False,
    )
    print(f"Successfully exported static ONNX to {DEFAULT_STATIC_ONNX_MODEL}")
    print(f"Size: {DEFAULT_STATIC_ONNX_MODEL.stat().st_size / (1024 * 1024):.2f} MB")


if __name__ == "__main__":
    main()
