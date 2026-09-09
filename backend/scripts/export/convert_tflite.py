# convert_tflite.py
import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(line_buffering=True)
import onnx
from onnx_tf.backend import prepare
import tensorflow as tf
from contact_scanner_backend.paths import (
    DEFAULT_SAVED_MODEL,
    DEFAULT_STATIC_ONNX_MODEL,
    DEFAULT_TFLITE_MODEL,
)

def main():
    print("Step 1: Loading static ONNX model...")
    onnx_model = onnx.load(DEFAULT_STATIC_ONNX_MODEL)

    print("Step 2: Converting ONNX -> TF SavedModel via onnx-tf...")
    tf_rep = prepare(onnx_model)

    print("Step 3: Exporting SavedModel...")
    DEFAULT_SAVED_MODEL.parent.mkdir(parents=True, exist_ok=True)
    tf_rep.export_graph(str(DEFAULT_SAVED_MODEL))

    print("Step 4: Converting SavedModel -> TFLite (Float16 quantized)...")
    converter = tf.lite.TFLiteConverter.from_saved_model(str(DEFAULT_SAVED_MODEL))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]

    tflite_model = converter.convert()
    DEFAULT_TFLITE_MODEL.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_TFLITE_MODEL.write_bytes(tflite_model)

    size_mb = DEFAULT_TFLITE_MODEL.stat().st_size / (1024 * 1024)
    print(f"Done! Final model: {DEFAULT_TFLITE_MODEL} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
