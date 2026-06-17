class ApiException implements Exception {
  ApiException({
    required this.message,
    required this.statusCode,
    this.payload,
    this.code,
    this.details,
  });

  final String message;
  final int statusCode;
  final Object? payload;
  final String? code;
  final Map<String, dynamic>? details;

  @override
  String toString() =>
      'ApiException(statusCode: $statusCode, code: $code, message: $message)';
}
