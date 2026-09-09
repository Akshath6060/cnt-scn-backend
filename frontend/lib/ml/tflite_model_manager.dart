import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/errors/app_exceptions.dart';
import '../core/utils/redaction.dart';

/// Metadata describing a loaded interpreter's tensor contract.
class ModelSignature {
  const ModelSignature({
    required this.inputShape,
    required this.outputShape,
    required this.inputType,
    required this.outputType,
  });

  final List<int> inputShape;
  final List<int> outputShape;
  final String inputType;
  final String outputType;

  @override
  String toString() =>
      'in=$inputShape($inputType) out=$outputShape($outputType)';
}

/// A loaded interpreter plus its signature.
class LoadedModel {
  LoadedModel(this.interpreter, this.signature, this.assetPath);

  final Interpreter interpreter;
  final ModelSignature signature;
  final String assetPath;
}

/// Owns the lifetime of every TFLite interpreter in the app (§7, §24).
///
/// Responsibilities:
///   * load models **only** from bundled assets — never from the network,
///   * keep exactly one interpreter per asset so a model is not held in
///     memory twice,
///   * turn every failure mode into a typed [MlException] instead of a crash.
class TfliteModelManager {
  TfliteModelManager({this.threads = 2});

  /// Interpreter thread count. Two is a reasonable default for mid-range
  /// devices: more threads contend with the UI isolate.
  final int threads;

  final Map<String, LoadedModel> _cache = {};
  final Map<String, Future<LoadedModel?>> _inFlight = {};

  static const _tag = 'TfliteModelManager';

  /// Whether [assetPath] is actually bundled with this build.
  ///
  /// Checked before loading so a missing model reports [MlException.modelMissing]
  /// rather than an opaque platform error (§7).
  Future<bool> isModelBundled(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      return data.lengthInBytes > 0;
    } catch (_) {
      return false;
    }
  }

  /// Loads (or returns the cached) interpreter for [assetPath].
  ///
  /// Returns `null` when the asset is not bundled — an expected condition
  /// while the trained model is still being produced (§30). Throws
  /// [MlException] for genuine load failures.
  Future<LoadedModel?> load(String assetPath) async {
    final cached = _cache[assetPath];
    if (cached != null) return cached;

    // Collapse concurrent requests so two screens cannot each load a copy.
    final pending = _inFlight[assetPath];
    if (pending != null) return pending;

    final future = _load(assetPath);
    _inFlight[assetPath] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(assetPath);
    }
  }

  Future<LoadedModel?> _load(String assetPath) async {
    if (!await isModelBundled(assetPath)) {
      AppLog.warn(_tag, 'model asset not bundled: $assetPath');
      return null;
    }

    try {
      final options = InterpreterOptions()..threads = threads;
      final interpreter = await Interpreter.fromAsset(
        assetPath,
        options: options,
      );

      final signature = _readSignature(interpreter, assetPath);
      final model = LoadedModel(interpreter, signature, assetPath);
      _cache[assetPath] = model;

      AppLog.info(_tag, 'loaded $assetPath  $signature');
      return model;
    } on MlException {
      rethrow;
    } catch (e, s) {
      // Covers out-of-memory, unsupported ops, and corrupt files alike.
      final isMemory = e.toString().toLowerCase().contains('memory');
      AppLog.error(_tag, 'failed to load $assetPath', e, s);
      throw MlException(
        isMemory ? AppErrorCode.lowMemory : AppErrorCode.modelLoadFailed,
        isMemory
            ? MlException.lowMemory.userMessage
            : MlException.modelLoadFailed.userMessage,
        cause: e,
        stackTrace: s,
      );
    }
  }

  ModelSignature _readSignature(Interpreter interpreter, String assetPath) {
    try {
      final input = interpreter.getInputTensors().first;
      final output = interpreter.getOutputTensors().first;
      return ModelSignature(
        inputShape: List<int>.from(input.shape),
        outputShape: List<int>.from(output.shape),
        inputType: input.type.toString(),
        outputType: output.type.toString(),
      );
    } catch (e, s) {
      throw MlException(
        AppErrorCode.modelIncompatible,
        MlException.incompatible.userMessage,
        cause: 'could not read tensors of $assetPath: $e',
        stackTrace: s,
      );
    }
  }

  /// Releases one interpreter.
  void release(String assetPath) {
    final model = _cache.remove(assetPath);
    try {
      model?.interpreter.close();
    } catch (e, s) {
      AppLog.error(_tag, 'error closing interpreter', e, s);
    }
  }

  /// Releases every interpreter. Called when the app is backgrounded under
  /// memory pressure and on dispose (§24).
  void releaseAll() {
    for (final path in _cache.keys.toList()) {
      release(path);
    }
  }

  bool get hasLoadedModels => _cache.isNotEmpty;
}
