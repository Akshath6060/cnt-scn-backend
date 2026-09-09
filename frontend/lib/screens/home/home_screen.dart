import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/temporary_contacts_provider.dart';
import '../../widgets/offline_badge.dart';
import '../camera/camera_screen.dart';
import '../saved_contacts/saved_contacts_screen.dart';
import '../settings/settings_screen.dart';
import '../temporary_contacts/temporary_contacts_screen.dart';

/// Landing screen (§3, §34).
///
/// Three primary actions, large targets, no clutter.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final temporary = ref.watch(temporaryContactsProvider);
    final activeCount = temporary.active.length;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Turn a handwritten contact sheet into phone contacts.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const OfflineBadge(),
                  ],
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList.list(
                children: [
                  _PrimaryAction(
                    icon: Icons.document_scanner_outlined,
                    title: 'Scan Contact Sheet',
                    subtitle: 'Photograph a page of names and numbers',
                    isPrimary: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CameraScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryAction(
                    icon: Icons.timer_outlined,
                    title: 'Temporary Contacts',
                    subtitle: activeCount == 0
                        ? 'Contacts that expire automatically'
                        : '$activeCount active',
                    badgeCount: activeCount,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TemporaryContactsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryAction(
                    icon: Icons.history,
                    title: 'Saved Contacts',
                    subtitle: 'Everything this app has saved',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedContactsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryAction(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Privacy, images and about',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isPrimary = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isPrimary;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isPrimary ? scheme.primaryContainer : null;
    final foreground =
        isPrimary ? scheme.onPrimaryContainer : scheme.onSurface;

    return Card(
      color: background,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: isPrimary ? 22 : 16,
          ),
          child: Row(
            children: [
              Icon(icon, size: isPrimary ? 32 : 26, color: foreground),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isPrimary ? 19 : 17,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (badgeCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: foreground.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
