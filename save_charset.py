# save_charset.py
from model import CHARS

with open("chars.txt", "w", encoding="utf-8") as f:
    f.write(CHARS)

print("Saved chars.txt (Copy this together with crnn_handwritten.tflite into Flutter assets)")
