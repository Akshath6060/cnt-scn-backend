import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';
import '../models/recognized_text.dart';
import 'charset.dart';
import 'ctc_decoder.dart';
import 'tflite_model_manager.dart';

/// Stage 3.2 — reads the handwriting inside each detected region (§6).
///
/// The abstraction exists so the UI and the extraction engine never touch
/// TensorFlow Lite types directly (§6, §35).
abstract class HandwritingRecognizer {
  /// Human-readable engine name, surfaced in Settings.
  String get engineName;

  /// True for development stand-ins. The pipeline refuses to treat mock output
  /// as production data (§30).
  bool get isMock;

  /// Prepares the engine. Safe to call more than once.
  Future<void> initialize();

  /// Recognises the text inside [regions] of [document].
  ///
  /// [onProgress] reports `(completed, total)` so the processing screen can
  /// show genuine progress rather than an invented percentage (§23).
  Future<List<RecognizedText>> recognize(
    img.Image document,
    List<TextRegion> regions, {
    void Function(int completed, int total)? onProgress,
  });

  Future<void> dispose();
}

/// Development stand-in used before the trained model is available (§30).
///
/// Emits deterministic, plausible contact-sheet content derived from region
/// geometry, so the review, pairing and persistence layers can be exercised
/// end to end. **Never** selected as the production default — see
/// `RecognizerFactory`.
class MockHandwritingRecognizer implements HandwritingRecognizer {
  MockHandwritingRecognizer({this.seed = 7});

  final int seed;

  static const _names = [
    'Anu',
    'Rahul',
    'Neha',
    'Kiran',
    'Sanjay',
    'Priya',
    'Vikram',
    'Meera',
    'Arjun',
    'Divya',
    'Rohit',
    'Sneha',
  ];

  @override
  String get engineName => 'Mock recogniser (development only)';

  @override
  bool get isMock => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<List<RecognizedText>> recognize(
    img.Image document,
    List<TextRegion> regions, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final random = math.Random(seed);
    final results = <RecognizedText>[];

    // Regions arrive in reading order, so alternating name/number down the
    // page mimics a two-column contact sheet.
    for (var i = 0; i < regions.length; i++) {
      final region = regions[i];
      final box = region.boundingBox;

      // Wide regions on the right of the page read as numbers.
      final isPhone = box.centerX > document.width * 0.45;

      final text = isPhone
          ? _phone(random)
          : _names[(i ~/ 2 + seed) % _names.length];

      results.add(
        RecognizedText(
          text: text,
          confidence: 0.80 + random.nextDouble() * 0.18,
          boundingBox: box,
          detectionConfidence: region.confidence,
        ),
      );
      onProgress?.call(i + 1, regions.length);
    }
    return results;
  }

  String _phone(math.Random random) {
    final buffer = StringBuffer()..write(6 + random.nextInt(4));
    for (var i = 0; i < 9; i++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }
}

/// Production recogniser backed by the bundled ResNet18-CRNN TFLite model.
///
/// The tensor contract mirrors the training pipeline exactly (see
/// `docs/ML_MODEL_INTEGRATION.md`):
///   * input  `[1, 3, 32, 800]` float32, NCHW, RGB,
///   * pixels scaled to `[-1, 1]` via `value / 127.5 - 1`,
///   * aspect-preserving resize to height 32, right-padded with white,
///   * output `[1, T, C]` logits decoded with greedy CTC, blank at index 0.
class TFLiteHandwritingRecognizer implements HandwritingRecognizer {
  TFLiteHandwritingRecognizer({
    required TfliteModelManager modelManager,
    this.assetPath = AppConstants.recognizerAsset,
    Charset? charset,
  }) : _models = modelManager,
       _charset = charset ?? Charset.fallback;

  final TfliteModelManager _models;
  final String assetPath;

  Charset _charset;
  LoadedModel? _model;
  CtcDecoder? _decoder;
  bool _initialized = false;

  static const _tag = 'TFLiteRecognizer';

  @override
  String get engineName => 'ResNet18-CRNN (TFLite)';

  @override
  bool get isMock => false;

  /// Whether a usable interpreter is loaded.
  bool get isReady => _model != null;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _charset = await Charset.load();
    _decoder = CtcDecoder(_charset);

    // A missing asset is expected while the model is still being trained;
    // it surfaces as `isReady == false`, not as a crash (§7, §30).
    _model = await _models.load(assetPath);
    if (_model == null) {
      AppLog.warn(_tag, 'recogniser model not bundled');
      return;
    }

    _validateSignature(_model!.signature);
  }

  /// Guards against a model whose tensors do not match this code (§7).
  void _validateSignature(ModelSignature signature) {
    final shape = signature.inputShape;
    if (shape.length != 4) {
      throw MlException(
        AppErrorCode.modelIncompatible,
        MlException.incompatible.userMessage,
        cause: 'expected a rank-4 input, got $shape',
      );
    }

    final expected = [
      1,
      AppConstants.recognizerInputChannels,
      AppConstants.recognizerInputHeight,
      AppConstants.recognizerInputWidth,
    ];
    // Dimensions of -1 are dynamic and acceptable.
    for (var i = 0; i < 4; i++) {
      if (shape[i] > 0 && shape[i] != expected[i]) {
        throw MlException(
          AppErrorCode.modelIncompatible,
          MlException.incompatible.userMessage,
          cause: 'input shape $shape does not match $expected',
        );
      }
    }

    final out = signature.outputShape;
    if (out.length == 3 && out.last > 0) {
      _charset.assertMatchesClassCount(out.last);
    }
  }

  @override
  Future<List<RecognizedText>> recognize(
    img.Image document,
    List<TextRegion> regions, {
    void Function(int completed, int total)? onProgress,
  }) async {
    await initialize();

    final model = _model;
    final decoder = _decoder;
    if (model == null || decoder == null) {
      throw MlException.modelMissing;
    }

    final results = <RecognizedText>[];

    for (var i = 0; i < regions.length; i++) {
      final region = regions[i];
      try {
        final crop = _cropRegion(document, region);
        final input = buildInputTensor(crop);
        final logits = _runInference(model, input);
        final decoded = decoder.decode(logits);

        if (decoded.text.trim().isNotEmpty) {
          results.add(
            RecognizedText(
              text: decoded.text,
              confidence: decoded.confidence,
              boundingBox: region.boundingBox,
              detectionConfidence: region.confidence,
            ),
          );
        }
      } catch (e, s) {
        // One unreadable region must not abort the page (§25).
        AppLog.error(_tag, 'region $i failed', e, s);
      }
      onProgress?.call(i + 1, regions.length);
    }
    return results;
  }

  img.Image _cropRegion(img.Image document, TextRegion region) {
    final box = region.boundingBox;
    final x = box.left.round().clamp(0, document.width - 1);
    final y = box.top.round().clamp(0, document.height - 1);
    final w = box.width.round().clamp(1, document.width - x);
    final h = box.height.round().clamp(1, document.height - y);
    return img.copyCrop(document, x: x, y: y, width: w, height: h);
  }

  /// Builds the `[1, 3, 32, 800]` NCHW float32 tensor.
  ///
  /// Exposed for testing: this is the piece most likely to drift from the
  /// training pipeline, and a silent mismatch produces garbage rather than an
  /// error.
  static Float32List buildInputTensor(img.Image crop) {
    const h = AppConstants.recognizerInputHeight;
    const w = AppConstants.recognizerInputWidth;
    const c = AppConstants.recognizerInputChannels;

    // Aspect-preserving resize to height 32, capped at width 800.
    final scale = h / math.max(crop.height, 1);
    final targetW = math.max(1, math.min((crop.width * scale).round(), w));
    final resized = img.copyResize(
      crop,
      width: targetW,
      height: h,
      interpolation: img.Interpolation.linear,
    );

    // White canvas, image left-aligned — matching the training preprocessor.
    final tensor = Float32List(c * h * w);
    // 255 -> 255/127.5 - 1 = 1.0, so white padding is 1.0 everywhere.
    tensor.fillRange(0, tensor.length, 1.0);

    const planeSize = h * w;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < targetW; x++) {
        final p = resized.getPixel(x, y);
        final idx = y * w + x;
        tensor[idx] = p.r / 127.5 - 1.0; // R plane
        tensor[planeSize + idx] = p.g / 127.5 - 1.0; // G plane
        tensor[planeSize * 2 + idx] = p.b / 127.5 - 1.0; // B plane
      }
    }
    return tensor;
  }

  /// Runs the interpreter and returns `[timeSteps][numClasses]` logits.
  List<List<double>> _runInference(LoadedModel model, Float32List input) {
    final outputShape = model.signature.outputShape;
    if (outputShape.length != 3) {
      throw MlException.incompatible;
    }
    final timeSteps = outputShape[1];
    final classes = outputShape[2];

    // Nested list shaped exactly as the interpreter expects.
    final output = List.generate(
      1,
      (_) => List.generate(timeSteps, (_) => List<double>.filled(classes, 0)),
      growable: false,
    );

    final reshapedInput = [
      _reshapeToNchw(
        input,
        AppConstants.recognizerInputChannels,
        AppConstants.recognizerInputHeight,
        AppConstants.recognizerInputWidth,
      ),
    ];

    try {
      model.interpreter.run(reshapedInput, output);
    } catch (e, s) {
      throw MlException(
        AppErrorCode.inferenceFailed,
        MlException.inferenceFailed.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
    return output.first;
  }

  List<List<List<double>>> _reshapeToNchw(
    Float32List flat,
    int channels,
    int height,
    int width,
  ) => List.generate(
    channels,
    (c) => List.generate(
      height,
      (y) => List.generate(
        width,
        (x) => flat[c * height * width + y * width + x],
        growable: false,
      ),
      growable: false,
    ),
    growable: false,
  );

  @override
  Future<void> dispose() async {
    _models.release(assetPath);
    _model = null;
    _initialized = false;
  }
}

/// Production fallback for ONNX models whose converted TFLite graph cannot be
/// prepared by the device's LiteRT version.
class OnnxHandwritingRecognizer implements HandwritingRecognizer {
  OnnxHandwritingRecognizer({
    this.assetPath = AppConstants.onnxRecognizerAsset,
    Charset? charset,
    OnnxRuntime? runtime,
  }) : _charset = charset ?? Charset.fallback,
       _runtime = runtime ?? OnnxRuntime();

  final String assetPath;
  final OnnxRuntime _runtime;

  Charset _charset;
  CtcDecoder? _decoder;
  OrtSession? _session;
  bool _initialized = false;

  static const _tag = 'OnnxRecognizer';

  @override
  String get engineName => 'ResNet18-CRNN (ONNX Runtime)';

  @override
  bool get isMock => false;

  bool get isReady => _session != null;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _charset = await Charset.load();
    _decoder = CtcDecoder(_charset);

    try {
      final session = await _runtime.createSessionFromAsset(
        assetPath,
        options: OrtSessionOptions(intraOpNumThreads: 2),
      );
      if (session.inputNames.length != 1 || session.outputNames.length != 1) {
        await session.close();
        throw MlException.incompatible;
      }
      final inputInfo = await session.getInputInfo();
      final outputInfo = await session.getOutputInfo();
      final inputShape = inputInfo.length == 1
          ? List<int>.from(inputInfo.single['shape'] as List)
          : const <int>[];
      final outputShape = outputInfo.length == 1
          ? List<int>.from(outputInfo.single['shape'] as List)
          : const <int>[];
      const expectedInput = [1, 3, 32, 800];
      final inputMatches =
          inputShape.length == expectedInput.length &&
          List.generate(
            expectedInput.length,
            (i) => inputShape[i] < 0 || inputShape[i] == expectedInput[i],
          ).every((matches) => matches);
      final outputMatches =
          outputShape.length == 3 &&
          (outputShape.first < 0 || outputShape.first == 1) &&
          (outputShape.last < 0 || outputShape.last == _charset.length);
      if (!inputMatches || !outputMatches) {
        await session.close();
        throw MlException.incompatible;
      }
      _session = session;
      AppLog.info(
        _tag,
        'loaded $assetPath  in=${session.inputNames}$inputShape '
        'out=${session.outputNames}$outputShape',
      );
    } on MlException {
      rethrow;
    } catch (e, s) {
      AppLog.error(_tag, 'failed to load $assetPath', e, s);
      throw MlException(
        AppErrorCode.modelLoadFailed,
        MlException.modelLoadFailed.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<List<RecognizedText>> recognize(
    img.Image document,
    List<TextRegion> regions, {
    void Function(int completed, int total)? onProgress,
  }) async {
    await initialize();
    final session = _session;
    final decoder = _decoder;
    if (session == null || decoder == null) throw MlException.modelMissing;

    final results = <RecognizedText>[];
    for (var i = 0; i < regions.length; i++) {
      final region = regions[i];
      try {
        final crop = _cropRegion(document, region);
        final input = TFLiteHandwritingRecognizer.buildInputTensor(crop);
        final logits = await _runInference(session, input);
        final decoded = decoder.decode(logits);
        if (decoded.text.trim().isNotEmpty) {
          results.add(
            RecognizedText(
              text: decoded.text,
              confidence: decoded.confidence,
              boundingBox: region.boundingBox,
              detectionConfidence: region.confidence,
            ),
          );
        }
      } catch (e, s) {
        AppLog.error(_tag, 'region $i failed', e, s);
      }
      onProgress?.call(i + 1, regions.length);
    }
    return results;
  }

  img.Image _cropRegion(img.Image document, TextRegion region) {
    final box = region.boundingBox;
    final x = box.left.round().clamp(0, document.width - 1);
    final y = box.top.round().clamp(0, document.height - 1);
    final w = box.width.round().clamp(1, document.width - x);
    final h = box.height.round().clamp(1, document.height - y);
    return img.copyCrop(document, x: x, y: y, width: w, height: h);
  }

  Future<List<List<double>>> _runInference(
    OrtSession session,
    Float32List input,
  ) async {
    OrtValue? inputValue;
    Map<String, OrtValue>? outputs;
    try {
      inputValue = await OrtValue.fromList(input, const [1, 3, 32, 800]);
      outputs = await session.run({session.inputNames.first: inputValue});
      final output = outputs[session.outputNames.first];
      if (output == null ||
          output.shape.length != 3 ||
          output.shape.first != 1) {
        throw MlException.incompatible;
      }

      final timeSteps = output.shape[1];
      final classes = output.shape[2];
      _charset.assertMatchesClassCount(classes);
      final flat = await output.asFlattenedList();
      if (flat.length != timeSteps * classes) {
        throw MlException.incompatible;
      }
      return List.generate(
        timeSteps,
        (t) => List.generate(
          classes,
          (c) => (flat[t * classes + c] as num).toDouble(),
          growable: false,
        ),
        growable: false,
      );
    } on MlException {
      rethrow;
    } catch (e, s) {
      throw MlException(
        AppErrorCode.inferenceFailed,
        MlException.inferenceFailed.userMessage,
        cause: e,
        stackTrace: s,
      );
    } finally {
      await inputValue?.dispose();
      if (outputs != null) {
        for (final output in outputs.values) {
          await output.dispose();
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _initialized = false;
  }
}
