import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/auth/presentation/screens/home_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import 'auth_state_provider.dart';

part 'router_provider.g.dart';

/// Named route paths used across the app.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';

  // ── Public routes (no auth required) ──────────────────────────────────────
  static const String priceHistory = '/price-history';
  static const String weightEstimation = '/weight';

  // ── Admin routes (auth required) ──────────────────────────────────────────
  static const String adminSrp = '/admin/srp';
  static const String adminSrpEncode = '/admin/srp/encode';
}

/// Central GoRouter instance with auth-based redirects.
///
/// Usage in `main.dart`:
/// ```dart
/// MaterialApp.router(routerConfig: ref.watch(routerProvider))
/// ```
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refreshNotifier = _GoRouterRefreshStream(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    refreshListenable: refreshNotifier,

    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final isAuth = authState.isAuthenticated;
      final location = state.uri.path;

      // Still loading — stay on splash
      if (authState.isLoading) return null;

      // Admin routes require authentication.
      final isAdminRoute = location.startsWith('/admin');
      if (isAdminRoute && !isAuth) return AppRoutes.login;

      // Authenticated admin on login page → redirect to admin home.
      if (isAuth && location == AppRoutes.login) return AppRoutes.adminSrp;

      return null;
    },

    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const HomeScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const _PlaceholderScreen(title: 'Home'),
      ),
      GoRoute(
        path: AppRoutes.weightEstimation,
        builder: (_, __) =>
            const _PlaceholderScreen(title: 'Pig Weight Estimation'),
      ),
      GoRoute(
        path: AppRoutes.priceHistory,
        builder: (_, __) => const _PlaceholderScreen(title: 'Price History'),
      ),
      GoRoute(
        path: AppRoutes.adminSrp,
        builder: (_, __) => const _PlaceholderScreen(title: 'SRP Management'),
      ),
      GoRoute(
        path: AppRoutes.adminSrpEncode,
        builder: (_, __) => const _PlaceholderScreen(title: 'Encode SRP'),
      ),
    ],

    errorBuilder: (_, state) => _ErrorScreen(error: state.error),
  );
}

// ── helpers ──────────────────────────────────────────────────────────────────

class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(this._ref) {
    _ref.listen(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;
}

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(title)));
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({this.error});
  final Exception? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text('404 — ${error?.toString() ?? 'Not found'}')),
  );
}
