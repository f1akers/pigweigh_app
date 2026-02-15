import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/app_error.dart';
import '../../core/utils/result.dart';
import '../storage/secure_storage_service.dart';
import 'interceptors.dart';

part 'api_client.g.dart';

/// Centralized HTTP client using Dio with automatic token management.
///
/// **Server response format** (matches pigweigh-server):
/// ```json
/// { "data": { ... } | null, "errors": [{ "field?": "...", "message": "..." }] }
/// ```
///
/// This client automatically:
/// - Unwraps the `data` field from successful responses.
/// - Parses the `errors` array and returns an [AppError] on failure.
///
/// Usage:
/// ```dart
/// final api = ref.read(apiClientProvider);
/// final result = await api.get<Map<String, dynamic>>('/srp/active');
/// result.when(
///   success: (data) => print(data),
///   failure: (error) => print(error.message),
/// );
/// ```
class ApiClient {
  ApiClient({
    required SecureStorageService secureStorage,
    void Function()? onAuthFailure,
  }) : _secureStorage = secureStorage {
    _onAuthFailure = onAuthFailure ?? () {};
    _configureDio();
  }

  late final Dio _dio;
  final SecureStorageService _secureStorage;
  late final void Function() _onAuthFailure;

  Dio get dio => _dio;

  void _configureDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000/api',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.addAll([
      AuthInterceptor(
        secureStorage: _secureStorage,
        onTokenRefresh: _refreshToken,
        onAuthFailure: _onAuthFailure,
      ),
      if (kDebugMode) LoggingInterceptor(),
      ErrorInterceptor(),
      RetryInterceptor(),
    ]);
  }

  /// Attempt to refresh the access token using the stored refresh token.
  Future<bool> tryRefreshToken() => _refreshToken();

  Future<bool> _refreshToken() async {
    final refreshToken = await _secureStorage.getRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await Dio(
        BaseOptions(baseUrl: _dio.options.baseUrl),
      ).post('/auth/refresh', data: {'refreshToken': refreshToken});

      final data = response.data as Map<String, dynamic>?;
      final payload = data?['data'] as Map<String, dynamic>?;
      if (payload == null) return false;

      await _secureStorage.saveTokens(
        accessToken: payload['accessToken'] as String,
        refreshToken: payload['refreshToken'] as String? ?? refreshToken,
        expiry: payload['expiresAt'] != null
            ? DateTime.tryParse(payload['expiresAt'] as String)
            : null,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  void setAuthFailureCallback(void Function() callback) {
    _onAuthFailure = callback;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // HTTP Methods
  // ══════════════════════════════════════════════════════════════════════════

  Future<Result<T, AppError>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
      return _parseResponse<T>(response.data);
    } on DioException catch (e) {
      return Result.failure(_mapDioError(e));
    }
  }

  Future<Result<T, AppError>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return _parseResponse<T>(response.data);
    } on DioException catch (e) {
      return Result.failure(_mapDioError(e));
    }
  }

  Future<Result<T, AppError>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return _parseResponse<T>(response.data);
    } on DioException catch (e) {
      return Result.failure(_mapDioError(e));
    }
  }

  Future<Result<T, AppError>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return _parseResponse<T>(response.data);
    } on DioException catch (e) {
      return Result.failure(_mapDioError(e));
    }
  }

  Future<Result<T, AppError>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      final response = await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
      return _parseResponse<T>(response.data);
    } on DioException catch (e) {
      return Result.failure(_mapDioError(e));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Response parsing
  // ══════════════════════════════════════════════════════════════════════════

  Result<T, AppError> _parseResponse<T>(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) {
      return Result.success(responseData as T);
    }

    final errors = responseData['errors'] as List<dynamic>? ?? [];
    if (errors.isNotEmpty) {
      return Result.failure(AppError.fromServerErrors(errors));
    }

    final data = responseData['data'];
    return Result.success(data as T);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Error mapping
  // ══════════════════════════════════════════════════════════════════════════

  AppError _mapDioError(DioException e) {
    // Try to extract server error envelope first
    if (e.response?.data is Map<String, dynamic>) {
      final errors =
          (e.response!.data as Map<String, dynamic>)['errors']
              as List<dynamic>?;
      if (errors != null && errors.isNotEmpty) {
        return AppError.fromServerErrors(errors);
      }
    }

    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => AppError.timeout(),
      DioExceptionType.connectionError => AppError.network(),
      _ => AppError.unknown(e.message),
    };
  }
}

/// Singleton provider for [ApiClient].
@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  return ApiClient(secureStorage: storage);
}
