import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/utils/logger.dart';
import '../models/price_estimation_model.dart';
import '../models/weight_estimation_model.dart';
import '../services/price_estimation_service.dart';
import '../services/weight_estimation_service.dart';

part 'weight_providers.g.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Weight Form State — manages the two-phase capture + inference flow
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state for the weight estimation form.
///
/// **Frontend expectations:**
/// - Watch this provider for the current form state.
/// - Show `sideViewResult` as a preview card when available.
/// - If the result has `isAmbiguous == true`, show a warning badge on the
///   card and disable the "Calculate" button.
/// - The "Calculate" button is enabled only when the side view has a non-null,
///   non-ambiguous result.
/// - On error, display [errorMessage] as a snackbar/toast.
/// - [isProcessing] — show a loading overlay during inference.
/// - [processingMessage] / [processingRound] / [processingCount] — shown in
///   the overlay to keep the user informed during the ~20 s two-round TTA.
class WeightFormState {
  const WeightFormState({
    this.sideViewResult,
    this.isProcessing = false,
    this.processingMessage,
    this.processingRound = 0,
    this.processingCount = 0,
    this.errorMessage,
  });

  /// Result of the side-view inference (null if not yet captured).
  final ViewEstimationResult? sideViewResult;

  /// `true` while an inference is running.
  final bool isProcessing;

  /// Human-readable status text shown in the overlay.
  final String? processingMessage;

  /// Current TTA round (1 = range detection, 2 = fine-grain detection).
  final int processingRound;

  /// Number of inferences completed in the current round.
  final int processingCount;

  /// Error message to display (e.g., image decode failure).
  final String? errorMessage;

  /// Whether the side view has been captured and processed.
  bool get hasSideView => sideViewResult != null;

  /// Whether the "Calculate" button should be enabled:
  /// side view captured and not currently processing.
  bool get canCalculate => hasSideView && !isProcessing;

  WeightFormState copyWith({
    ViewEstimationResult? sideViewResult,
    bool? isProcessing,
    String? processingMessage,
    int? processingRound,
    int? processingCount,
    String? errorMessage,
    bool clearSideView = false,
    bool clearError = false,
    bool clearProcessingMessage = false,
  }) {
    return WeightFormState(
      sideViewResult: clearSideView
          ? null
          : (sideViewResult ?? this.sideViewResult),
      isProcessing: isProcessing ?? this.isProcessing,
      processingMessage: clearProcessingMessage
          ? null
          : (processingMessage ?? this.processingMessage),
      processingRound: processingRound ?? this.processingRound,
      processingCount: processingCount ?? this.processingCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages the side-view capture and inference flow for weight estimation.
///
/// **Frontend usage:**
/// ```dart
/// // Watch state
/// final formState = ref.watch(weightFormProvider);
///
/// // User captures side view (UI provides the image path)
/// await ref.read(weightFormProvider.notifier).processSideView('/path/to/image.jpg');
///
/// // User taps "Calculate"
/// final result = await ref.read(weightFormProvider.notifier).calculate();
/// // result is set on weightResultProvider, navigate to result screen
/// ```
@riverpod
class WeightForm extends _$WeightForm {
  @override
  WeightFormState build() {
    // Ensure the estimation service is initialized.
    _ensureInitialized();
    return const WeightFormState();
  }

  Future<void> _ensureInitialized() async {
    final service = ref.read(weightEstimationServiceProvider);
    if (!service.isInitialized) {
      try {
        await service.initialize();
      } catch (e) {
        AppLogger.error(
          'Failed to initialize weight estimation',
          tag: 'WEIGHT',
          error: e,
        );
        state = state.copyWith(
          errorMessage: 'Failed to load the weight estimation model.',
        );
      }
    }
  }

  /// Process a captured side-view image through the two-round TTA pipeline.
  ///
  /// [imagePath] — absolute path to the image file from camera/gallery.
  ///
  /// The two rounds (~10 s each) provide a statistically robust estimate:
  ///   Round 1 — narrow to a 10 kg range.
  ///   Round 2 — pinpoint the exact weight within that range.
  Future<void> processSideView(String imagePath) async {
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      processingRound: 1,
      processingCount: 0,
      processingMessage: 'Preparing image...',
    );

    try {
      final service = ref.read(weightEstimationServiceProvider);
      final result = await service.estimateFromImage(
        imagePath: imagePath,
        viewType: 'side',
        onProgress: (round, count, message) {
          state = state.copyWith(
            processingRound: round,
            processingCount: count,
            processingMessage: message,
          );
        },
      );
      state = state.copyWith(
        sideViewResult: result,
        isProcessing: false,
        clearProcessingMessage: true,
        processingRound: 0,
        processingCount: 0,
      );
    } catch (e) {
      AppLogger.error('Side view inference failed', tag: 'WEIGHT', error: e);
      state = state.copyWith(
        isProcessing: false,
        clearProcessingMessage: true,
        processingRound: 0,
        processingCount: 0,
        errorMessage: 'Failed to process side view image. Please try again.',
      );
    }
  }

  /// Retake the side-view photo — clears the current side-view result.
  ///
  /// **Frontend notes:**
  /// Call this before opening the camera/gallery for a new side-view capture.
  void retakeSideView() {
    state = state.copyWith(clearSideView: true, clearError: true);
  }

  /// Calculate the final weight estimate and price, then set the result.
  ///
  /// **Preconditions:**
  /// - Side view must be captured and non-ambiguous (check `state.canCalculate`).
  ///
  /// **Frontend notes:**
  /// - After this completes, read [weightResultProvider] and navigate
  ///   to the result screen.
  /// - Returns `true` on success, `false` on failure.
  Future<bool> calculate() async {
    if (!state.canCalculate) {
      state = state.copyWith(
        errorMessage: 'Please capture the side view with a clear result first.',
      );
      return false;
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final service = ref.read(weightEstimationServiceProvider);

      // Pick the estimate from the side view.
      final estimation = service.calculateEstimate(
        sideViewResult: state.sideViewResult!,
      );

      // Calculate the price.
      final priceService = ref.read(priceEstimationServiceProvider);
      final priceEstimation = await priceService.calculatePrice(
        estimation.estimatedWeightKg,
      );

      // Set the result for the result screen.
      ref
          .read(weightResultProvider.notifier)
          .setResult(estimation: estimation, priceEstimation: priceEstimation);

      state = state.copyWith(isProcessing: false);
      return true;
    } catch (e) {
      AppLogger.error('Weight calculation failed', tag: 'WEIGHT', error: e);
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to calculate weight. Please try again.',
      );
      return false;
    }
  }

  /// Reset the entire form (used when navigating away or "Estimate Again").
  void reset() {
    state = const WeightFormState();
  }

  /// Clear the current error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Weight Result State — holds the final result for the result screen
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state for the weight result screen.
///
/// **Frontend expectations:**
/// - Watch this provider on the result screen.
/// - If `null`, the user navigated directly without estimating → redirect back.
/// - Display [estimation] for the weight card.
/// - Display [priceEstimation] for the price breakdown card.
/// - "Done" button calls `reset()` and navigates to home.
class WeightResultState {
  const WeightResultState({this.estimation, this.priceEstimation});

  final WeightEstimationModel? estimation;
  final PriceEstimationModel? priceEstimation;

  bool get hasResult => estimation != null;
}

/// Holds the latest estimation result for the result screen.
///
/// **Frontend usage:**
/// ```dart
/// final result = ref.watch(weightResultProvider);
/// if (!result.hasResult) {
///   // Redirect back — no estimation data.
///   return;
/// }
/// // Display result.estimation and result.priceEstimation
/// ```
@riverpod
class WeightResult extends _$WeightResult {
  @override
  WeightResultState build() => const WeightResultState();

  /// Set the result (called by [WeightForm.calculate]).
  void setResult({
    required WeightEstimationModel estimation,
    required PriceEstimationModel priceEstimation,
  }) {
    state = WeightResultState(
      estimation: estimation,
      priceEstimation: priceEstimation,
    );
  }

  /// Clear the result (called when user taps "Done" or "Estimate Again").
  void reset() {
    state = const WeightResultState();
  }
}
