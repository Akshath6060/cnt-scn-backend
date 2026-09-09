import 'package:permission_handler/permission_handler.dart';

import '../errors/app_exceptions.dart';

/// Contextual permission requests (§27).
///
/// Only camera and contacts are ever requested, and only at the moment the
/// feature needing them is used. No location, microphone, storage, or network
/// permission is asked for.
class PermissionService {
  const PermissionService();

  /// Requested when a scan starts — never at launch.
  Future<void> ensureCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) throw CameraException.permissionDenied;
  }

  /// Requested when contacts are read for duplicate checking or written.
  Future<void> ensureContacts() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) throw ContactsException.permissionDenied;
  }

  Future<bool> hasCamera() async => Permission.camera.isGranted;

  Future<bool> hasContacts() async => Permission.contacts.isGranted;

  /// True when the user chose "Don't ask again"; the UI must then send them to
  /// system settings rather than re-prompting.
  Future<bool> isCameraPermanentlyDenied() =>
      Permission.camera.isPermanentlyDenied;

  Future<bool> isContactsPermanentlyDenied() =>
      Permission.contacts.isPermanentlyDenied;

  Future<bool> openSettings() => openAppSettings();
}
