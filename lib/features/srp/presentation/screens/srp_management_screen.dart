import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/auth_state_provider.dart';
import '../../../../providers/router_provider.dart';
import '../widgets/manage_records_tab.dart';
import '../widgets/record_history_tab.dart';
import '../widgets/srp_drawer.dart';

/// Admin SRP Management screen.
///
/// Accessible only to authenticated admins. If the user is not
/// authenticated, they are automatically redirected to the home page.
///
/// Contains two tabs:
/// - **Record History** — paginated list of SRP records.
/// - **Manage Records** — form to encode a new SRP record.
class SrpManagementScreen extends ConsumerStatefulWidget {
  const SrpManagementScreen({super.key});

  @override
  ConsumerState<SrpManagementScreen> createState() =>
      _SrpManagementScreenState();
}

class _SrpManagementScreenState extends ConsumerState<SrpManagementScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    // Redirect to home whenever auth is lost.
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (next.status == AuthStatus.unauthenticated) {
        context.go(AppRoutes.splash);
      }
    });

    // While auth is resolving, show a loading spinner.
    if (authState.status == AuthStatus.initial || authState.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.cream,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Not authenticated — blank scaffold while redirect fires.
    if (!authState.isAuthenticated) {
      return const Scaffold(backgroundColor: AppTheme.cream);
    }

    return Scaffold(
      backgroundColor: AppTheme.cream,
      drawer: SrpDrawer(
        username: authState.username ?? 'admin',
        name: authState.name,
      ),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, size: 28),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: const Text(
          'DA - TALISAY CITY',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Tab bar (sits inside the red header area) ─────────────────────
          _SrpTabBar(
            selectedIndex: _selectedTab,
            onTabChanged: (index) => setState(() => _selectedTab = index),
          ),

          // ── Tab content ────────────────────────────────────────────────────
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: const [RecordHistoryTab(), ManageRecordsTab()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab bar ──────────────────────────────────────────────────────────────────

class _SrpTabBar extends StatelessWidget {
  const _SrpTabBar({required this.selectedIndex, required this.onTabChanged});

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
              label: 'Record History',
              isActive: selectedIndex == 0,
              onTap: () => onTabChanged(0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _TabButton(
              label: 'Manage Records',
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
    required this.label,
    required this.isActive,
    required this.onTap,
  });

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
        padding: const EdgeInsets.symmetric(vertical: 14),
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
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.black87,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
