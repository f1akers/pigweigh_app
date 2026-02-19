import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/router_provider.dart';
import '../../data/providers/weight_providers.dart';
import '../widgets/estimate_weight_tab.dart';
import '../widgets/total_price_tab.dart';

/// Main screen for pig weight estimation.
///
/// Contains two tabs:
/// - **① Estimate Weight** — capture top-view and side-view photos,
///   run TFLite inference, and trigger the weight calculation.
/// - **② Total Price** — display the estimated weight and computed
///   market value based on the current SRP.
///
/// The screen auto-advances to tab 2 after a successful [WeightForm.calculate].
/// The "Done" button on tab 2 resets the form and navigates back to home.
class WeightEstimationScreen extends ConsumerStatefulWidget {
  const WeightEstimationScreen({super.key});

  @override
  ConsumerState<WeightEstimationScreen> createState() =>
      _WeightEstimationScreenState();
}

class _WeightEstimationScreenState
    extends ConsumerState<WeightEstimationScreen> {
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    // Reset the form whenever we enter this screen fresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weightFormProvider.notifier).reset();
      ref.read(weightResultProvider.notifier).reset();
    });
  }

  void _onCalculateSuccess() {
    setState(() => _selectedTab = 1);
  }

  void _onDone() {
    ref.read(weightFormProvider.notifier).reset();
    ref.read(weightResultProvider.notifier).reset();
    context.go(AppRoutes.splash);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      appBar: AppBar(
        backgroundColor: AppTheme.darkRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 26),
          onPressed: () {
            ref.read(weightFormProvider.notifier).reset();
            ref.read(weightResultProvider.notifier).reset();
            context.go(AppRoutes.splash);
          },
        ),
        title: const Text(
          'USERS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Tab bar ────────────────────────────────────────────────────────
          _WeightTabBar(
            selectedIndex: _selectedTab,
            onTabChanged: (index) {
              // Only allow going to tab 2 if we have a result.
              if (index == 1) {
                final result = ref.read(weightResultProvider);
                if (!result.hasResult) return;
              }
              setState(() => _selectedTab = index);
            },
          ),

          // ── Tab content ────────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                EstimateWeightTab(onCalculateSuccess: _onCalculateSuccess),
                TotalPriceTab(onDone: _onDone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar ───────────────────────────────────────────────────────────────────

class _WeightTabBar extends StatelessWidget {
  const _WeightTabBar({
    required this.selectedIndex,
    required this.onTabChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryRed,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              index: 1,
              label: 'Estimate Weight',
              isActive: selectedIndex == 0,
              onTap: () => onTabChanged(0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TabButton(
              index: 2,
              label: 'Total Price',
              isActive: selectedIndex == 1,
              onTap: () => onTabChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.index,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final int index;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : const Color(0xFFBB8080),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? AppTheme.primaryRed
                : AppTheme.primaryRed.withAlpha(180),
            width: 3,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withAlpha(30),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Numbered badge
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isActive ? AppTheme.primaryRed : Colors.black54,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.black87,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
