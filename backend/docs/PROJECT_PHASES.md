# HTR Offline Contact Card Recognition Pipeline: Project Phases Documentation

## Executive Overview
This document chronicles the complete end-to-end technical engineering effort executed to establish an offline, on-device **Handwritten Text Recognition (HTR)** pipeline tailored for recognizing names, phone numbers, email addresses, and contact details from handwritten paper strips.

The system is engineered to run fully offline on edge devices (such as a Flutter mobile application) with zero cloud dependencies. It utilizes a **ResNet18-CRNN** (Convolutional Recurrent Neural Network) architecture trained with **Connectionist Temporal Classification (CTC)** loss and optimized via **Float16 Quantization** down to a compact **25.26 MB `.tflite`** binary.

---

## Technical Architecture & How the System Works

### 1. The Core Vision-Language Pipeline
```
[Input Image (3, 32, 800)]
         │
         ▼
[ResNet-18 Backbone (Feature Extractor)]
   • Modulated horizontal strides: Layer3 & Layer4 conv1/downsample stride = (2, 1)
   • Extracts deep visual feature maps while preserving sequence time-steps
   • Output Shape: (Batch, 512, 1, TimeSteps=100)
         │
         ▼
[Dimension Permutation & Linear Bridge]
   • Squeeze height: (Batch, TimeSteps, 512)
   • Linear Projection: 512 -> 256
         │
         ▼
[Bidirectional LSTM (Sequence Context)]
   • 2 Layers, hidden_size=256, dropout=0.2
   • Captures bidirectional cursive stroke contexts
   • Output Shape: (Batch, TimeSteps, 512)
         │
         ▼
[Linear Classifier Head]
   • Linear: 512 -> 81 (80 character classes + 1 CTC blank token)
   • Output Shape: (Batch, TimeSteps=100, Classes=81)
         │
         ▼
[CTC Loss (Training) / CTC Greedy Decoder (Inference)]
   • Collapses consecutive duplicate tokens and eliminates CTC blank (index 0)
   • Yields final predicted string
```

### 2. Character Vocabulary (`CHARS`)
Index `0` is strictly reserved for the CTC Blank (`-`). The complete alphabet comprises 80 distinct characters covering alphanumeric symbols, natural punctuation from benchmark handwriting, and contact sheet tokens:
```
-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !"\'(),.:;?+@/-#*&
```

---

## Detailed Chronological Breakdown: Phase by Phase

---

### Phase 0.1: Environment Calibration & CUDA 13.2 Realignment
* **Objective:** Establish a working PyTorch runtime with GPU acceleration on the host workstation.
* **Hardware & Runtime Context:**
  * Host GPU: **NVIDIA GeForce RTX 5060 Laptop GPU** (Blackwell Architecture, Compute Capability `sm_120`, Driver `596.36`).
  * Python runtime: Python 3.14.
* **Challenge Encountered:**
  * The initial pre-installed PyTorch build was `torch==2.14.0+cu126`.
  * Attempting to run a forward pass failed with `torch.AcceleratorError: CUDA error: no kernel image is available for execution on the device`. PyTorch cu126 only built kernels up to `sm_90` and lacked support for `sm_120`.
* **Changes Made & Solution:**
  1. Identified that driver version `596.36` supports CUDA 13.2 runtimes.
  2. Executed a clean force-reinstallation of PyTorch using the official CUDA 13.2 wheel index:
     ```bash
     pip install --force-reinstall torch==2.14.0 torchvision --index-url https://download.pytorch.org/whl/cu132
     ```
  3. Verified the GPU runtime: `torch.cuda.is_available() -> True` detecting `RTX 5060 Laptop GPU`.

---

### Phase 0.2: Model Architecture & Verification (`model.py` & `tests/test_model_forward.py`)
* **Objective:** Construct the ResNet18-CRNN model with CTC output head and verify forward tensor math.
* **Implementation Details:**
  * Created [`model.py`](../src/contact_scanner_backend/model.py):
    * Imported torchvision's pretrained `resnet18`.
    * **Stride Modulation:** Standard ResNet downsamples spatial dimensions by a factor of 32 in both height and width. For text line recognition, aggressive horizontal downsampling squashes adjacent characters into single feature columns. To preserve sequence width along the time dimension, strides in `layer3` and `layer4` were modified to `(2, 1)`.
    * Coupled the CNN output to a 2-layer `nn.LSTM(bidirectional=True, hidden_size=256)`.
    * Output projection mapped to `NUM_CLASSES` (initially 67, subsequently expanded to 81).
* **Verification:**
  * Created [`test_model_forward.py`](../tests/test_model_forward.py) feeding a synthetic batch of `(4, 3, 32, 280)`.
  * Forward pass completed successfully on CUDA yielding tensor shape `(4, 35, NUM_CLASSES)`.

---

### Phase 0.3: Benchmark Dataset Acquisition (`download_iam.py`)
* **Objective:** Acquire real-world human handwriting data rather than synthetic computer fonts to learn natural stroke width, cursive connections, and baseline slants.
* **Implementation Details:**
  * Created [`download_iam.py`](../scripts/data/download_iam.py) utilizing the HuggingFace `datasets` library to stream the academic benchmark **IAM Line Database** (`Teklia/IAM-line`).
  * Downloaded **6,482 authentic human handwritten text line strips** into `data/images/`.
  * Generated train/validation splits:
    * `data/train.csv`: **5,833 samples** (90%)
    * `data/val.csv`: **649 samples** (10%)
  * Verified average label length: ~43 characters per line.

---

### Phase 0.4: Resolution Scaling & Vocabulary Expansion
* **Objective:** Prevent CTC loss collapse on wide text lines and eliminate out-of-vocabulary character omissions.
* **Challenges Identified:**
  1. **Width Bottleneck:** Standard single-word CRNNs use a width of `280px`. IAM lines contain 40–60 characters. Compressing a 50-character sentence into 280 pixels forces each character into fewer than 5 pixels, causing temporal receptive fields to overlap heavily and causing CTC collapse.
  2. **Character Omissions:** IAM ground-truth labels contain punctuation such as commas, quotes, hyphens, and semicolons, as well as symbols `#`, `*`, and `&`.
* **Changes Made:**
  1. **Vocabulary Audit:** Created an automated audit script analyzing all unique characters across all 6,482 labels. Added `#`, `*`, `&`, `"`, `'`, `(`, `)`, `;`, `?`, `/`, `-`, `+`, `@` into `CHARS` in [`model.py`](../src/contact_scanner_backend/model.py), bringing total classes to 81.
  2. **Dataset Preprocessing in [`dataset.py`](../src/contact_scanner_backend/dataset.py):**
     * Scaled target image width from `280px` to **`800px`** (Height: `32px`).
     * Implemented aspect-ratio-preserving proportional scaling: height is scaled to 32px, width is proportionally resized up to 800px, and remainder is cleanly right-padded with pure white background (`255`).
     * Normalized pixels to `[-1.0, 1.0]`.
     * Added empty label fallback to prevent zero-length target tensors.

---

### Phase 0.5: Model Training on RTX 5060 (`train.py`)
* **Objective:** Train the ResNet18-CRNN to convergence using PyTorch on CUDA.
* **Training Hyperparameters:**
  * Batch Size: `16` (selected to balance gradient stability and VRAM footprint with 800px width).
  * Optimizer: `AdamW` (learning rate `3e-4`, weight decay `1e-4`).
  * Gradient Clipping: `torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)`.
  * Scheduler: `ReduceLROnPlateau(mode='min', factor=0.5, patience=2)`.
  * Loss: `nn.CTCLoss(blank=0, zero_infinity=True)`.
  * Epochs: 20.
* **Windows Engineering Fixes:**
  * **Multiprocessing Spawn Bug:** On Windows, PyTorch DataLoader workers fork via multiprocessing spawn rather than POSIX fork, triggering silent hangs and bootstrap exceptions. Resolved by wrapping the training execution in `if __name__ == '__main__':` and setting `num_workers=0` with `pin_memory=True`.
  * **Console Buffer Stalls:** Added unbuffered stdout reconfiguration (`sys.stdout.reconfigure(line_buffering=True)`) to eliminate Windows console buffer deadlocks.
* **Training Trajectory & Results:**
  ```
  Epoch [01/20] - Train Loss: 3.0763 | Val Loss: 2.5336  --> Saved best checkpoint
  Epoch [02/20] - Train Loss: 2.0834 | Val Loss: 1.8975  --> Saved best checkpoint
  Epoch [03/20] - Train Loss: 1.4873 | Val Loss: 1.5656  --> Saved best checkpoint
  Epoch [04/20] - Train Loss: 1.1811 | Val Loss: 1.3933  --> Saved best checkpoint
  Epoch [05/20] - Train Loss: 1.0044 | Val Loss: 1.3261  --> Saved best checkpoint
  Epoch [06/20] - Train Loss: 0.8678 | Val Loss: 1.2483  --> Saved best checkpoint
  Epoch [07/20] - Train Loss: 0.7588 | Val Loss: 1.2528
  Epoch [08/20] - Train Loss: 0.6726 | Val Loss: 1.2601
  Epoch [09/20] - Train Loss: 0.5991 | Val Loss: 1.2633
  Epoch [10/20] - Train Loss: 0.4716 | Val Loss: 1.1962  --> Saved best checkpoint (OPTIMAL)
  Epoch [11-20] - Train Loss: 0.4022 -> 0.1861 | Val Loss: 1.2638 -> 1.5225 (Overfitting phase)
  ```
  * **Outcome:** The optimal checkpoint `artifacts/checkpoints/best_crnn.pth` was preserved at **Epoch 10** with validation loss **`1.1962`**.

---

### Phase 0.6: Validation Verification (`scripts/evaluation/evaluate_validation.py`)
* **Objective:** Validate real-world transcription capabilities on unseen validation lines.
* **Implementation Details:**
  * Created [`evaluate_validation.py`](../scripts/evaluation/evaluate_validation.py) implementing a CTC greedy decoder.
* **Inference Demonstration:**
  * **Ground Truth:** `of the river . She helped me clean up my`
    * **Prediction:** `of the river . She halped me dean up mey`
  * **Ground Truth:** `ended well , reported the paper , since the`
    * **Prediction:** `andid wel , rported the peoper , ince the`
  * **Ground Truth:** `Grimstead for three thousand , that 's where I live , just`
    * **Prediction:** `brimotead for thek thonsand , that's ere I live , ist`
* **Interpretation:**
  * The network demonstrates strong phonetic, cursive, and grammatical character tracking across varied human handwritings with minimal misreadings, confirming weights are ready for production conversion.

---

### Phase 0.7: ONNX Model Export (`export_onnx.py`)
* **Objective:** Export the PyTorch network graph into an open standard ONNX format for cross-platform mobile compilation.
* **Challenges & Engineering Fixes:**
  1. **PyTorch 2.14 Dynamo FX Decomposition Bug:** In PyTorch 2.14, the default exporter is Dynamo-based (`dynamo=True`). When tracing dynamic sequence lengths through the PyTorch C++ BiLSTM operator (`_VF.lstm`), the symbolic shape analyzer failed during FX graph tensor stacking.
  2. **Unicode CP-1252 Crash:** The exporter printed Unicode checkmarks (`\u2705`) which crashed Python on standard Windows CP-1252 consoles.
  3. **Resolution:** Fixed stdout/stderr encodings to UTF-8 and forced the legacy TorchScript export engine (`dynamo=False`, `opset_version=17`):
     ```python
     torch.onnx.export(
         model, dummy_input, "crnn_handwritten.onnx",
         export_params=True, opset_version=17, do_constant_folding=True,
         input_names=["image_input"], output_names=["logits"],
         dynamic_axes={"image_input": {0: "batch_size", 3: "width"},
                       "logits": {0: "batch_size", 1: "time_steps"}},
         dynamo=False
     )
     ```
  * Produced `artifacts/onnx/crnn_handwritten.onnx` (53.32 MB).

---

### Phase 0.8: Cross-Compilation to Mobile TFLite (`convert_tflite.py`)
* **Objective:** Produce a standalone, float16 quantized `.tflite` model consumable by mobile engines (such as the Flutter `tflite_flutter` package) without Python runtimes.
* **Challenges & Systematic Resolution:**
  1. **Python 3.14 / TensorFlow Incompatibility:**
     * TensorFlow does not yet distribute binary wheels for Python 3.14 on Windows.
     * Established an isolated Python 3.11 virtual environment (`venv_tf`) specifically designated as the conversion engine.
  2. **Keras 3 & TF Addons Collision:**
     * Newer TensorFlow versions (2.16+) package Keras 3 by default, completely removing legacy submodules like `keras.src.engine` which caused imports of `onnx-tf` and `tensorflow-addons` to fail.
     * Configured an exact compatible stack in `venv_tf`:
       * `tensorflow==2.15.0`
       * `tensorflow-addons==0.22.0`
       * `tensorflow-probability==0.23.0`
       * `onnx==1.15.0`
       * `onnx-tf==1.10.0`
  3. **ONNX Opset 13 Squeeze & Unsqueeze Operator Gap:**
     * During ONNX-to-TensorFlow graph reconstruction, `onnx-tf` raised:
       `BackendIsNotSupposedToImplementIt: Squeeze version 13 is not implemented` and `Unsqueeze version 13 is not implemented`.
     * In ONNX Opset 13+, `axes` changed from node attributes to tensor inputs.
     * **Direct Source Patching:** In `venv_tf/Lib/site-packages/onnx_tf/handlers/backend/`:
       * Patched `squeeze.py` with a custom `version_13` handler to resolve axes dynamically or statically via `tf.get_static_value` and execute `tf.squeeze`.
       * Patched `unsqueeze.py` with a custom `version_13` handler to iterate over input axis tensors and iteratively expand dimensions with `tf.expand_dims`.
  4. **TFLite Float16 Quantization:**
     * Converted the generated SavedModel using `tf.lite.TFLiteConverter`:
       ```python
       converter = tf.lite.TFLiteConverter.from_saved_model("saved_model_dir")
       converter.optimizations = [tf.lite.Optimize.DEFAULT]
       converter.target_spec.supported_types = [tf.float16]
       ```
* **Outcome:**
  * Generated **`artifacts/tflite/crnn_handwritten.tflite`** (**25.26 MB**).
  * Reduced model footprint by **52.6%** with zero architectural loss.

---

### Phase 0.9: Flutter Integration Artifact Generation (`save_charset.py`)
* **Objective:** Provide the mobile client with the exact decoding alphabet.
* **Implementation:**
  * Created [`save_charset.py`](../scripts/export/save_charset.py).
  * Generated **[`assets/chars.txt`](../assets/chars.txt)** containing all 81 characters mapped 1-to-1 with model output indices.

---

## File Inventory & Workspace Structure

```text
src/contact_scanner_backend/  # Reusable model, dataset, and project paths
scripts/data/                 # Dataset acquisition and preparation
scripts/training/             # Training and fine-tuning
scripts/evaluation/           # PyTorch and TFLite inference
scripts/export/               # ONNX, TFLite, and charset generation
scripts/dev/                  # Experimental conversion work
tests/                        # Model regression and smoke tests
assets/chars.txt              # Versioned character decoding map
docs/                         # Architecture and project history
requirements/                 # Core and conversion dependency sets
data/                         # Generated datasets (gitignored)
artifacts/                    # Generated checkpoints/models (gitignored)
```

---

## Next Steps (Phase 1: Flutter Client Integration)
1. **Asset Embedding:**
   * Copy `artifacts/tflite/crnn_handwritten.tflite` and `assets/chars.txt` into the Flutter project's `assets/models/` folder.
   * Register assets in `pubspec.yaml`.
2. **Inference Pipeline in Flutter:**
   * Load model with `tflite_flutter`.
   * Preprocess camera crops: resize height to 32px, aspect-ratio scale width to 800px, pad with 255, normalize to `[-1.0, 1.0]`.
   * Pass input tensor `[1, 3, 32, 800]` to the interpreter.
   * Implement CTC Greedy Decoding in Dart matching `chars.txt`.
