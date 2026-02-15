/// Keys used for secure storage and Hive boxes.
class StorageKeys {
  StorageKeys._();

  // ── Secure Storage (flutter_secure_storage) ───────────────────────────────
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String tokenExpiry = 'token_expiry';
  static const String userId = 'user_id';
  static const String userEmail = 'user_email';

  // ── Hive Boxes ────────────────────────────────────────────────────────────
  static const String settingsBox = 'settings';
  static const String cacheBox = 'cache';
}
