# ContactScanner

> Offline handwritten contact scanner — photograph handwritten contact lists (names + phone numbers) and convert them into structured, saveable contacts using image processing and AI-powered vision parsing.

<p align="center">
  <strong>Cyan & White</strong> • <strong>Inter Typography</strong> • <strong>Material 3</strong> • <strong>Modular Architecture</strong>
</p>

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [App Flow](#app-flow)
- [Component Reference](#component-reference)
  - [Presentation Layer (Screens)](#presentation-layer-screens)
  - [Service Layer (Business Logic)](#service-layer-business-logic)
  - [Design System](#design-system)
- [Dependencies](#dependencies)
- [Environment Setup](#environment-setup)
- [tflite_flutter Integration Guide](#tflite_flutter-integration-guide)
- [Project Structure](#project-structure)

---

## Architecture Overview

The app follows a **strict presentation/logic separation**:

```
┌─────────────────────────────────────────────────────────┐
│                   PRESENTATION LAYER                     │
│   Screens (UI only — no business logic)                  │
│                                                          │
│   camera_screen.dart → review_screen.dart                │
│       → processed_image_screen.dart                      │
│           → contact_review_screen.dart                   │
│               → save_success_screen.dart                 │
│                                                          │
│   Shared: loading_spinner.dart, app_theme.dart           │
├─────────────────────────────────────────────────────────┤
│                    SERVICE LAYER                         │
│   Pure logic — no UI, no BuildContext                    │
│                                                          │
│   document_crop_service.dart    (Phase 1 — capture)      │
│   preprocessing_service.dart    (Phase 2 — image clean)  │
│   vision_parser_service.dart    (Phase 3+4 — ML/AI)      │
│   contacts_writer_service.dart  (Phase 5+6 — save)       │
└─────────────────────────────────────────────────────────┘
```

This separation means you can **swap any service** (e.g., replace `vision_parser_service.dart` with a `tflite_flutter` implementation) without touching a single screen file.

---

## App Flow

```
CameraScreen → ReviewScreen → ProcessedImageScreen → ContactReviewScreen → SaveSuccessScreen
  (Phase 1)     (Phase 1)       (Phase 2)              (Phase 3+4+5)        (Phase 6)
                                    ↓
                       RotatingLoader overlay:
                  "Running Offline ML Processing..."
                     (Gemini Vision API / tflite)
```

---

## Component Reference

### Presentation Layer (Screens)

#### `camera_screen.dart` — Phase 1: Image Capture

| Feature | Description |
|---------|-------------|
| **Camera preview** | Full-screen rear camera viewfinder via `camera` package |
| **Cyan bounding box** | Animated `CustomPainter` overlay with dashed cyan edges, glowing corner brackets, and dim-outside effect. Pulses subtly to simulate edge detection |
| **Shutter button** | Quick capture → navigates to `ReviewScreen` |
| **Scan Doc button** | Launches `cunning_document_scanner` for native edge detection + perspective correction |
| **Torch toggle** | Flash on/off control (top-right) |
| **Instruction banner** | Auto-dismissing cyan banner: "Place the paper flat..." |

**Key state variables:**
- `_isCapturing` — guards against double-tap on shutter
- `_isScanning` — guards against double-tap on scan button
- `_isTorchOn` — tracks flashlight state
- `_boxPulseAnimation` — drives corner bracket pulse animation

---

#### `review_screen.dart` — Phase 1: Image Review

| Feature | Description |
|---------|-------------|
| **Full-screen preview** | Captured image with pinch-to-zoom (`InteractiveViewer`) |
| **Quality warning** | Amber banner if image is under 200KB |
| **Retake button** | Pops back to camera |
| **Process Image button** | Runs `PreprocessingService.processImage()` → navigates to `ProcessedImageScreen` |
| **Loading overlay** | Shows `RotatingLoader` during preprocessing |

---

#### `processed_image_screen.dart` — Phase 2: Preprocessed Preview

| Feature | Description |
|---------|-------------|
| **Processed/Original toggle** | Switch between cleaned B&W image and raw capture |
| **Quality badge** | Green/orange/grey pill badge from brightness analysis |
| **Continue button** | Sends image to `VisionParserService.extractAndParseContacts()` |
| **ML loading overlay** | `RotatingLoader` with message "Running Offline ML Processing..." |
| **Retry on failure** | SnackBar with "Retry" action on API/ML errors |

---

#### `loading_spinner.dart` — Phase 3: ML Processing Overlay

| Feature | Description |
|---------|-------------|
| **Frosted glass backdrop** | Semi-transparent white overlay (92% opacity) |
| **3 concentric rings** | Outer: slow clockwise dashed ring (cyan light). Middle: counter-clockwise + scale pulse (cyan). Inner: fast clockwise (cyan dark). All drawn with `CustomPainter` |
| **Brain icon** | Centered `psychology_rounded` icon in a cyan circle |
| **Primary message** | Configurable via `message` parameter |
| **Sub-label** | Green dot + "On-device • No internet required" (configurable via `subLabel`) |

---

#### `contact_review_screen.dart` — Phases 4+5: Contact Verification

| Feature | Description |
|---------|-------------|
| **White contact cards** | Cyan left-border accent, subtle shadow, slide-in animation |
| **Editable fields** | Name + Phone Number with cyan-focused input borders |
| **Low-confidence badge** | Orange pill warning for AI-uncertain entries |
| **Mark as Temporary toggle** | Per-card `Switch` — when ON, reveals time-picker |
| **Expiry duration picker** | `CupertinoTimerPicker` in a bottom sheet — sets auto-delete timer |
| **Batch label** | Suffix panel to append a label (e.g., "College") to all names |
| **Skip label checkbox** | Per-card opt-out from batch label |
| **Swipe to delete** | `Dismissible` with red background |
| **Add Manually** | Inserts a blank card at the top |
| **Save to Phonebook** | Cyan primary button → `ContactsWriterService.saveAllContacts()` |
| **Confirmation snackbar** | "Contact saved. Cleanup task scheduled." before navigating |

**Key state variables:**
- `_nameControllers` / `_phoneControllers` — parallel `TextEditingController` lists
- `_isTemporary` — `List<bool>` tracking temporary toggle per card
- `_expiryDuration` — `List<Duration>` tracking expiry per card (default 24h)
- `_skipSuffix` — `List<bool>` for per-card label opt-out

---

#### `save_success_screen.dart` — Phase 6: Save Confirmation

| Feature | Description |
|---------|-------------|
| **Animated check icon** | Scale-in with `Curves.elasticOut` inside a cyan circle |
| **Summary card** | White card with colored count badges (saved/skipped/failed) |
| **Failures section** | Orange-bordered list of contacts that couldn't be saved |
| **Skipped section** | Cyan-bordered list of duplicates |
| **Scan Another Page** | Clears stack → back to camera |
| **Open Contacts** | Launches native contacts app (multi-vendor support) |
| **Share Summary** | Shares save count via `share_plus` |
| **Confetti** | Cyan/white color palette burst on mount |

---

### Service Layer (Business Logic)

#### `document_crop_service.dart` — Document Scanning

- Wraps `cunning_document_scanner` (Google ML Kit on Android, VisionKit on iOS)
- Returns a cropped, perspective-corrected `File` or `null` if cancelled
- **Swap target:** Replace with OpenCV for custom edge detection

#### `preprocessing_service.dart` — Image Preprocessing

4-step pipeline (pure Dart via `image` package):
1. **Grayscale** conversion
2. **Gaussian blur** (5×5 kernel, noise reduction)
3. **Adaptive thresholding** (local mean, handles uneven lighting)
4. **Dilation** (3×3 kernel, thickens handwritten strokes)

Also supports a lighter `forOCR` mode (grayscale + mild contrast only).

- **Swap target:** Replace with OpenCV for faster native processing

#### `vision_parser_service.dart` — AI Vision Parsing

- Sends base64-encoded image to **Gemini 2.5 Flash** via REST HTTP
- Returns `List<Map<String, String>>` with `name`, `phone`, and optional `confidence` keys
- Auto-retries once on malformed response
- 30-second timeout with descriptive error messages
- **Swap target:** Replace with `tflite_flutter` for fully offline ML (see guide below)

#### `contacts_writer_service.dart` — Native Contacts Writer

- Uses `MethodChannel` to invoke native Android contact insertion
- Handles Google account detection (avoids SIM/local account crashes)
- Checks for duplicates before insertion
- Returns `ContactSaveResult` with saved/failed/skipped counts + names
- **Swap target:** Wire up to `flutter_contacts` or `contacts_service` packages

---

### Design System

#### `app_theme.dart` — Centralized Theme

| Token | Value | Usage |
|-------|-------|-------|
| `cyan` | `#00BCD4` | Primary buttons, accents, focus borders |
| `cyanDark` | `#0097A7` | AppBar, snackbar backgrounds |
| `cyanLight` | `#B2EBF2` | Outlined button borders, card accents |
| `cyanAccent` | `#00E5FF` | Torch-on indicator, confetti |
| `cyanFaint` | `#E0F7FA` | Input field fills, badge backgrounds |
| `white` | `#FFFFFF` | Scaffolds, card surfaces |
| `textPrimary` | `#1A1A2E` | Headings, body text |
| `textSecondary` | `#6B7280` | Labels, hints |
| `error` | `#EF4444` | Delete actions, error states |
| `warning` | `#F59E0B` | Low-confidence badges, quality alerts |
| `success` | `#10B981` | Good quality badge, online status dot |

**Typography:** All text uses **Inter** via `google_fonts`.

**Reusable decorations:**
- `accentCardDecoration` — white card with cyan left border + shadow
- `cyanGradientDecoration` — gradient CTA button background
- `frostedGlassDecoration` — glassmorphism overlay panel

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `camera` | ^0.10.5 | Camera preview and photo capture |
| `cunning_document_scanner` | ^1.4.0 | Native document scanning with edge detection |
| `image` | ^4.5.3 | Image manipulation (preprocessing pipeline) |
| `http` | ^1.2.1 | HTTP client for Gemini Vision API calls |
| `flutter_dotenv` | ^5.1.0 | Load API keys from `.env` file |
| `path_provider` | ^2.1.3 | File system paths |
| `path` | ^1.9.0 | Path manipulation utilities |
| `google_fonts` | ^6.1.0 | Inter font family |
| `permission_handler` | ^12.0.3 | Camera and contacts permissions |
| `confetti` | ^0.7.0 | Celebration animation on save success |
| `share_plus` | ^10.0.0 | Share save summary |
| `url_launcher` | ^6.3.0 | Open native contacts app |

---

## Environment Setup

```
Flutter 3.44.2 (stable)
Dart 3.12.2
Android SDK 36.1.0
Target device: Android (tested on Motorola Edge 50 Pro)
```

### Required Configuration

1. **Gemini API Key** (for current cloud-based parsing):
   ```
   # .env file in project root
   GEMINI_API_KEY=your_key_here
   ```
   Get one free at: https://aistudio.google.com/app/apikey

2. **Android permissions** (already configured in `AndroidManifest.xml`):
   - `CAMERA`
   - `INTERNET`
   - `READ_CONTACTS`
   - `WRITE_CONTACTS`

---

## tflite_flutter Integration Guide

> **Status: NOT yet configured.** The app currently uses Gemini Vision API (cloud). Below are the complete steps to migrate to fully offline on-device ML with `tflite_flutter`.

### Step 1 — Add the dependency

```yaml
# pubspec.yaml
dependencies:
  tflite_flutter: ^0.12.1
```

```bash
flutter pub get
```

### Step 2 — Create the model assets directory

```
contact_scanner/
├── assets/
│   └── models/
│       ├── text_detection.tflite      # EAST or similar text detector
│       ├── text_recognition.tflite    # CNN+LSTM handwriting recognizer
│       └── labels.txt                 # Character set labels
```

Register in `pubspec.yaml`:
```yaml
flutter:
  assets:
    - .env
    - assets/models/text_detection.tflite
    - assets/models/text_recognition.tflite
    - assets/models/labels.txt
```

### Step 3 — Prevent model compression (Android)

Add to `android/app/build.gradle.kts`:
```kotlin
android {
    // ... existing config ...

    androidResources {
        noCompress += "tflite"
    }
}
```

### Step 4 — Create the TFLite service

Create `lib/tflite_parser_service.dart` — this replaces `vision_parser_service.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// On-device handwriting recognition using TensorFlow Lite.
///
/// Replaces [VisionParserService] for fully offline ML processing.
/// Pipeline: Text Detection → Crop Regions → Text Recognition → Regex Parse
class TfliteParserService {
  static Interpreter? _detector;
  static Interpreter? _recognizer;

  /// Initialize both models. Call once at app startup.
  static Future<void> initialize() async {
    // Use GPU delegate for performance (falls back to CPU automatically)
    final options = InterpreterOptions()..threads = 4;

    // Optional: Add NNAPI delegate for Android hardware acceleration
    // options.addDelegate(NnApiDelegate());

    _detector = await Interpreter.fromAsset(
      'assets/models/text_detection.tflite',
      options: options,
    );

    _recognizer = await Interpreter.fromAsset(
      'assets/models/text_recognition.tflite',
      options: options,
    );
  }

  /// Release model resources.
  static void dispose() {
    _detector?.close();
    _recognizer?.close();
  }

  /// Extract contacts from a preprocessed image.
  ///
  /// Returns the same format as VisionParserService:
  /// List<Map<String, String>> with "name" and "phone" keys.
  static Future<List<Map<String, String>>> extractAndParseContacts(
    String imagePath,
  ) async {
    if (_detector == null || _recognizer == null) {
      await initialize();
    }

    // 1. Load and preprocess image for the detection model
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    // 2. Run text detection to get bounding boxes
    //    (Implementation depends on your specific model's input/output spec)
    final boxes = _runDetection(image);

    // 3. For each box, crop and run text recognition
    final List<String> recognizedLines = [];
    for (final box in boxes) {
      final cropped = img.copyCrop(image,
          x: box.left.toInt(),
          y: box.top.toInt(),
          width: box.width.toInt(),
          height: box.height.toInt());
      final text = _runRecognition(cropped);
      if (text.isNotEmpty) recognizedLines.add(text);
    }

    // 4. Parse recognized text into name + phone pairs using regex
    return _parseContactLines(recognizedLines);
  }

  /// Run text detection model on the full image.
  static List<Rect> _runDetection(img.Image image) {
    // TODO: Implement based on your detection model's spec
    // Typical flow:
    // 1. Resize image to model input size (e.g., 320x320)
    // 2. Normalize pixel values to [0, 1] or [-1, 1]
    // 3. Run interpreter.run(input, output)
    // 4. Post-process output into bounding box Rects
    // 5. Apply Non-Maximum Suppression (NMS)
    throw UnimplementedError('Wire up your text detection model here');
  }

  /// Run text recognition model on a cropped text region.
  static String _runRecognition(img.Image croppedRegion) {
    // TODO: Implement based on your recognition model's spec
    // Typical flow:
    // 1. Resize to model input (e.g., 31x200 for CRNN)
    // 2. Normalize pixel values
    // 3. Run interpreter.run(input, output)
    // 4. Decode output using CTC or attention-based decoding
    // 5. Map indices to characters using labels.txt
    throw UnimplementedError('Wire up your text recognition model here');
  }

  /// Parse raw text lines into structured contact maps.
  static List<Map<String, String>> _parseContactLines(List<String> lines) {
    final contacts = <Map<String, String>>[];

    // Phone number regex: matches 7-15 digit sequences with optional
    // country code, dashes, spaces, and parentheses
    final phoneRegex = RegExp(
      r'[\+]?[(]?[0-9]{1,4}[)]?[-\s\./0-9]{6,14}[0-9]',
    );

    for (final line in lines) {
      final phoneMatch = phoneRegex.firstMatch(line);
      if (phoneMatch != null) {
        final phone = phoneMatch.group(0)!.replaceAll(RegExp(r'[^\d+]'), '');
        final name = line.substring(0, phoneMatch.start).trim()
            .replaceAll(RegExp(r'[-=:]+$'), '')  // Remove trailing separators
            .trim();

        if (name.isNotEmpty || phone.isNotEmpty) {
          contacts.add({'name': name, 'phone': phone});
        }
      }
    }

    return contacts;
  }
}
```

### Step 5 — Wire it into the app

In `processed_image_screen.dart`, swap the service call:

```dart
// BEFORE (cloud):
import 'vision_parser_service.dart';
final contacts = await VisionParserService.extractAndParseContacts(path);

// AFTER (offline):
import 'tflite_parser_service.dart';
final contacts = await TfliteParserService.extractAndParseContacts(path);
```

In `main.dart`, initialize models at startup:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ... existing setup ...

  // Pre-load TFLite models
  await TfliteParserService.initialize();

  runApp(const ContactScannerApp());
}
```

### Step 6 — Choose your models

You need **two** `.tflite` models:

| Model | Purpose | Recommended Source |
|-------|---------|-------------------|
| **Text Detection** | Locates text regions in the image | [EAST model](https://www.tensorflow.org/lite/examples/optical_character_recognition/overview) or [CRAFT](https://github.com/clovaai/CRAFT-pytorch) (convert to TFLite) |
| **Text Recognition** | Converts cropped text to characters | [SimpleHTR](https://github.com/githubharald/SimpleHTR) trained on IAM handwriting dataset, or TensorFlow Hub's text recognition models |

**Alternative (simpler):** Use Google ML Kit's on-device text recognition instead of raw TFLite:
```yaml
dependencies:
  google_mlkit_text_recognition: ^0.14.0
```
This provides a pre-trained, optimized model without manual model management, though it may struggle with very messy handwriting.

### Step 7 — Performance optimization

```dart
// Use NNAPI delegate for Android hardware acceleration
final options = InterpreterOptions()
  ..threads = 4
  ..addDelegate(NnApiDelegate());

// For heavy models, run inference in an Isolate to prevent UI jank
final contacts = await compute(_runInferenceIsolate, imagePath);
```

### Step 8 — Remove cloud dependency

Once tflite is working, you can:
1. Remove `http` from `pubspec.yaml`
2. Remove `flutter_dotenv` and the `.env` file
3. Remove `INTERNET` permission from `AndroidManifest.xml`
4. Delete `vision_parser_service.dart`

---

## Project Structure

```
contact_scanner/
├── android/                         # Android native code + manifest
│   └── app/src/main/
│       ├── AndroidManifest.xml      # Permissions (camera, contacts, internet)
│       └── kotlin/                  # Native contacts writer (MethodChannel)
├── assets/                          # (Future) TFLite models directory
│   └── models/
├── lib/
│   ├── main.dart                    # App entry point + root MaterialApp
│   ├── app_theme.dart               # Cyan/White design system + Inter font
│   ├── camera_screen.dart           # Phase 1: Camera + bounding box overlay
│   ├── review_screen.dart           # Phase 1: Image review + quality check
│   ├── processed_image_screen.dart  # Phase 2: Preprocessed preview + toggle
│   ├── loading_spinner.dart         # Phase 3: Pulsing cyan rings overlay
│   ├── contact_review_screen.dart   # Phase 4+5: Editable cards + temp toggle
│   ├── save_success_screen.dart     # Phase 6: Success + summary + confetti
│   ├── document_crop_service.dart   # Service: Native doc scanner wrapper
│   ├── preprocessing_service.dart   # Service: 4-step image pipeline
│   ├── vision_parser_service.dart   # Service: Gemini Vision API (swap target)
│   └── contacts_writer_service.dart # Service: Native contacts writer
├── .env                             # API keys (not committed to git)
├── pubspec.yaml                     # Dependencies
└── README.md                        # This file
```

---

## License

Private project — not published to pub.dev.
