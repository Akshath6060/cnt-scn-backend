"""Canonical project paths shared by command-line workflows."""

from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data"
ASSETS_DIR = PROJECT_ROOT / "assets"
ARTIFACTS_DIR = PROJECT_ROOT / "artifacts"
CHECKPOINT_DIR = ARTIFACTS_DIR / "checkpoints"
ONNX_DIR = ARTIFACTS_DIR / "onnx"
TFLITE_DIR = ARTIFACTS_DIR / "tflite"

DEFAULT_CHECKPOINT = CHECKPOINT_DIR / "best_crnn.pth"
DEFAULT_ONNX_MODEL = ONNX_DIR / "crnn_handwritten.onnx"
DEFAULT_STATIC_ONNX_MODEL = ONNX_DIR / "crnn_static.onnx"
DEFAULT_TFLITE_MODEL = TFLITE_DIR / "crnn_handwritten.tflite"
DEFAULT_CHARSET = ASSETS_DIR / "chars.txt"
DEFAULT_SAVED_MODEL = ARTIFACTS_DIR / "saved_model"
