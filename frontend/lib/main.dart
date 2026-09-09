import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/utils/redaction.dart';

/// Application entry point.
///
/// Deliberately minimal (§39): it starts the framework, installs a
/// privacy-safe error handler, and hands off to [ContactScannerApp].
///
/// Note what is *absent*: no network client, no analytics, no remote config,
/// no crash uploader. The app performs no I/O beyond the device itself (§2).
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Framework errors are logged locally and never uploaded (§2, §28).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.error(
      'FlutterError',
      'uncaught framework error',
      details.exception,
      details.stack,
    );
  };

  // Replace the red error box with something a user can act on (§25).
  ErrorWidget.builder = (details) {
    AppLog.error('ErrorWidget', 'widget build failed', details.exception);
    return const _FatalErrorView();
  };

  runApp(const ProviderScope(child: ContactScannerApp()));
}

/// Shown in place of a widget that failed to build. Carries no stack trace.
class _FatalErrorView extends StatelessWidget {
  const _FatalErrorView();

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Something went wrong on this screen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Go back and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
