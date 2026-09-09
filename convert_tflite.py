# convert_tflite.py
import sys
sys.stdout.reconfigure(line_buffering=True)
import os
import onnx
from onnx_tf.backend import prepare
import tensorflow as tf

print("Step 1: Loading static ONNX model...")
onnx_model = onnx.load("crnn_static.onnx")

print("Step 2: Converting ONNX -> TF SavedModel via onnx-tf...")
tf_rep = prepare(onnx_model)

print("Step 3: Exporting SavedModel...")
tf_rep.export_graph("saved_model_dir")

print("Step 4: Converting SavedModel -> TFLite (Float16 quantized)...")
converter = tf.lite.TFLiteConverter.from_saved_model("saved_model_dir")
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]

tflite_model = converter.convert()

with open("crnn_handwritten.tflite", "wb") as f:
    f.write(tflite_model)

print(f"Done! Final model: crnn_handwritten.tflite ({os.path.getsize('crnn_handwritten.tflite') / (1024*1024):.2f} MB)")
