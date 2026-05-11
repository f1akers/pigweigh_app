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
/// - Show [topViewResult] and [sideViewResult] as preview cards when available.
/// - The "Calculate" button is enabled when at least one view is captured and
///   not currently processing.
/// - On calculate, the view with the highest confidence is used; ties favour
///   the top view.
/// - On error, display [errorMessage] as a snackbar/toast.
/// - [isProcessing] — show a loading overlay during inference.
/// - [processingMessage] / [processingRound] / [processingCount] — shown in
///   the overlay to keep the user informed during the ~20 s two-round TTA.
class WeightFormState {
  const WeightFormState({
    this.topViewResult,
    this.sideViewResult,
    this.isProcessing = false,
    this.processingMessage,
    this.processingRound = 0,
    this.processingCount = 0,
    this.errorMessage,
  });

  /// Result of the top-view inference (null if not yet captured).
  final ViewEstimationResult? topViewResult;

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

  /// Whether the top view has been captured and processed.
  bool get hasTopView => topViewResult != null;

  /// Whether the side view has been captured and processed.
  bool get hasSideView => sideViewResult != null;

  /// Whether the "Calculate" button should be enabled:
  /// at least one view captured and not currently processing.
  bool get canCalculate => (hasTopView || hasSideView) && !isProcessing;

  WeightFormState copyWith({
    ViewEstimationResult? topViewResult,
    ViewEstimationResult? sideViewResult,
    bool? isProcessing,
    String? processingMessage,
    int? processingRound,
    int? processingCount,
    String? errorMessage,
    bool clearTopView = false,
    bool clearSideView = false,
    bool clearError = false,
    bool clearProcessingMessage = false,
  }) {
    return WeightFormState(
      topViewResult: clearTopView
          ? null
          : (topViewResult ?? this.topViewResult),
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

/// Manages the top-view and side-view capture + inference flow for weight estimation.
///
/// **Frontend usage:**
/// ```dart
/// // Watch state
/// final formState = ref.watch(weightFormProvider);
///
/// // User captures top view (UI provides the image path)
/// await ref.read(weightFormProvider.notifier).processTopView('/path/to/image.jpg');
///
/// // User captures side view (optional, for better accuracy)
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

  Future<void> _processView(String imagePath, String viewType) async {
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
        viewType: viewType,
        onProgress: (round, count, message) {
          state = state.copyWith(
            processingRound: round,
            processingCount: count,
            processingMessage: message,
          );
        },
      );
      state = state.copyWith(
        topViewResult: viewType == 'top' ? result : null,
        sideViewResult: viewType == 'side' ? result : null,
        isProcessing: false,
        clearProcessingMessage: true,
        processingRound: 0,
        processingCount: 0,
      );
    } catch (e) {
      AppLogger.error(
        '$viewType view inference failed',
        tag: 'WEIGHT',
        error: e,
      );
      state = state.copyWith(
        isProcessing: false,
        clearProcessingMessage: true,
        processingRound: 0,
        processingCount: 0,
        errorMessage:
            'Failed to process $viewType view image. Please try again.',
      );
    }
  }

  /// Process a captured top-view image through the two-round TTA pipeline.
  ///
  /// [imagePath] — absolute path to the image file from camera/gallery.
  Future<void> processTopView(String imagePath) =>
      _processView(imagePath, 'top');

  /// Process a captured side-view image through the two-round TTA pipeline.
  ///
  /// [imagePath] — absolute path to the image file from camera/gallery.
  Future<void> processSideView(String imagePath) =>
      _processView(imagePath, 'side');

  /// Retake the top-view photo — clears the current top-view result.
  void retakeTopView() {
    state = state.copyWith(clearTopView: true, clearError: true);
  }

  /// Retake the side-view photo — clears the current side-view result.
  void retakeSideView() {
    state = state.copyWith(clearSideView: true, clearError: true);
  }

  /// Calculate the final weight estimate and price, then set the result.
  ///
  /// Selects the view with the highest confidence. If confidences are equal,
  /// the top view is preferred.
  ///
  /// **Preconditions:**
  /// - At least one view must be captured (check `state.canCalculate`).
  ///
  /// **Frontend notes:**
  /// - After this completes, read [weightResultProvider] and navigate
  ///   to the result screen.
  /// - Returns `true` on success, `false` on failure.
  Future<bool> calculate() async {
    if (!state.canCalculate) {
      state = state.copyWith(
        errorMessage: 'Please capture at least one view first.',
      );
      return false;
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final service = ref.read(weightEstimationServiceProvider);

      // Pick the view with higher confidence; ties favour the top view.
      final estimation = service.calculateEstimate(
        topViewResult: state.topViewResult,
        sideViewResult: state.sideViewResult,
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
