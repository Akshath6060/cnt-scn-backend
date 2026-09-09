import 'package:shared_preferences/shared_preferences.dart';

/// Locally-stored user preferences (§19, §5).
///
/// Uses `shared_preferences`, which is backed by scoped app storage on both
/// platforms — nothing here leaves the device.
class AppSettings {
  const AppSettings({
    this.keepScannedImages = false,
    this.showDebugPreview = false,
    this.defaultCountryCode = '+91',
    this.themeMode = AppThemeMode.system,
    this.allowMockRecognizer = false,
  });

  /// §19 — off by default: captured sheets are not retained.
  final bool keepScannedImages;

  /// §5 — developer preview of the preprocessing stages. Off in production.
  final bool showDebugPreview;

  final String defaultCountryCode;
  final AppThemeMode themeMode;

  /// §30 — permits the mock recogniser to stand in when no model is bundled.
  /// The pipeline still labels every result it produces.
  final bool allowMockRecognizer;

  AppSettings copyWith({
    bool? keepScannedImages,
    bool? showDebugPreview,
    String? defaultCountryCode,
    AppThemeMode? themeMode,
    bool? allowMockRecognizer,
  }) =>
      AppSettings(
        keepScannedImages: keepScannedImages ?? this.keepScannedImages,
        showDebugPreview: showDebugPreview ?? this.showDebugPreview,
        defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
        themeMode: themeMode ?? this.themeMode,
        allowMockRecognizer: allowMockRecognizer ?? this.allowMockRecognizer,
      );
}

enum AppThemeMode { system, light, dark }

/// Reads and writes [AppSettings].
class SettingsService {
  SettingsService({SharedPreferences? preferences}) : _prefs = preferences;

  SharedPreferences? _prefs;

  static const _keepImages = 'settings.keep_scanned_images';
  static const _debugPreview = 'settings.show_debug_preview';
  static const _countryCode = 'settings.default_country_code';
  static const _theme = 'settings.theme_mode';
  static const _allowMock = 'settings.allow_mock_recognizer';

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<AppSettings> load() async {
    final prefs = await _instance;
    return AppSettings(
      keepScannedImages: prefs.getBool(_keepImages) ?? false,
      showDebugPreview: prefs.getBool(_debugPreview) ?? false,
      defaultCountryCode: prefs.getString(_countryCode) ?? '+91',
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == prefs.getString(_theme),
        orElse: () => AppThemeMode.system,
      ),
      allowMockRecognizer: prefs.getBool(_allowMock) ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await _instance;
    await prefs.setBool(_keepImages, settings.keepScannedImages);
    await prefs.setBool(_debugPreview, settings.showDebugPreview);
    await prefs.setString(_countryCode, settings.defaultCountryCode);
    await prefs.setString(_theme, settings.themeMode.name);
    await prefs.setBool(_allowMock, settings.allowMockRecognizer);
  }
}
