import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../services/settings_service.dart';
import '../../widgets/offline_badge.dart';

/// Settings and About (§18, §19, §5).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Settings could not be loaded.'),
        ),
        data: (settings) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ── Privacy (§18) ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: const OfflineBadge(showDescription: true),
                ),
              ),
            ),

            const _SectionHeader('Images'),
            SwitchListTile(
              title: const Text('Keep scanned images'),
              subtitle: const Text(
                'Off by default. When off, photos of contact sheets are '
                'deleted as soon as the scan finishes and are never added to '
                'your gallery.',
              ),
              value: settings.keepScannedImages,
              onChanged: (value) => notifier.update(
                settings.copyWith(keepScannedImages: value),
              ),
            ),

            const _SectionHeader('Appearance'),
            ListTile(
              title: const Text('Theme'),
              subtitle: Text(switch (settings.themeMode) {
                AppThemeMode.system => 'Follow system',
                AppThemeMode.light => 'Light',
                AppThemeMode.dark => 'Dark',
              }),
              trailing: SegmentedButton<AppThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AppThemeMode.system,
                    icon: Icon(Icons.brightness_auto, size: 18),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.light,
                    icon: Icon(Icons.light_mode, size: 18),
                  ),
                  ButtonSegment(
                    value: AppThemeMode.dark,
                    icon: Icon(Icons.dark_mode, size: 18),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (selection) => notifier.update(
                  settings.copyWith(themeMode: selection.first),
                ),
              ),
            ),

            const _SectionHeader('Phone numbers'),
            ListTile(
              title: const Text('Default country code'),
              subtitle: Text(
                'Applied to 10-digit numbers with no country code. '
                'Currently ${settings.defaultCountryCode}.',
              ),
              trailing: DropdownButton<String>(
                value: settings.defaultCountryCode,
                items: const [
                  DropdownMenuItem(value: '+91', child: Text('+91')),
                  DropdownMenuItem(value: '+1', child: Text('+1')),
                  DropdownMenuItem(value: '+44', child: Text('+44')),
                  DropdownMenuItem(value: '+61', child: Text('+61')),
                  DropdownMenuItem(value: '+971', child: Text('+971')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  notifier.update(settings.copyWith(defaultCountryCode: value));
                },
              ),
            ),

            // ── Developer options: debug builds only (§5, §30) ───────────
            if (!kReleaseMode) ...[
              const _SectionHeader('Developer'),
              SwitchListTile(
                title: const Text('Show preprocessing preview'),
                subtitle: const Text(
                  'Keeps the grayscale and thresholded stages for inspection. '
                  'Costs extra memory per scan.',
                ),
                value: settings.showDebugPreview,
                onChanged: (value) => notifier.update(
                  settings.copyWith(showDebugPreview: value),
                ),
              ),
              SwitchListTile(
                title: const Text('Allow mock recogniser'),
                subtitle: const Text(
                  'Used only when no trained model is bundled. Results are '
                  'synthetic and are labelled as such. Never active in a '
                  'release build.',
                ),
                value: settings.allowMockRecognizer,
                onChanged: (value) => notifier.update(
                  settings.copyWith(allowMockRecognizer: value),
                ),
              ),
              ListTile(
                title: const Text('Imaging backend'),
                subtitle: Text(ref.watch(imageProcessorProvider).backendName),
              ),
              ListTile(
                title: const Text('Text detector'),
                subtitle: Text(ref.watch(textDetectorProvider).engineName),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final recognizer = ref.watch(handwritingRecognizerProvider);
                  return ListTile(
                    title: const Text('Handwriting recogniser'),
                    subtitle: Text(
                      recognizer.when(
                        data: (r) => r.engineName,
                        loading: () => 'Loading…',
                        error: (e, _) => 'Not available — no model bundled',
                      ),
                    ),
                  );
                },
              ),
            ],

            const _SectionHeader('About'),
            ListTile(
              title: const Text(AppConstants.appName),
              subtitle: const Text('Version 1.0.0'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Text(
                'This application performs document processing, handwriting '
                'recognition, contact extraction, storage, phonebook '
                'integration, and temporary-contact lifecycle management '
                'entirely on this device. It requires no internet connection '
                'and contacts no server.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
