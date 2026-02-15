import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_state_provider.dart';

part 'router_provider.g.dart';

/// Named route paths used across the app.
class AppRoutes {
  AppRoutes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  // Add more routes as features are created
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

      const publicRoutes = [AppRoutes.login];
      final isPublicRoute = publicRoutes.contains(location);

      if (!isAuth && !isPublicRoute) return AppRoutes.login;
      if (isAuth && isPublicRoute) return AppRoutes.home;

      return null;
    },

    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const _PlaceholderScreen(title: 'Loading…'),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const _PlaceholderScreen(title: 'Login'),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const _PlaceholderScreen(title: 'Home'),
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
