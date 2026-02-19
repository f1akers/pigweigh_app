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
/// - Show `topViewResult` / `sideViewResult` as preview cards when available.
/// - If a result has `isAmbiguous == true`, show a warning badge on that
///   card and disable the "Calculate" button.
/// - The "Calculate" button is enabled only when both views have non-null,
///   non-ambiguous results.
/// - On error, display [errorMessage] as a snackbar/toast.
/// - [isProcessing] — show a loading overlay during inference.
class WeightFormState {
  const WeightFormState({
    this.topViewResult,
    this.sideViewResult,
    this.isProcessing = false,
    this.errorMessage,
  });

  /// Result of the top-view inference (null if not yet captured).
  final ViewEstimationResult? topViewResult;

  /// Result of the side-view inference (null if not yet captured).
  final ViewEstimationResult? sideViewResult;

  /// `true` while an inference is running.
  final bool isProcessing;

  /// Error message to display (e.g., image decode failure).
  final String? errorMessage;

  /// Whether the top view has been captured and processed.
  bool get hasTopView => topViewResult != null;

  /// Whether the side view has been captured and processed.
  bool get hasSideView => sideViewResult != null;

  /// Whether the "Calculate" button should be enabled:
  /// both views captured and not currently processing.
  bool get canCalculate => hasTopView && hasSideView && !isProcessing;

  WeightFormState copyWith({
    ViewEstimationResult? topViewResult,
    ViewEstimationResult? sideViewResult,
    bool? isProcessing,
    String? errorMessage,
    bool clearTopView = false,
    bool clearSideView = false,
    bool clearError = false,
  }) {
    return WeightFormState(
      topViewResult: clearTopView
          ? null
          : (topViewResult ?? this.topViewResult),
      sideViewResult: clearSideView
          ? null
          : (sideViewResult ?? this.sideViewResult),
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages the two-photo capture and inference flow for weight estimation.
///
/// **Frontend usage:**
/// ```dart
/// // Watch state
/// final formState = ref.watch(weightFormProvider);
///
/// // User captures top view (UI provides the image path)
/// await ref.read(weightFormProvider.notifier).processTopView('/path/to/image.jpg');
///
/// // User captures side view
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

  /// Process a captured top-view image through the TFLite model.
  ///
  /// [imagePath] — absolute path to the image file from camera/gallery.
  Future<void> processTopView(String imagePath) async {
    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final service = ref.read(weightEstimationServiceProvider);
      final result = await service.estimateFromImage(
        imagePath: imagePath,
        viewType: 'top',
      );
      state = state.copyWith(topViewResult: result, isProcessing: false);
    } catch (e) {
      AppLogger.error('Top view inference failed', tag: 'WEIGHT', error: e);
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to process top view image. Please try again.',
      );
    }
  }

  /// Process a captured side-view image through the TFLite model.
  ///
  /// [imagePath] — absolute path to the image file from camera/gallery.
  Future<void> processSideView(String imagePath) async {
    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final service = ref.read(weightEstimationServiceProvider);
      final result = await service.estimateFromImage(
        imagePath: imagePath,
        viewType: 'side',
      );
      state = state.copyWith(sideViewResult: result, isProcessing: false);
    } catch (e) {
      AppLogger.error('Side view inference failed', tag: 'WEIGHT', error: e);
      state = state.copyWith(
        isProcessing: false,
        errorMessage: 'Failed to process side view image. Please try again.',
      );
    }
  }

  /// Retake the top-view photo — clears the current top-view result.
  ///
  /// **Frontend notes:**
  /// Call this before opening the camera/gallery for a new top-view capture.
  void retakeTopView() {
    state = state.copyWith(clearTopView: true, clearError: true);
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
  /// - Both views must be captured and non-ambiguous (check `state.canCalculate`).
  ///
  /// **Frontend notes:**
  /// - After this completes, read [weightResultProvider] and navigate
  ///   to the result screen.
  /// - Returns `true` on success, `false` on failure.
  Future<bool> calculate() async {
    if (!state.canCalculate) {
      state = state.copyWith(
        errorMessage: 'Please capture both views with clear results first.',
      );
      return false;
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    try {
      final service = ref.read(weightEstimationServiceProvider);

      // Pick the best estimate from both views.
      final estimation = service.calculateBestEstimate(
        topViewResult: state.topViewResult!,
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
