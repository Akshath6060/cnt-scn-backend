/// Typed, user-safe error taxonomy.
///
/// Every failure surfaced to the UI carries a [userMessage] that is safe to
/// display: it never contains stack traces, file paths, phone numbers, names,
/// or OCR output (see `core/utils/redaction.dart` and requirement §25/§28).
library;

/// Stable machine-readable identity for a failure.
enum AppErrorCode {
  cameraUnavailable,
  cameraPermissionDenied,
  captureFailed,
  documentNotDetected,
  poorImageQuality,
  preprocessingFailed,
  modelMissing,
  modelLoadFailed,
  modelIncompatible,
  inferenceFailed,
  lowMemory,
  noTextDetected,
  noPhoneNumbersDetected,
  contactsPermissionDenied,
  contactReadFailed,
  contactCreateFailed,
  contactDeleteFailed,
  databaseFailure,
  backgroundTaskFailure,
  cancelled,
  unknown,
}

/// Base class for all recoverable, reportable application errors.
///
/// [cause] and [stackTrace] are retained for local diagnostics only and must
/// never be rendered in the UI.
class AppException implements Exception {
  const AppException(
    this.code,
    this.userMessage, {
    this.cause,
    this.stackTrace,
    this.isRecoverable = true,
  });

  final AppErrorCode code;

  /// Safe to show to the end user.
  final String userMessage;

  final Object? cause;
  final StackTrace? stackTrace;

  /// Whether retrying the same operation could plausibly succeed.
  final bool isRecoverable;

  @override
  String toString() => 'AppException(${code.name}): $userMessage';
}

/// Camera subsystem failures.
class CameraException extends AppException {
  const CameraException(super.code, super.message, {super.cause, super.stackTrace});

  static const unavailable = CameraException(
    AppErrorCode.cameraUnavailable,
    'No usable camera was found on this device.',
  );

  static const permissionDenied = CameraException(
    AppErrorCode.cameraPermissionDenied,
    'Camera access is needed to scan a contact sheet. '
    'You can enable it in Settings.',
  );
}

/// Document detection / preprocessing failures.
class ImageProcessingException extends AppException {
  const ImageProcessingException(
    super.code,
    super.message, {
    super.cause,
    super.stackTrace,
  });

  static const documentNotDetected = ImageProcessingException(
    AppErrorCode.documentNotDetected,
    'The page edges could not be found. Adjust the corners manually, '
    'or retake the photo against a contrasting background.',
  );
}

/// On-device ML failures. These are the ones most likely to be hit on a
/// device where the bundled model is absent or the device is out of memory.
class MlException extends AppException {
  const MlException(super.code, super.message, {super.cause, super.stackTrace});

  static const modelMissing = MlException(
    AppErrorCode.modelMissing,
    'The on-device recognition model is not bundled with this build. '
    'Handwriting recognition is unavailable.',
    // Not recoverable by retrying — the asset genuinely is not present.
  );

  static const modelLoadFailed = MlException(
    AppErrorCode.modelLoadFailed,
    'The on-device recognition model could not be loaded on this device.',
  );

  static const incompatible = MlException(
    AppErrorCode.modelIncompatible,
    'The bundled recognition model is not compatible with this app version.',
  );

  static const inferenceFailed = MlException(
    AppErrorCode.inferenceFailed,
    'Handwriting recognition failed while reading this page.',
  );

  static const lowMemory = MlException(
    AppErrorCode.lowMemory,
    'This device ran low on memory while reading the page. '
    'Try scanning a smaller section.',
  );
}

/// Native phonebook failures.
class ContactsException extends AppException {
  const ContactsException(super.code, super.message, {super.cause, super.stackTrace});

  static const permissionDenied = ContactsException(
    AppErrorCode.contactsPermissionDenied,
    'Contacts access is needed to save and later remove these contacts. '
    'You can enable it in Settings.',
  );

  static const createFailed = ContactsException(
    AppErrorCode.contactCreateFailed,
    'The contact could not be saved to your phonebook.',
  );

  static const deleteFailed = ContactsException(
    AppErrorCode.contactDeleteFailed,
    'The contact could not be removed from your phonebook.',
  );
}

/// Local SQLite failures.
class DatabaseException extends AppException {
  const DatabaseException(String message, {super.cause, super.stackTrace})
      : super(AppErrorCode.databaseFailure, message);

  static const generic = DatabaseException(
    'The local contact registry could not be opened. '
    'Temporary-contact tracking is unavailable.',
  );
}

/// Raised when the user aborts a pipeline run.
class CancelledException extends AppException {
  const CancelledException()
      : super(AppErrorCode.cancelled, 'Scan cancelled.', isRecoverable: false);
}
