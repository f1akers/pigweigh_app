import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/utils/logger.dart';
import '../features/auth/data/repositories/auth_repository.dart';

part 'auth_state_provider.g.dart';

/// Authentication status enum.
enum AuthStatus { initial, authenticated, unauthenticated }

/// Immutable auth state with admin profile fields.
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.userId,
    this.username,
    this.name,
    this.isLoading = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? userId;
  final String? username;
  final String? name;
  final bool isLoading;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? username,
    String? name,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      name: name ?? this.name,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() =>
      'AuthState(status: $status, userId: $userId, username: $username, isLoading: $isLoading)';
}

/// App-wide auth state notifier backed by [AuthRepository].
///
/// On build, checks for an existing session:
/// - If a token exists, verifies with the server (`GET /auth/me`).
/// - Falls back to the Hive-cached admin profile when offline.
/// - If no token exists, sets status to `unauthenticated`.
///
/// ```dart
/// final auth = ref.watch(authStateProvider);
/// if (auth.isAuthenticated) { /* … */ }
/// ```
@Riverpod(keepAlive: true)
class AuthStateNotifier extends _$AuthStateNotifier {
  late AuthRepository _authRepo;

  @override
  AuthState build() {
    _authRepo = ref.watch(authRepositoryProvider);
    Future.microtask(() => _checkAuthStatus());
    return const AuthState(isLoading: true);
  }

  /// Initial auth check on app start.
  Future<void> _checkAuthStatus() async {
    try {
      final isAuth = await _authRepo.isAuthenticated();

      if (!isAuth) {
        state = const AuthState(status: AuthStatus.unauthenticated);
        return;
      }

      // Token exists — try to verify with server (falls back to cache).
      final result = await _authRepo.verifySession();
      result.when(
        success: (admin) {
          state = AuthState(
            status: AuthStatus.authenticated,
            userId: admin.id,
            username: admin.username,
            name: admin.name,
          );
          AppLogger.info('Session restored for ${admin.username}', tag: 'AUTH');
        },
        failure: (_) {
          // No cached admin and server unreachable — force re-login.
          state = const AuthState(status: AuthStatus.unauthenticated);
        },
      );
    } catch (e) {
      AppLogger.error('Auth check failed', tag: 'AUTH', error: e);
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Log in with username and password.
  Future<void> login({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    final result = await _authRepo.login(
      username: username,
      password: password,
    );

    result.when(
      success: (admin) {
        state = AuthState(
          status: AuthStatus.authenticated,
          userId: admin.id,
          username: admin.username,
          name: admin.name,
        );
      },
      failure: (error) {
        state = state.copyWith(isLoading: false, errorMessage: error.message);
      },
    );
  }

  /// Clear credentials and return to unauthenticated state.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await _authRepo.logout();
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Called by API interceptors when a 401 is received.
  void onAuthFailure() => logout();

  /// Clear the current error message.
  void clearError() => state = state.copyWith(errorMessage: null);
}
