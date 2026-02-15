/// Structured error type used throughout the app.
///
/// Mirrors the server `{ errors: [{ field?, message }] }` format.
class AppError {
  const AppError({required this.message, this.field, this.statusCode});

  final String message;
  final String? field;
  final int? statusCode;

  /// Build from the server error list: `[{ "field": "email", "message": "..." }]`
  factory AppError.fromServerErrors(List<dynamic> errors) {
    if (errors.isEmpty) {
      return const AppError(message: 'An unknown error occurred.');
    }
    final messages = errors
        .map((e) => (e as Map<String, dynamic>)['message'])
        .join('; ');
    return AppError(message: messages);
  }

  // ── Convenience constructors ──────────────────────────────────────────────
  factory AppError.network() =>
      const AppError(message: 'Network error. Please check your connection.');

  factory AppError.timeout() =>
      const AppError(message: 'Request timed out. Please try again.');

  factory AppError.unauthorized() => const AppError(
    message: 'Session expired. Please log in again.',
    statusCode: 401,
  );

  factory AppError.unknown([String? detail]) =>
      AppError(message: detail ?? 'An unexpected error occurred.');

  @override
  String toString() =>
      'AppError(message: $message, field: $field, statusCode: $statusCode)';
}
