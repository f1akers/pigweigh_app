import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/logger.dart';
import '../../data/models/weight_estimation_model.dart';
import '../../data/providers/weight_providers.dart';

/// Tab 1 — Capture top-view photo, run TFLite inference,
/// and trigger the final weight + price calculation.
///
/// [onCalculateSuccess] is called after a successful calculate(), so the
/// parent screen can switch to the Total Price tab.
class EstimateWeightTab extends ConsumerStatefulWidget {
  const EstimateWeightTab({super.key, required this.onCalculateSuccess});

  final VoidCallback onCalculateSuccess;

  @override
  ConsumerState<EstimateWeightTab> createState() => _EstimateWeightTabState();
}

class _EstimateWeightTabState extends ConsumerState<EstimateWeightTab> {
  final _picker = ImagePicker();

  // ── Image picking ──────────────────────────────────────────────────────────

  Future<void> _captureView(String viewType) async {
    final source = await _showSourceDialog();
    if (source == null) return;

    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return;

      await ref.read(weightFormProvider.notifier).processSideView(file.path);
    } catch (e) {
      AppLogger.error('Image pick failed', tag: 'WEIGHT_UI', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open camera. Please try again.'),
            backgroundColor: AppTheme.primaryRed,
          ),
        );
      }
    }
  }

  Future<ImageSource?> _showSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt,
                  color: AppTheme.primaryRed,
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: AppTheme.primaryRed,
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Calculate ──────────────────────────────────────────────────────────────

  Future<void> _calculate() async {
    final success = await ref.read(weightFormProvider.notifier).calculate();
    if (success && mounted) {
      widget.onCalculateSuccess();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(weightFormProvider);

    // Show error as snackbar.
    ref.listen<WeightFormState>(weightFormProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppTheme.primaryRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        ref.read(weightFormProvider.notifier).clearError();
      }
    });

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top View capture panel ──────────────────────────────────
              _CapturePanel(
                label: 'Capture: Top View',
                hint: 'Photo taken from above the pig',
                result: formState.sideViewResult,
                isProcessing: formState.isProcessing,
                onTap: () => _captureView('top'),
              ),

              const SizedBox(height: 36),

              // ── Calculate button ─────────────────────────────────────────
              _ThickBorderButton(
                label: 'Calculate',
                enabled: formState.canCalculate,
                onTap: formState.canCalculate ? _calculate : null,
              ),

              const SizedBox(height: 24),

              // ── Helper text ──────────────────────────────────────────────
              if (!formState.hasSideView)
                Text(
                  'Capture the top view to enable calculation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),

        // ── Loading overlay ──────────────────────────────────────────────────
        if (formState.isProcessing)
          Container(
            color: Colors.black.withAlpha(100),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 20),
                    // Round indicator
                    if (formState.processingRound > 0)
                      Text(
                        'Round ${formState.processingRound} of 2',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      formState.processingMessage ?? 'Analyzing image…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (formState.processingCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${formState.processingCount} samples processed',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Please be patient — this takes about 20 seconds.\n'
                      'Running statistical analysis for best accuracy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Capture Panel ─────────────────────────────────────────────────────────────

class _CapturePanel extends StatelessWidget {
  const _CapturePanel({
    required this.label,
    required this.hint,
    required this.result,
    required this.isProcessing,
    required this.onTap,
  });

  final String label;
  final String hint;
  final ViewEstimationResult? result;
  final bool isProcessing;
  final VoidCallback onTap;

  _ViewStatus get _status {
    if (result == null) return _ViewStatus.empty;
    return _ViewStatus.ok;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final bool isDone = status == _ViewStatus.ok;
    const bool needsRetake = false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Main tap target ─────────────────────────────────────────────────
        GestureDetector(
          onTap: isProcessing ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: needsRetake
                    ? Colors.orange.shade700
                    : AppTheme.primaryRed,
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Camera icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.cream,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isDone ? Icons.check_circle_outline : Icons.camera_alt,
                    color: isDone ? Colors.green.shade700 : AppTheme.primaryRed,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: Colors.black,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (result != null && isDone) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${result!.weightKg.toStringAsFixed(0)} kg  •  '
                          '${(result!.confidence * 100).toStringAsFixed(1)}% confidence',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else if (result == null) ...[
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Status icon
                _StatusIcon(status: status),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Status icon ───────────────────────────────────────────────────────────────

enum _ViewStatus { empty, ok }

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final _ViewStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _ViewStatus.ok:
        return Icon(Icons.check_circle, color: Colors.green.shade600, size: 28);
      case _ViewStatus.empty:
        return Icon(
          Icons.circle_outlined,
          color: Colors.grey.shade400,
          size: 28,
        );
    }
  }
}

// ── Thick-border button ───────────────────────────────────────────────────────

class _ThickBorderButton extends StatelessWidget {
  const _ThickBorderButton({
    required this.label,
    required this.enabled,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primaryRed, width: 3),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppTheme.primaryRed.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: Colors.black,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
