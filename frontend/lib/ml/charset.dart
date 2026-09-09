import 'package:flutter/services.dart' show rootBundle;

import '../core/constants/app_constants.dart';
import '../core/errors/app_exceptions.dart';

/// Character vocabulary used to decode recogniser output.
///
/// Must match the vocabulary the model was trained with, character for
/// character and *in order* — index 0 is the CTC blank (§31).
class Charset {
  const Charset(this.characters, {this.blankIndex = AppConstants.ctcBlankIndex});

  /// The training charset shipped by the backend
  /// (`backend/assets/chars.txt`). Index 0 is reserved for the CTC blank.
  static const String defaultCharacters =
      '-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ !"\'(),.:;?+@/-#*&';

  /// Fallback used when no `chars.txt` asset is bundled.
  static const Charset fallback = Charset(defaultCharacters);

  final String characters;
  final int blankIndex;

  int get length => characters.length;

  /// Maps a class index to its character; returns '' for the blank and for
  /// out-of-range indices, so a malformed tensor cannot crash decoding.
  String operator [](int index) {
    if (index == blankIndex) return '';
    if (index < 0 || index >= characters.length) return '';
    return characters[index];
  }

  /// Loads the charset from bundled assets, falling back to [defaultCharacters].
  ///
  /// Never touches the network (§2).
  static Future<Charset> load({
    String assetPath = AppConstants.charsetAsset,
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      // The file is a single line; strip only the trailing newline so that a
      // meaningful leading/!trailing space in the vocabulary is preserved.
      final cleaned = raw.replaceAll(RegExp(r'[\r\n]+$'), '');
      if (cleaned.isEmpty) return fallback;
      return Charset(cleaned);
    } catch (_) {
      // Asset absent is an expected, non-fatal condition.
      return fallback;
    }
  }

  /// Verifies that a model's class dimension matches this vocabulary.
  void assertMatchesClassCount(int classCount) {
    if (classCount != length) {
      throw MlException(
        AppErrorCode.modelIncompatible,
        MlException.incompatible.userMessage,
        cause: 'charset has $length classes, model emits $classCount',
      );
    }
  }
}
