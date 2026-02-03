import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import '../config/app_config.dart';
import '../error/exceptions.dart';

/// HTTP client wrapper with retry logic and error handling
class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        headers: {
          'User-Agent': AppConfig.userAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
        },
      ),
    );

    // Add retry interceptor
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ],
      ),
    );
  }

  /// GET request that returns response body as String
  Future<String> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.get<String>(
        url,
        queryParameters: queryParameters,
        options: Options(headers: headers, responseType: ResponseType.plain),
      );
      return response.data ?? '';
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// GET request that returns JSON
  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  /// POST request
  Future<Map<String, dynamic>> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? headers,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return response.data ?? {};
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  AppException _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkException(message: 'Connection timeout');
      case DioExceptionType.connectionError:
        return const NetworkException(message: 'No internet connection');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode ?? 0;
        return ServerException(
          message: 'Server error: ${e.response?.statusMessage}',
          statusCode: statusCode,
        );
      default:
        return NetworkException(message: e.message ?? 'Unknown network error');
    }
  }

  /// Get the underlying Dio instance for advanced usage
  Dio get dio => _dio;
}
