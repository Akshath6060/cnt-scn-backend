# Contact Scanner — Project Phases & Architecture

## Overview

Contact Scanner is a Flutter mobile app that photographs handwritten contact lists
(names + phone numbers) and converts them into structured, saveable contacts using
a pipeline of image processing and AI-powered vision parsing.

---

## App Flow (Screen-by-Screen)

```
CameraScreen → ReviewScreen → ProcessedImageScreen → ContactReviewScreen
  (Phase 1)      (Phase 1)       (Phase 2)              (Phase 3+4)
                                    ↓
                         RotatingLoader overlay:
                      "Reading handwriting with AI..."
                         (Gemini Vision API call)
```

---

## Phase 1 — Image Capture (`camera_screen.dart`, `review_screen.dart`)

**What it does:**
- Opens a full-screen camera preview using the device's rear camera.
- Two capture modes:
  1. **Shutter button** — quick snapshot, no edge detection.
  2. **"Scan Doc" button** — launches the native document scanner
     (`cunning_document_scanner`) with automatic edge detection,
     corner adjustment, and perspective correction.
- After capture, `ReviewScreen` shows the image for review with
  pinch-to-zoom. User can retake or proceed to processing.

**Key files:**
- `camera_screen.dart` — Camera preview + capture UI
- `review_screen.dart` — Image review + "Process Image" button
- `document_crop_service.dart` — Wraps `cunning_document_scanner`

---

## Phase 2 — Image Preprocessing (`preprocessing_service.dart`, `processed_image_screen.dart`)

**What it does:**
- Runs a 4-step image preprocessing pipeline to clean the handwritten
  image for better AI recognition:
  1. Grayscale conversion
  2. Contrast enhancement
  3. Adaptive thresholding (converts to black-and-white)
  4. Noise reduction
- `ProcessedImageScreen` shows the cleaned image and lets the user
  continue to AI extraction or retake.
- Tapping "Continue" triggers the Gemini Vision API call (Phase 3+4).

**Key files:**
- `preprocessing_service.dart` — The 4-step image cleaning pipeline
- `processed_image_screen.dart` — Preview + "Continue" button → Gemini Vision

---

## Phase 3+4 — AI Vision Parsing (`vision_parser_service.dart`, `contact_review_screen.dart`)

**What it does:**
- **Replaced the old two-step pipeline** (ML Kit OCR → Anthropic AI parsing)
  with a **single Gemini Vision API call** that handles both text recognition
  and structured contact extraction simultaneously.
- Uses **Google Gemini 2.0 Flash** via REST HTTP (no SDK dependency).
- The image is base64-encoded and sent with a detailed prompt instructing
  Gemini to extract name + phone pairs from handwritten text.
- Gemini returns a strict JSON array of contacts.
- `ContactReviewScreen` displays the parsed contacts in editable cards:
  - Each card has editable Name and Phone text fields
  - Low-confidence entries show an orange warning badge
  - Users can delete incorrect entries or add blank cards manually

**Key files:**
- `vision_parser_service.dart` — Gemini Vision API integration (OCR + parsing in one call)
- `contact_review_screen.dart` — Editable contact cards UI
- `loading_spinner.dart` — Animated rotating loader overlay

**Why Gemini Vision instead of ML Kit + Anthropic?**
- ML Kit's on-device OCR struggled with handwritten text
- Gemini Vision handles both recognition and structuring in one API call
- Free tier: 1500 requests/day, no credit card required
- Temperature set to 0.1 for deterministic, JSON-only output

**Requirements:**
- A valid Gemini API key in `.env` file: `GEMINI_API_KEY=your_key_here`
  Get one free at: https://aistudio.google.com/app/apikey
- Internet permission in AndroidManifest.xml

---

## Phase 5 — Native Contacts Integration (NOT YET IMPLEMENTED)

**What it will do:**
- The "Save All to Contacts" button on ContactReviewScreen will save
  the reviewed contacts directly to the device's native contacts app.
- Currently shows a placeholder snackbar: "Phase 5 — Saving to phonebook coming next!"

---

## Deleted Files (No Longer Needed)

These files were part of the old Phase 3/4 pipeline and have been removed:
- `ocr_service.dart` — ML Kit on-device OCR (replaced by Gemini Vision)
- `ocr_result_screen.dart` — Raw OCR text display screen (no longer needed)
- `ai_parser_service.dart` — Anthropic Claude API integration (replaced by Gemini Vision)

---

## Environment Setup

```
Flutter 3.44.2 (stable)
Dart 3.12.2
Android SDK 36.1.0
Target device: Android (tested on Motorola Edge 50 Pro)
```

## Dependencies

| Package                     | Purpose                                     |
|-----------------------------|---------------------------------------------|
| `camera`                    | Camera preview and photo capture            |
| `cunning_document_scanner`  | Native document scanning with edge detection|
| `image`                     | Image manipulation (preprocessing)          |
| `http`                      | HTTP client for Gemini Vision API calls     |
| `flutter_dotenv`            | Load API keys from .env file                |
| `path_provider`             | File system paths                           |
| `path`                      | Path manipulation utilities                 |
