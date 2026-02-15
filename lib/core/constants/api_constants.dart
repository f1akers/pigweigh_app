/// API endpoint constants.
///
/// All server endpoints are defined here so changes propagate from one place.
class ApiConstants {
  ApiConstants._();

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String login = '/auth/login';
  static const String me = '/auth/me';

  // ── SRP ───────────────────────────────────────────────────────────────────
  static const String srpList = '/srp';
  static const String srpActive = '/srp/active';
  static String srpById(String id) => '/srp/$id';
}
