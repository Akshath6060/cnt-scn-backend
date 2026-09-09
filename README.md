# Contact Scanner

The project is split into a Flutter mobile client and a Python OCR backend.

```text
frontend/  Flutter application
backend/   Model training, evaluation, and TFLite export pipeline
```

## Frontend

```bash
cd frontend
flutter pub get
flutter test
flutter run
```

See [`frontend/README.md`](frontend/README.md) for mobile setup and architecture.

## Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'
pytest
```

See [`backend/README.md`](backend/README.md) for dataset, training, evaluation,
and model export commands.
