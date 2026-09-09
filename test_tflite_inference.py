"""
Quick standalone test: run the fine-tuned crnn_handwritten.tflite against
one or more real handwritten phone-number crops, without touching the
Flutter app.

Usage:
    python test_tflite_inference.py --image path/to/phone_number_crop.jpg
    python test_tflite_inference.py --image_dir path/to/folder_of_crops
"""
import argparse
import os
import numpy as np
import cv2
import tensorflow as tf

CHARS = "-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !\"'(),.:;?+@/-#*&"
IDX_TO_CHAR = {idx: char for idx, char in enumerate(CHARS)}
TARGET_H = 32
TARGET_W = 800


def preprocess(img_path):
    img = cv2.imread(img_path)
    if img is None:
        raise FileNotFoundError(f"Could not read image: {img_path}")

    h, w, _ = img.shape
    scale = TARGET_H / max(h, 1)
    new_w = min(int(w * scale), TARGET_W)
    resized = cv2.resize(img, (new_w, TARGET_H))

    canvas = np.full((TARGET_H, TARGET_W, 3), 255, dtype=np.uint8)
    canvas[:, :new_w] = resized

    tensor_img = canvas.astype(np.float32).transpose(2, 0, 1) / 127.5 - 1.0
    return np.expand_dims(tensor_img, axis=0)  # (1, 3, 32, 800)


def ctc_greedy_decode(logits):
    # logits: (1, T, C)
    pred_indices = np.argmax(logits[0], axis=-1)  # (T,)
    decoded = []
    prev = -1
    for idx in pred_indices:
        if idx != prev and idx != 0:  # skip repeats and blank (index 0)
            decoded.append(IDX_TO_CHAR.get(int(idx), ""))
        prev = idx
    return "".join(decoded)


def run_inference(interpreter, img_path):
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    # Model input is fixed at (1, 3, 32, 800) already, matching preprocess().
    # Do NOT call resize_tensor_input here - onnx_tf's while-loop-based LSTM
    # implementation breaks shape inference if the graph is re-triggered,
    # even when resizing to the exact same shape.
    interpreter.allocate_tensors()

    input_data = preprocess(img_path)
    expected_shape = tuple(input_details[0]["shape"])
    if input_data.shape != expected_shape:
        raise ValueError(
            f"Preprocessed image shape {input_data.shape} does not match "
            f"the model's fixed input shape {expected_shape}. "
            f"Check TARGET_H/TARGET_W constants match the model's export dimensions."
        )

    interpreter.set_tensor(input_details[0]["index"], input_data)
    interpreter.invoke()
    logits = interpreter.get_tensor(output_details[0]["index"])

    text = ctc_greedy_decode(logits)
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="crnn_handwritten.tflite")
    parser.add_argument("--image", help="Single image path")
    parser.add_argument("--image_dir", help="Folder of images to test in batch")
    args = parser.parse_args()

    interpreter = tf.lite.Interpreter(
        model_path=args.model,
        experimental_op_resolver_type=tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES,
    )

    if args.image:
        text = run_inference(interpreter, args.image)
        digits_only = "".join(c for c in text if c.isdigit())
        print(f"{os.path.basename(args.image)}: raw='{text}'  digits_only='{digits_only}' (len={len(digits_only)})")

    elif args.image_dir:
        for fname in sorted(os.listdir(args.image_dir)):
            if not fname.lower().endswith((".png", ".jpg", ".jpeg")):
                continue
            img_path = os.path.join(args.image_dir, fname)
            text = run_inference(interpreter, img_path)
            digits_only = "".join(c for c in text if c.isdigit())
            print(f"{fname}: raw='{text}'  digits_only='{digits_only}' (len={len(digits_only)})")
    else:
        print("Provide --image or --image_dir")


if __name__ == "__main__":
    main()
