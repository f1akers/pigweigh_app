import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import '../storage/secure_storage_service.dart';

/// Attaches the stored access token to every outbound request
/// and handles 401 → refresh → retry flow.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.secureStorage,
    required this.onTokenRefresh,
    required this.onAuthFailure,
  });

  final SecureStorageService secureStorage;
  final Future<bool> Function() onTokenRefresh;
  final void Function() onAuthFailure;

  bool _isRefreshing = false;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final isPublic =
        options.path.contains('/auth/login') ||
        options.path.contains('/auth/refresh');

    if (!isPublic) {
      final token = await secureStorage.getAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == HttpStatus.unauthorized && !_isRefreshing) {
      _isRefreshing = true;
      final refreshed = await onTokenRefresh();
      _isRefreshing = false;

      if (refreshed) {
        // Retry the original request with new token
        final token = await secureStorage.getAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';

        try {
          final retryResponse = await Dio().fetch(err.requestOptions);
          return handler.resolve(retryResponse);
        } catch (retryError) {
          // Fall through to auth failure
        }
      }

      onAuthFailure();
    }

    handler.next(err);
  }
}

/// Logs HTTP requests & responses (debug builds only).
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    AppLogger.debug('→ ${options.method} ${options.uri}', tag: 'HTTP');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    AppLogger.debug(
      '← ${response.statusCode} ${response.requestOptions.uri}',
      tag: 'HTTP',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    AppLogger.error(
      '✖ ${err.response?.statusCode} ${err.requestOptions.uri}',
      tag: 'HTTP',
      error: err.message,
    );
    handler.next(err);
  }
}

/// Enriches Dio errors with better messages.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: err.error,
        message: _getErrorMessage(err),
      ),
    );
  }

  String _getErrorMessage(DioException err) {
    return switch (err.type) {
      DioExceptionType.connectionTimeout => 'Connection timed out.',
      DioExceptionType.sendTimeout => 'Send timed out.',
      DioExceptionType.receiveTimeout => 'Receive timed out.',
      DioExceptionType.connectionError => 'No internet connection.',
      _ => err.message ?? 'An unexpected error occurred.',
    };
  }
}

/// Retries failed requests on transient errors (network / 5xx).
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
  });

  final int maxRetries;
  final Duration retryDelay;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final shouldRetry =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);

    if (!shouldRetry) {
      handler.next(err);
      return;
    }

    final retryCount = err.requestOptions.extra['retryCount'] ?? 0;

    if (retryCount < maxRetries) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      await Future.delayed(retryDelay * (retryCount + 1));
      try {
        final response = await Dio().fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (_) {
        // Fall through to next handler
      }
    }

    handler.next(err);
  }
}
