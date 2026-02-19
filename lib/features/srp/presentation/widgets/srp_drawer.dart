import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../providers/auth_state_provider.dart';
import '../../../../providers/router_provider.dart';

/// Side drawer shown via the hamburger menu on the SRP Management screen.
///
/// Displays the admin's username and a logout button.
/// On logout the router automatically redirects to the home page.
class SrpDrawer extends ConsumerWidget {
  const SrpDrawer({super.key, required this.username, this.name});

  final String username;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: AppTheme.cream,
      child: SafeArea(
        child: Column(
          children: [
            // ── Admin profile header ────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.primaryRed, AppTheme.darkRed],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(40),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(100),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Full name (if available)
                  if (name != null && name!.isNotEmpty) ...[
                    Text(
                      name!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],

                  // Username
                  Text(
                    '@$username',
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Admin badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withAlpha(80)),
                    ),
                    child: const Text(
                      'ADMINISTRATOR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Navigation label ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ADMIN',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Colors.black.withAlpha(100),
                  ),
                ),
              ),
            ),

            // ── SRP Management tile ─────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.price_change, color: AppTheme.darkRed),
              title: const Text(
                'SRP Management',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              tileColor: AppTheme.darkRed.withAlpha(20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 2,
              ),
            ),

            const Spacer(),

            const Divider(indent: 20, endIndent: 20),

            // ── Logout button ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(width: double.infinity, child: _LogoutButton()),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authStateProvider.select((s) => s.isLoading));

    return ElevatedButton.icon(
      onPressed: isLoading
          ? null
          : () async {
              Navigator.of(context).pop(); // close drawer
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.splash);
            },
      icon: isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.logout),
      label: Text(isLoading ? 'Logging out…' : 'Logout'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryRed,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}
