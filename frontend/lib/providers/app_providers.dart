import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exceptions.dart';
import '../core/permissions/permission_service.dart';
import '../database/app_database.dart';
import '../imaging/dart_image_processor.dart';
import '../imaging/document_image_processor.dart';
import '../ml/handwriting_recognizer.dart';
import '../ml/text_detector.dart';
import '../ml/tflite_model_manager.dart';
import '../platform/native_contacts/native_contacts_gateway.dart';
import '../repositories/temporary_contact_repository.dart';
import '../services/background_cleanup_service.dart';
import '../services/contact_extraction_service.dart';
import '../services/contact_scan_pipeline.dart';
import '../services/contact_service.dart';
import '../services/document_scanner_service.dart';
import '../services/duplicate_detection_service.dart';
import '../services/expiry_service.dart';
import '../services/image_preprocessing_service.dart';
import '../services/phone_number_parser.dart';
import '../services/settings_service.dart';
import '../services/spatial_contact_pairing_service.dart';
import '../services/temp_file_service.dart';

// ── Settings ───────────────────────────────────────────────────────────────

final settingsServiceProvider =
    Provider<SettingsService>((ref) => SettingsService());

/// Current user settings. Everything downstream reads this rather than
/// touching `SharedPreferences` directly.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AsyncValue<AppSettings>>(
  (ref) => SettingsNotifier(ref.watch(settingsServiceProvider)),
);

class SettingsNotifier extends StateNotifier<AsyncValue<AppSettings>> {
  SettingsNotifier(this._service) : super(const AsyncValue.loading()) {
    load();
  }

  final SettingsService _service;

  Future<void> load() async {
    state = await AsyncValue.guard(_service.load);
  }

  Future<void> update(AppSettings settings) async {
    state = AsyncValue.data(settings);
    await _service.save(settings);
  }

  AppSettings get current => state.valueOrNull ?? const AppSettings();
}

// ── Imaging & pipeline ─────────────────────────────────────────────────────

/// The active image-processing backend (§35).
///
/// Swap this single provider to move the whole app onto OpenCV — see
/// `docs/OPENCV_PIPELINE.md`.
final imageProcessorProvider =
    Provider<DocumentImageProcessor>((ref) => const DartImageProcessor());

final documentScannerProvider = Provider<DocumentScannerService>(
  (ref) => DocumentScannerService(processor: ref.watch(imageProcessorProvider)),
);

final preprocessingServiceProvider = Provider<ImagePreprocessingService>(
  (ref) =>
      ImagePreprocessingService(processor: ref.watch(imageProcessorProvider)),
);

final tempFileServiceProvider =
    Provider<TempFileService>((ref) => TempFileService());

final permissionServiceProvider =
    Provider<PermissionService>((ref) => const PermissionService());

// ── Machine learning ───────────────────────────────────────────────────────

/// One interpreter cache for the whole app (§24 — no duplicate models).
final modelManagerProvider = Provider<TfliteModelManager>((ref) {
  final manager = TfliteModelManager();
  ref.onDispose(manager.releaseAll);
  return manager;
});

final textDetectorProvider = Provider<TextDetector>(
  (ref) => TfliteTextDetector(fallback: const MorphologicalTextDetector()),
);

/// Builds the production recogniser.
///
/// The mock is **never** the production default (§30): it is used only when
/// the trained model is genuinely absent, the build is not a release build,
/// and the developer has explicitly opted in through Settings. Otherwise a
/// missing model surfaces as a clear, local error.
final handwritingRecognizerProvider =
    FutureProvider<HandwritingRecognizer>((ref) async {
  final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
  final manager = ref.watch(modelManagerProvider);

  final tflite = TFLiteHandwritingRecognizer(modelManager: manager);
  await tflite.initialize();
  if (tflite.isReady) {
    ref.onDispose(tflite.dispose);
    return tflite;
  }

  if (!kReleaseMode && settings.allowMockRecognizer) {
    return MockHandwritingRecognizer();
  }
  throw MlException.modelMissing;
});

final phoneNumberParserProvider = Provider<PhoneNumberParser>((ref) {
  final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
  return PhoneNumberParser(defaultCountryCode: settings.defaultCountryCode);
});

final contactExtractionProvider = Provider<ContactExtractionService>(
  (ref) => ContactExtractionService(
    phoneParser: ref.watch(phoneNumberParserProvider),
  ),
);

final spatialPairingProvider = Provider<SpatialContactPairingService>(
  (ref) => const SpatialContactPairingService(),
);

/// The orchestrator (§20). Async because it depends on recogniser start-up.
final scanPipelineProvider = FutureProvider<ContactScanPipeline>((ref) async {
  final recognizer = await ref.watch(handwritingRecognizerProvider.future);
  return ContactScanPipeline(
    scanner: ref.watch(documentScannerProvider),
    preprocessor: ref.watch(preprocessingServiceProvider),
    textDetector: ref.watch(textDetectorProvider),
    recognizer: recognizer,
    extractor: ref.watch(contactExtractionProvider),
    pairing: ref.watch(spatialPairingProvider),
  );
});

// ── Persistence & contacts ─────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final temporaryContactRepositoryProvider = Provider<TemporaryContactRepository>(
  (ref) => TemporaryContactRepository(ref.watch(appDatabaseProvider)),
);

final contactsGatewayProvider =
    Provider<NativeContactsGateway>((ref) => const FlutterContactsGateway());

final contactServiceProvider = Provider<ContactService>(
  (ref) => ContactService(
    gateway: ref.watch(contactsGatewayProvider),
    phoneParser: ref.watch(phoneNumberParserProvider),
  ),
);

final duplicateDetectionProvider = Provider<DuplicateDetectionService>(
  (ref) => DuplicateDetectionService(
    phoneParser: ref.watch(phoneNumberParserProvider),
  ),
);

final expiryServiceProvider = Provider<ExpiryService>(
  (ref) => ExpiryService(
    repository: ref.watch(temporaryContactRepositoryProvider),
    contacts: ref.watch(contactServiceProvider),
  ),
);

final backgroundCleanupProvider =
    Provider<BackgroundCleanupService>((ref) => BackgroundCleanupService());
