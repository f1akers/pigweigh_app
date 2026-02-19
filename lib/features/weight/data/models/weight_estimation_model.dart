import 'package:freezed_annotation/freezed_annotation.dart';

part 'weight_estimation_model.freezed.dart';
part 'weight_estimation_model.g.dart';

/// The result of running TFLite inference on a single image (one view).
///
/// Contains the predicted weight class, its confidence, and whether the
/// prediction is ambiguous (two or more classes with very similar confidence).
///
/// **Frontend notes:**
/// - If [isAmbiguous] is `true`, prompt the user to retake that view.
/// - [allPredictions] is sorted descending by confidence for debug/display.
@freezed
abstract class ViewEstimationResult with _$ViewEstimationResult {
  const factory ViewEstimationResult({
    /// The predicted weight in kilograms (from the top class label).
    required double weightKg,

    /// Confidence score of the top class (0.0 – 1.0).
    required double confidence,

    /// `true` if two or more classes have similar confidence,
    /// meaning the model is not sure. The user should retake this view.
    required bool isAmbiguous,

    /// File path to the source image used for this inference.
    required String imagePath,

    /// Which view this result came from: `'top'` or `'side'`.
    required String viewType,

    /// Top-N predicted classes sorted by confidence (descending).
    /// Useful for debugging or showing the user the runner-up predictions.
    @Default([]) List<PredictionClass> allPredictions,
  }) = _ViewEstimationResult;

  factory ViewEstimationResult.fromJson(Map<String, dynamic> json) =>
      _$ViewEstimationResultFromJson(json);
}

/// A single predicted class with its weight and confidence.
@freezed
abstract class PredictionClass with _$PredictionClass {
  const factory PredictionClass({
    required double weightKg,
    required double confidence,
    required String label,
  }) = _PredictionClass;

  factory PredictionClass.fromJson(Map<String, dynamic> json) =>
      _$PredictionClassFromJson(json);
}

/// Aggregated result after both top-view and side-view inferences.
///
/// **Frontend notes:**
/// - Show [estimatedWeightKg] as the final weight.
/// - [sourceView] indicates which photo produced the winning estimate.
/// - If either view's result has `isAmbiguous == true`, the UI should prompt
///   the user to retake **that specific view** before allowing "Calculate".
/// - If BOTH views are ambiguous, ask user to retake both.
@freezed
abstract class WeightEstimationModel with _$WeightEstimationModel {
  const factory WeightEstimationModel({
    /// Best estimated weight in kg (from the more confident view).
    required double estimatedWeightKg,

    /// Confidence of the winning prediction (0.0 – 1.0).
    required double confidence,

    /// Which view produced the winning estimate: `'top'` or `'side'`.
    required String sourceView,

    /// File path of the image that produced the winning estimate.
    required String imagePath,

    /// Full result for the top-view inference (null if not yet captured).
    ViewEstimationResult? topViewResult,

    /// Full result for the side-view inference (null if not yet captured).
    ViewEstimationResult? sideViewResult,
  }) = _WeightEstimationModel;

  factory WeightEstimationModel.fromJson(Map<String, dynamic> json) =>
      _$WeightEstimationModelFromJson(json);
}
