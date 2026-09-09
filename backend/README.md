# Contact Scanner Backend

Offline handwritten-text recognition pipeline for extracting names and phone
numbers from contact sheets. The project trains a ResNet18-CRNN model, exports
it through ONNX to TFLite, and supplies the character map consumed by the
mobile client.

## Layout

```text
src/contact_scanner_backend/  Reusable model and dataset package
scripts/data/                 Dataset download and preparation commands
scripts/training/             Training and fine-tuning commands
scripts/evaluation/           PyTorch and TFLite evaluation utilities
scripts/export/               ONNX, TFLite, and charset export commands
scripts/dev/                  Experimental development utilities
tests/                        Automated and smoke tests
assets/                       Small versioned runtime assets
docs/                         Architecture and project history
requirements/                 Environment-specific dependency lists
data/                         Generated datasets (gitignored)
```

## Setup

Use Python 3.11 or newer for training and ONNX export:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[dev]'
```

The legacy TensorFlow conversion toolchain requires a separate Python 3.11
environment:

```bash
python -m pip install -r requirements/conversion.txt
```

## Common commands

Run commands from the `backend/` directory after installing the package:

```bash
python scripts/data/download_iam.py
python scripts/training/train.py
python scripts/evaluation/evaluate_validation.py
python scripts/export/export_onnx_static.py
python scripts/export/convert_tflite.py
python scripts/evaluation/tflite_inference.py --image path/to/crop.jpg
pytest
```

See [docs/PROJECT_PHASES.md](docs/PROJECT_PHASES.md) for the model architecture,
training history, and conversion notes.
