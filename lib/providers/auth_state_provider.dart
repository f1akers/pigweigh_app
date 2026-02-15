import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/utils/logger.dart';
import '../services/api/api_client.dart';
import '../services/storage/secure_storage_service.dart';

part 'auth_state_provider.g.dart';

/// Authentication status enum.
enum AuthStatus { initial, authenticated, unauthenticated }

/// Immutable auth state.
class AuthState {
  const AuthState({
    this.status = AuthStatus.initial,
    this.userId,
    this.email,
    this.isLoading = false,
    this.errorMessage,
  });

  final AuthStatus status;
  final String? userId;
  final String? email;
  final bool isLoading;
  final String? errorMessage;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? email,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() =>
      'AuthState(status: $status, userId: $userId, isLoading: $isLoading)';
}

/// App-wide auth state notifier.
///
/// ```dart
/// final auth = ref.watch(authStateProvider);
/// if (auth.isAuthenticated) { /* … */ }
/// ```
@Riverpod(keepAlive: true)
class AuthStateNotifier extends _$AuthStateNotifier {
  late SecureStorageService _storage;

  @override
  AuthState build() {
    _storage = ref.watch(secureStorageServiceProvider);
    Future.microtask(() => _checkAuthStatus());
    return const AuthState(isLoading: true);
  }

  Future<void> _checkAuthStatus() async {
    try {
      final isAuth = await _storage.isAuthenticated();

      if (isAuth) {
        if (await _storage.isTokenExpired()) {
          final apiClient = ref.read(apiClientProvider);
          final refreshed = await apiClient.tryRefreshToken();
          if (!refreshed) {
            state = const AuthState(status: AuthStatus.unauthenticated);
            return;
          }
        }

        final userId = await _storage.getUserId();
        final email = await _storage.getUserEmail();
        state = AuthState(
          status: AuthStatus.authenticated,
          userId: userId,
          email: email,
        );
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      AppLogger.error('Auth check failed', tag: 'AUTH', error: e);
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Called after a successful login.
  Future<void> setAuthenticated({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String email,
    DateTime? tokenExpiry,
  }) async {
    await _storage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiry: tokenExpiry,
    );
    await _storage.saveUserId(userId);
    await _storage.saveUserEmail(email);

    state = AuthState(
      status: AuthStatus.authenticated,
      userId: userId,
      email: email,
    );
  }

  /// Clear credentials and return to unauthenticated state.
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await _storage.clearTokens();
      await _storage.delete(key: 'user_id');
      await _storage.delete(key: 'user_email');
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void onAuthFailure() => logout();
  void clearError() => state = state.copyWith(errorMessage: null);
}
