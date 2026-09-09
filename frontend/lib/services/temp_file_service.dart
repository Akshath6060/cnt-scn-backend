import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/redaction.dart';

/// Manages the short-lived image files a scan produces (§19, §28).
///
/// Captured contact sheets are **never** written to the shared gallery. They
/// live in the app's private temporary directory and are removed as soon as
/// the scan ends — successfully, by cancellation, or by error.
class TempFileService {
  TempFileService({Directory? overrideRoot}) : _overrideRoot = overrideRoot;

  final Directory? _overrideRoot;
  Directory? _workingDir;

  static const _tag = 'TempFileService';

  /// Private per-scan working directory.
  Future<Directory> workingDirectory() async {
    final existing = _workingDir;
    if (existing != null && existing.existsSync()) return existing;

    final root = _overrideRoot ?? await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, AppConstants.scanWorkingDirName));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _workingDir = dir;
    return dir;
  }

  /// Writes bytes to a scoped temporary file.
  Future<File> writeTemp(String name, Uint8List bytes) async {
    final dir = await workingDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Deletes everything produced by the current scan.
  ///
  /// Called on success, on cancellation, and on fatal error (§19).
  Future<void> clearWorkingDirectory() async {
    try {
      final dir = _workingDir;
      if (dir == null || !dir.existsSync()) return;
      await dir.delete(recursive: true);
      _workingDir = null;
      AppLog.info(_tag, 'cleared scan working directory');
    } catch (e, s) {
      AppLog.error(_tag, 'failed to clear working directory', e, s);
    }
  }

  /// Deletes a single file, ignoring a file that is already gone.
  Future<void> deleteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e, s) {
      AppLog.error(_tag, 'failed to delete ${maskPath(path)}', e, s);
    }
  }

  /// Housekeeping sweep for files a previous crash left behind (§28).
  Future<void> purgeStale({Duration olderThan = const Duration(hours: 6)}) async {
    try {
      final dir = await workingDirectory();
      final cutoff = DateTime.now().subtract(olderThan);
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        if (entity.statSync().modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
    } catch (e, s) {
      AppLog.error(_tag, 'stale purge failed', e, s);
    }
  }
}
