import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/redaction.dart';
import 'providers/app_providers.dart';
import 'providers/temporary_contacts_provider.dart';
import 'screens/home/home_screen.dart';
import 'services/settings_service.dart';

/// Root widget.
///
/// Also owns the two lifecycle-driven cleanup triggers: one on first build
/// (app launch) and one whenever the app returns to the foreground (§15).
class ContactScannerApp extends ConsumerStatefulWidget {
  const ContactScannerApp({super.key});

  @override
  ConsumerState<ContactScannerApp> createState() => _ContactScannerAppState();
}

class _ContactScannerAppState extends ConsumerState<ContactScannerApp>
    with WidgetsBindingObserver {
  static const _tag = 'App';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onLaunch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// §15 trigger 2 — cleanup on app launch.
  Future<void> _onLaunch() async {
    // Register the OS-level periodic task (§15 trigger 1).
    await ref.read(backgroundCleanupProvider).initialize();

    // Sweep any working files a previous crash left behind (§28).
    await ref.read(tempFileServiceProvider).purgeStale();

    await _runCleanup('launch');
  }

  /// §15 trigger 3 — cleanup whenever the app resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runCleanup('resume');
    } else if (state == AppLifecycleState.paused) {
      // Release interpreters while backgrounded so the OS is less likely to
      // kill us for memory (§24).
      ref.read(modelManagerProvider).releaseAll();
    }
  }

  Future<void> _runCleanup(String trigger) async {
    try {
      final report = await ref.read(expiryServiceProvider).runCleanup();
      if (report.didWork) {
        AppLog.info(_tag, '$trigger cleanup: $report');
        ref.invalidate(temporaryContactsProvider);
      }
    } catch (e, s) {
      // Cleanup failing must never block app start (§25).
      AppLog.error(_tag, '$trigger cleanup failed', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: switch (settings?.themeMode ?? AppThemeMode.system) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      home: const HomeScreen(),
    );
  }
}
