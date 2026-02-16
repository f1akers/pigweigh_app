import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/utils/app_error.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/result.dart';
import '../../../../services/api/api_client.dart';
import '../../../../services/storage/secure_storage_service.dart';
import '../models/admin_model.dart';
import '../models/login_response_model.dart';

part 'auth_repository.g.dart';

/// Data-access layer for admin authentication.
///
/// Handles:
/// - Login via `POST /api/auth/login`
/// - Session verification via `GET /api/auth/me`
/// - JWT storage in [SecureStorageService]
/// - Admin profile caching in Hive for offline access
class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required SecureStorageService secureStorage,
  }) : _apiClient = apiClient,
       _secureStorage = secureStorage;

  final ApiClient _apiClient;
  final SecureStorageService _secureStorage;

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Authenticate with the server.
  ///
  /// On success:
  /// 1. Stores JWT in secure storage.
  /// 2. Caches admin profile in Hive.
  ///
  /// Returns the [AdminModel] on success.
  Future<Result<AdminModel, AppError>> login({
    required String username,
    required String password,
  }) async {
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiConstants.login,
      data: {'username': username, 'password': password},
    );

    return result.when(
      success: (data) async {
        final response = LoginResponseModel.fromJson(data);

        // 1. Store JWT securely
        await _secureStorage.saveTokens(
          accessToken: response.token,
          refreshToken: '', // Server doesn't issue refresh tokens yet
          expiry: null, // Token expiry managed server-side (7d default)
        );

        // 2. Cache admin profile in Hive
        await _cacheAdmin(response.admin);

        AppLogger.info(
          'Login successful for ${response.admin.username}',
          tag: 'AUTH',
        );
        return Result.success(response.admin);
      },
      failure: (error) {
        AppLogger.warn('Login failed: ${error.message}', tag: 'AUTH');
        return Result.failure(error);
      },
    );
  }

  // ── Session Verification ──────────────────────────────────────────────────

  /// Check if a valid session exists (token present).
  Future<bool> isAuthenticated() => _secureStorage.isAuthenticated();

  /// Verify the current token with the server (`GET /auth/me`).
  ///
  /// Falls back to the cached admin profile if the network is unavailable.
  Future<Result<AdminModel, AppError>> verifySession() async {
    final result = await _apiClient.get<Map<String, dynamic>>(ApiConstants.me);

    return result.when(
      success: (data) async {
        final admin = AdminModel.fromJson(data);
        await _cacheAdmin(admin);
        return Result.success(admin);
      },
      failure: (error) {
        // If network error, try to return cached admin
        final cached = getCachedAdmin();
        if (cached != null) {
          AppLogger.info(
            'Server unreachable — using cached admin profile',
            tag: 'AUTH',
          );
          return Result.success(cached);
        }
        return Result.failure(error);
      },
    );
  }

  // ── Cached Admin ──────────────────────────────────────────────────────────

  /// Get the cached admin profile from Hive (works offline).
  AdminModel? getCachedAdmin() {
    try {
      final box = Hive.box(StorageKeys.adminCacheBox);
      final json = box.get(StorageKeys.adminProfile);
      if (json == null) return null;
      return AdminModel.fromJson(
        jsonDecode(json as String) as Map<String, dynamic>,
      );
    } catch (e) {
      AppLogger.error('Failed to read cached admin', tag: 'AUTH', error: e);
      return null;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  /// Clear all auth data: secure storage tokens + Hive admin cache.
  Future<void> logout() async {
    await _secureStorage.clearTokens();
    await _secureStorage.delete(key: StorageKeys.userId);
    await _secureStorage.delete(key: StorageKeys.userEmail);

    try {
      final box = Hive.box(StorageKeys.adminCacheBox);
      await box.clear();
    } catch (e) {
      AppLogger.error('Failed to clear admin cache', tag: 'AUTH', error: e);
    }

    AppLogger.info('Logged out — all auth data cleared', tag: 'AUTH');
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Persist admin profile JSON + login flag in Hive.
  Future<void> _cacheAdmin(AdminModel admin) async {
    try {
      final box = Hive.box(StorageKeys.adminCacheBox);
      await box.put(StorageKeys.adminProfile, jsonEncode(admin.toJson()));
      await box.put(StorageKeys.isLoggedIn, true);
    } catch (e) {
      AppLogger.error('Failed to cache admin profile', tag: 'AUTH', error: e);
    }
  }
}

/// Singleton provider for [AuthRepository].
@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) {
  return AuthRepository(
    apiClient: ref.watch(apiClientProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
  );
}
