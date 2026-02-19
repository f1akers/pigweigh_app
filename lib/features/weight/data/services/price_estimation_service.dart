import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/providers/connectivity_provider.dart';
import '../../../../core/utils/logger.dart';
import '../../../../features/srp/data/repositories/srp_repository.dart';
import '../models/price_estimation_model.dart';

part 'price_estimation_service.g.dart';

/// Service that calculates the estimated total price of a pig
/// based on its weight and the current SRP (Suggested Retail Price).
///
/// **Data source priority:**
/// 1. Server (via [SrpRepository.getActiveSrp]) if online.
/// 2. Drift cache (via [SrpRepository.getCachedActiveSrp]) if offline.
/// 3. Returns [PriceEstimationModel] with null price fields if SRP
///    has never been fetched (fresh install, never connected).
class PriceEstimationService {
  PriceEstimationService({
    required SrpRepository srpRepository,
    required bool Function() isOnline,
  }) : _srpRepository = srpRepository,
       _isOnline = isOnline;

  final SrpRepository _srpRepository;
  final bool Function() _isOnline;

  /// Calculate the estimated total price for a given weight.
  ///
  /// Returns a [PriceEstimationModel] that the result screen can display.
  ///
  /// **Frontend notes:**
  /// - If [PriceEstimationModel.srpPerKg] is `null`, SRP is unavailable.
  ///   Show only the weight and a message to connect to the internet.
  /// - If [PriceEstimationModel.isSrpFromCache] is `true`, the price
  ///   came from the offline cache — show a subtle "Offline price" badge.
  Future<PriceEstimationModel> calculatePrice(double weightKg) async {
    AppLogger.debug('Calculating price for ${weightKg}kg', tag: 'PRICE');

    // Try to get the active SRP (server-first, cache-fallback via repo).
    final result = await _srpRepository.getActiveSrp();

    return result.when(
      success: (srp) {
        if (srp == null) {
          // No active SRP exists at all.
          AppLogger.warn('No active SRP record found', tag: 'PRICE');
          return PriceEstimationModel(estimatedWeightKg: weightKg);
        }

        final totalPrice = weightKg * srp.price;

        AppLogger.info(
          'Price calculated: ${weightKg}kg × ₱${srp.price}/kg = ₱$totalPrice',
          tag: 'PRICE',
        );

        return PriceEstimationModel(
          estimatedWeightKg: weightKg,
          srpPerKg: srp.price,
          estimatedTotalPrice: totalPrice,
          isSrpFromCache: !_isOnline(),
          srpEffectiveDate: srp.startDate,
          srpReference: srp.reference,
        );
      },
      failure: (_) {
        // Server + cache both failed — return weight only.
        AppLogger.warn(
          'Could not retrieve SRP for price calculation',
          tag: 'PRICE',
        );
        return PriceEstimationModel(estimatedWeightKg: weightKg);
      },
    );
  }
}

/// Singleton provider for [PriceEstimationService].
@Riverpod(keepAlive: true)
PriceEstimationService priceEstimationService(Ref ref) {
  return PriceEstimationService(
    srpRepository: ref.watch(srpRepositoryProvider),
    isOnline: () => ref.read(connectivityProvider),
  );
}
