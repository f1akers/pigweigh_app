import 'package:freezed_annotation/freezed_annotation.dart';

part 'price_estimation_model.freezed.dart';
part 'price_estimation_model.g.dart';

/// The final price estimation combining weight + market price.
///
/// **Frontend notes (Total Price screen):**
/// - Display [estimatedWeightKg] as "Estimated Weight".
/// - Display [srpPerKg] as "Market Price (₱/kg)".
/// - Display [estimatedTotalPrice] as "Total Value" (₱).
/// - If [isSrpFromCache] is `true`, show a subtle indicator:
///   "Offline price — last updated {srpEffectiveDate}".
/// - If [srpPerKg] is `null`, SRP was never fetched — show:
///   "Connect to the internet to load current market prices."
///   and only display the estimated weight without price.
/// - "Done" button navigates back to the home page.
@freezed
abstract class PriceEstimationModel with _$PriceEstimationModel {
  const factory PriceEstimationModel({
    /// Estimated weight of the pig in kilograms.
    required double estimatedWeightKg,

    /// Current SRP per kilogram (₱/kg). Null if SRP is unavailable.
    double? srpPerKg,

    /// Estimated total price: [estimatedWeightKg] × [srpPerKg].
    /// Null if SRP is unavailable.
    double? estimatedTotalPrice,

    /// `true` if the SRP was read from the offline Drift cache
    /// rather than fetched fresh from the server.
    @Default(false) bool isSrpFromCache,

    /// The effective start date of the SRP record used for calculation.
    DateTime? srpEffectiveDate,

    /// Reference string of the SRP record (e.g., "DA-MO-2026-001").
    String? srpReference,
  }) = _PriceEstimationModel;

  factory PriceEstimationModel.fromJson(Map<String, dynamic> json) =>
      _$PriceEstimationModelFromJson(json);
}
