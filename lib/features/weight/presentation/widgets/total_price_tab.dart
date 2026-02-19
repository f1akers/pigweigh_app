import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/router_provider.dart';
import '../../data/providers/weight_providers.dart';

/// Tab 2 — Display the estimated weight and market value after inference.
///
/// Shows:
/// - Estimated weight (kg) in a thick-bordered display box.
/// - "See Price History" shortcut button.
/// - Price breakdown card: Market Price (₱/kg) + Total Value.
/// - Offline/unavailable SRP indicators.
/// - "Done" button to reset and return home.
class TotalPriceTab extends ConsumerWidget {
  const TotalPriceTab({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultState = ref.watch(weightResultProvider);

    // If the user somehow lands here without a result, show a placeholder.
    if (!resultState.hasResult) {
      return const _NoResultPlaceholder();
    }

    final estimation = resultState.estimation!;
    final price = resultState.priceEstimation;

    final srpPerKg = price?.srpPerKg;
    final totalValue = price?.estimatedTotalPrice;
    final isCached = price?.isSrpFromCache ?? false;
    final srpDate = price?.srpEffectiveDate;
    final srpRef = price?.srpReference;

    final weightDisplay = estimation.estimatedWeightKg.toStringAsFixed(0);

    final currencyFmt = NumberFormat.currency(
      locale: 'fil_PH',
      symbol: '₱',
      decimalDigits: 2,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Estimated weight label ─────────────────────────────────────────
          const Text(
            'Estimated Weight (kg):',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),

          const SizedBox(height: 10),

          // ── Thick-border weight display ────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryRed, width: 3.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryRed.withAlpha(50),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              weightDisplay,
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                height: 1.1,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── See Price History button ───────────────────────────────────────
          ElevatedButton(
            onPressed: () => context.push(AppRoutes.priceHistory),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryRed,
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'See Price History',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Price breakdown card ───────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // SRP unavailable message
                if (srpPerKg == null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Icon(
                          Icons.wifi_off_rounded,
                          color: Colors.grey.shade500,
                          size: 32,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Connect to the internet to load current market prices.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Offline badge
                  if (isCached)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        border: Border(
                          bottom: BorderSide(color: Colors.amber.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 15,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              srpDate != null
                                  ? 'Offline price — last updated ${_formatDate(srpDate)}'
                                  : 'Offline price',
                              style: TextStyle(
                                color: Colors.amber.shade800,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Reference
                  if (srpRef != null)
                    _InfoRow(
                      label: 'SRP Reference',
                      value: srpRef,
                      isFirst: !isCached,
                      isLast: false,
                    ),

                  // Market price per kg
                  _InfoRow(
                    label: 'Market Price (₱/kg)',
                    value: currencyFmt.format(srpPerKg),
                    isFirst: srpRef == null && !isCached,
                    isLast: false,
                  ),

                  // Total value
                  _InfoRow(
                    label: 'Total Value',
                    value: totalValue != null
                        ? currencyFmt.format(totalValue)
                        : '—',
                    isFirst: false,
                    isLast: true,
                    valueStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.darkRed,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 36),

          // ── Done button ────────────────────────────────────────────────────
          GestureDetector(
            onTap: onDone,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryRed, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryRed.withAlpha(55),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  color: Colors.black,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return DateFormat('MMM d, yyyy').format(local);
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.isFirst,
    required this.isLast,
    this.valueStyle,
  });

  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final effectiveValueStyle =
        valueStyle ??
        const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: !isLast
            ? Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1))
            : null,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(12) : Radius.zero,
          bottom: isLast ? const Radius.circular(12) : Radius.zero,
        ),
      ),
      child: Row(
        children: [
          // Label chip
          Flexible(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Value
          Flexible(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade200),
              ),
              alignment: Alignment.centerLeft,
              child: Text(value, style: effectiveValueStyle),
            ),
          ),
        ],
      ),
    );
  }
}

// ── No-result placeholder ─────────────────────────────────────────────────────

class _NoResultPlaceholder extends StatelessWidget {
  const _NoResultPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.scale_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No estimate yet.\nCapture both views and tap Calculate.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
