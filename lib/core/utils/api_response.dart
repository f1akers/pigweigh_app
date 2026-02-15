/// Mirrors the server envelope: `{ data: T, errors: [] }`.
///
/// Used internally by [ApiClient] to parse raw JSON responses.
class ApiResponse<T> {
  const ApiResponse({this.data, this.errors = const []});

  final T? data;
  final List<ApiErrorEntry> errors;

  bool get hasErrors => errors.isNotEmpty;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromData,
  ) {
    final rawErrors = json['errors'] as List<dynamic>? ?? [];
    return ApiResponse<T>(
      data: json['data'] != null && fromData != null
          ? fromData(json['data'])
          : json['data'] as T?,
      errors: rawErrors.map((e) => ApiErrorEntry.fromJson(e)).toList(),
    );
  }
}

/// A single entry from the server `errors` array.
class ApiErrorEntry {
  const ApiErrorEntry({required this.message, this.field});

  final String message;
  final String? field;

  factory ApiErrorEntry.fromJson(Map<String, dynamic> json) {
    return ApiErrorEntry(
      message: json['message'] as String? ?? 'Unknown error',
      field: json['field'] as String?,
    );
  }
}
