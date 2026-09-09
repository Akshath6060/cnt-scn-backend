# Bundled model assets

Everything the recogniser needs ships inside the APK/IPA. Nothing here is ever
downloaded at runtime (§2, §7).

| File | Required | Purpose |
|------|----------|---------|
| `chars.txt` | yes (bundled) | Character vocabulary. Index 0 is the CTC blank. Must match the training charset exactly. |
| `handwriting_recognizer.tflite` | fallback source | Float16 conversion of the recogniser. Input `[1,3,32,800]` float32 NCHW. |
| `handwriting_recognizer.onnx` | yes (bundled) | Production ResNet18-CRNN graph used when LiteRT rejects the converted LSTM graph. |
| `text_detector.tflite` | optional | Text-region detector. Absent, the app uses the built-in morphological detector. |
| `contact_recognition.tflite` | optional | Combined detect+recognise model, if the architecture is merged later. |

## Current state

Both supplied model formats are bundled. Their SHA-256 digests are:

* ONNX: `bad6c351234b3567c493d20a6e950f9ee6ddee729cbc84a407b404fa2137d2f1`
* TFLite: `33866238ef86d797827c65e1c76c5bfffd4dff03b105d825f04a8d32a94ddac7`

The app handles this without crashing:

The app loads the original ONNX graph through ONNX Runtime. The supplied TFLite
graph is rejected by LiteRT at its LSTM `WHILE` / `BATCH_MATMUL` preparation
step, so it is retained only as a fallback for a future corrected export. ONNX
Runtime is still real, fully-offline recognition; the labelled mock remains a
debug-only last resort.

## Adding the trained model

```bash
cd ../../backend
python scripts/export/export_onnx_static.py
python scripts/export/convert_tflite.py
python scripts/export/save_charset.py

cp artifacts/tflite/crnn_handwritten.tflite \
   ../frontend/assets/models/handwriting_recognizer.tflite
cp assets/chars.txt ../frontend/assets/models/chars.txt
```

No Dart changes are required — the asset path is already declared in
`pubspec.yaml`. See `docs/ML_MODEL_INTEGRATION.md` for the full tensor contract.
