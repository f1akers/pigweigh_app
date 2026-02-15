import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/constants/storage_keys.dart';

part 'secure_storage_service.g.dart';

/// Thin wrapper around [FlutterSecureStorage] for JWT management.
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // ── Token CRUD ────────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    DateTime? expiry,
  }) async {
    await _storage.write(key: StorageKeys.accessToken, value: accessToken);
    await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);
    if (expiry != null) {
      await _storage.write(
        key: StorageKeys.tokenExpiry,
        value: expiry.toIso8601String(),
      );
    }
  }

  Future<String?> getAccessToken() =>
      _storage.read(key: StorageKeys.accessToken);

  Future<String?> getRefreshToken() =>
      _storage.read(key: StorageKeys.refreshToken);

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> isTokenExpired() async {
    final raw = await _storage.read(key: StorageKeys.tokenExpiry);
    if (raw == null) return true;
    final expiry = DateTime.tryParse(raw);
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: StorageKeys.accessToken);
    await _storage.delete(key: StorageKeys.refreshToken);
    await _storage.delete(key: StorageKeys.tokenExpiry);
  }

  // ── Generic key-value ─────────────────────────────────────────────────────

  Future<void> saveUserId(String id) =>
      _storage.write(key: StorageKeys.userId, value: id);

  Future<void> saveUserEmail(String email) =>
      _storage.write(key: StorageKeys.userEmail, value: email);

  Future<String?> getUserId() => _storage.read(key: StorageKeys.userId);

  Future<String?> getUserEmail() => _storage.read(key: StorageKeys.userEmail);

  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Singleton provider for [SecureStorageService].
@Riverpod(keepAlive: true)
SecureStorageService secureStorageService(Ref ref) {
  return SecureStorageService();
}
