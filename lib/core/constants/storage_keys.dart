/// Keys used for secure storage, Hive boxes, and cache tracking.
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
  static const String adminCacheBox = 'admin_cache';

  // ── Hive Keys — Admin Auth Cache ──────────────────────────────────────────
  static const String adminProfile = 'admin_profile';
  static const String isLoggedIn = 'is_logged_in';

  // ── Hive Keys — Sync Tracking ─────────────────────────────────────────────
  static const String lastSrpSyncAt = 'last_srp_sync_at';
}
