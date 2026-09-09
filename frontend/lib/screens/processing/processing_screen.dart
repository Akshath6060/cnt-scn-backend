import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exceptions.dart';
import '../../providers/review_provider.dart';
import '../../providers/scan_session_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/processing_progress.dart';
import '../review/review_screen.dart';

/// Runs the pipeline and shows genuine stage progress (§23).
class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    await ref.read(scanSessionProvider.notifier).process();
    if (!mounted) return;

    final session = ref.read(scanSessionProvider);
    if (session.phase == ScanPhase.complete && session.result != null) {
      _goToReview();
    }
  }

  void _goToReview() {
    if (_navigated) return;
    _navigated = true;

    final result = ref.read(scanSessionProvider).result!;
    ref.read(reviewProvider.notifier).loadFrom(result);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(scanSessionProvider);
    final error = session.error;

    return PopScope(
      // Leaving mid-run should stop the work, not orphan it.
      canPop: !session.isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(scanSessionProvider.notifier).cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reading the page'),
          automaticallyImplyLeading: !session.isBusy,
        ),
        body: Center(
          child: error != null
              ? AppErrorView(
                  error: error,
                  onRetry: error.isRecoverable ? _start : null,
                  onSecondary: () => Navigator.of(context).pop(),
                  secondaryLabel: 'Retake photo',
                )
              : ProcessingProgressView(
                  progress: session.progress,
                  usingMockRecognizer:
                      session.result?.usedMockRecognizer ?? false,
                ),
        ),
        bottomNavigationBar: session.isBusy
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: OutlinedButton(
                    onPressed: () {
                      ref.read(scanSessionProvider.notifier).cancel();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Convenience for callers that want to surface a pipeline error inline.
extension AppExceptionUi on AppException {
  bool get offersRetry => isRecoverable;
}
