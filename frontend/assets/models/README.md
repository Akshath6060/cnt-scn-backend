# Bundled model assets

Everything the recogniser needs ships inside the APK/IPA. Nothing here is ever
downloaded at runtime (§2, §7).

| File | Required | Purpose |
|------|----------|---------|
| `chars.txt` | yes (bundled) | Character vocabulary. Index 0 is the CTC blank. Must match the training charset exactly. |
| `handwriting_recognizer.tflite` | **not yet present** | ResNet18-CRNN recogniser. Input `[1,3,32,800]` float32 NCHW. |
| `text_detector.tflite` | optional | Text-region detector. Absent, the app uses the built-in morphological detector. |
| `contact_recognition.tflite` | optional | Combined detect+recognise model, if the architecture is merged later. |

## Current state

No `.tflite` file is bundled yet — the training pipeline in `../../backend`
has not produced one (`backend/artifacts/` is empty).

The app handles this without crashing:

* `TfliteModelManager.isModelBundled()` reports the asset as missing,
* `TFLiteHandwritingRecognizer.isReady` stays `false`,
* in a **debug** build with *Settings → Allow mock recogniser* enabled, the
  mock stands in and every result is labelled as synthetic,
* in a **release** build the user sees a clear local error instead.

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
