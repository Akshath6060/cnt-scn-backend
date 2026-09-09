# export_onnx.py
import sys
import os
os.environ["PYTHONIOENCODING"] = "utf-8"
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")
import torch
from contact_scanner_backend.model import ResNet18_CRNN
from contact_scanner_backend.paths import DEFAULT_CHECKPOINT, DEFAULT_ONNX_MODEL

def main():
    import onnx

    device = torch.device("cpu")
    model = ResNet18_CRNN(pretrained=False)
    model.load_state_dict(torch.load(DEFAULT_CHECKPOINT, map_location=device))
    model.eval()

    dummy_input = torch.randn(1, 3, 32, 800, dtype=torch.float32)
    DEFAULT_ONNX_MODEL.parent.mkdir(parents=True, exist_ok=True)

    # Use legacy TorchScript exporter to avoid LSTM dynamic shape issues.
    torch.onnx.export(
        model,
        dummy_input,
        DEFAULT_ONNX_MODEL,
        export_params=True,
        opset_version=17,
        do_constant_folding=True,
        input_names=["image_input"],
        output_names=["logits"],
        dynamic_axes={
            "image_input": {0: "batch_size", 3: "width"},
            "logits": {0: "batch_size", 1: "time_steps"},
        },
        dynamo=False,
    )
    print(f"Successfully exported to {DEFAULT_ONNX_MODEL}")

    onnx_model = onnx.load(DEFAULT_ONNX_MODEL)
    onnx.checker.check_model(onnx_model)
    size_mb = DEFAULT_ONNX_MODEL.stat().st_size / (1024 * 1024)
    print(f"ONNX model verified. Size: {size_mb:.2f} MB")


if __name__ == "__main__":
    main()
