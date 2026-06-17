import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../../main.dart' show MyApp;
import '../session/auth_session.dart';
import 'api_exception.dart';

class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  final http.Client _httpClient = http.Client();

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authRequired = true,
  }) {
    return _request(
      method: 'GET',
      path: path,
      query: query,
      authRequired: authRequired,
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'POST',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'PATCH',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> uploadFile(
    String path, {
    required String filePath,
    String fileField = 'file',
    Map<String, String> fields = const <String, String>{},
    bool authRequired = true,
  }) async {
    final Uri uri = _buildUri(path);
    final request = http.MultipartRequest('POST', uri);
    request.fields.addAll(fields);

    if (authRequired) {
      final String? token = AuthSession.instance.token;
      if (token == null || token.isEmpty) {
        throw ApiException(
          message: 'Missing auth token. Please login again.',
          statusCode: 401,
        );
      }
      request.headers['Authorization'] = 'Bearer $token';
    }

    try {
      final String extension = filePath.contains('.')
          ? filePath.split('.').last.toLowerCase()
          : '';
      final String mimeType = _mimeTypeForExtension(extension);
      final String filename = filePath.split('/').last;

      final http.MultipartFile file = await http.MultipartFile.fromPath(
        fileField,
        filePath,
        filename: filename,
        contentType: _parseMediaType(mimeType),
      );
      request.files.add(file);
      final http.StreamedResponse streamedResponse = await _httpClient.send(
        request,
      );
      final String body = await streamedResponse.stream.bytesToString();
      final dynamic payload = _decodeBody(body);

      if (streamedResponse.statusCode >= 200 &&
          streamedResponse.statusCode < 300) {
        return payload;
      }

      if (streamedResponse.statusCode == 401) {
        _handleUnauthorized();
      }

      throw ApiException(
        message: _readMessage(payload, fallback: 'Upload failed.'),
        statusCode: streamedResponse.statusCode,
        payload: payload,
      );
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(message: 'Network error: $error', statusCode: 0);
    }
  }

  Future<dynamic> patchMultipartFields(
    String path, {
    Map<String, String> fields = const <String, String>{},
    bool authRequired = true,
  }) async {
    return patch(path, body: fields, authRequired: authRequired);
  }

  Future<dynamic> _request({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    required bool authRequired,
  }) async {
    final Uri uri = _buildUri(path, query: query);
    final Map<String, String> headers = {'Content-Type': 'application/json'};

    if (authRequired) {
      final String? token = AuthSession.instance.token;
      if (token == null || token.isEmpty) {
        throw ApiException(
          message: 'Missing auth token. Please login again.',
          statusCode: 401,
        );
      }
      headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;
    final String? encodedBody = body == null ? null : jsonEncode(body);

    try {
      switch (method) {
        case 'GET':
          response = await _httpClient.get(uri, headers: headers);
          break;
        case 'POST':
          response = await _httpClient.post(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        case 'PATCH':
          response = await _httpClient.patch(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        case 'DELETE':
          response = await _httpClient.delete(
            uri,
            headers: headers,
            body: encodedBody,
          );
          break;
        default:
          throw UnsupportedError('Unsupported method: $method');
      }
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(message: 'Network error: $error', statusCode: 0);
    }

    final dynamic payload = _decodeBody(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    if (response.statusCode == 401) {
      _handleUnauthorized();
    }

    final String message = _readMessage(payload, fallback: 'Request failed.');
    final String? code = _readCode(payload);
    final Map<String, dynamic>? details = _readDetails(payload);

    throw ApiException(
      message: message,
      statusCode: response.statusCode,
      payload: payload,
      code: code,
      details: details,
    );
  }

  void _handleUnauthorized() {
    final GlobalKey<ScaffoldMessengerState> messengerKey =
        MyApp.scaffoldMessengerKey;
    final ScaffoldMessengerState? messengerState = messengerKey.currentState;
    if (messengerState != null && messengerKey.currentContext != null) {
      messengerState
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Your session has expired. Please log in again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    unawaited(AuthSession.instance.clear());
  }

  Uri _buildUri(String path, {Map<String, dynamic>? query}) {
    final String normalizedPath = path.startsWith('/') ? path : '/$path';
    final Uri base = Uri.parse(AppConfig.apiBaseUrl);
    final Uri resolved = base.resolve(normalizedPath);

    if (query == null || query.isEmpty) {
      return resolved;
    }

    final Map<String, String> queryParameters = <String, String>{};
    query.forEach((String key, dynamic value) {
      if (value == null) {
        return;
      }
      final String str = value.toString().trim();
      if (str.isEmpty) {
        return;
      }
      queryParameters[key] = str;
    });

    return resolved.replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  dynamic _decodeBody(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(rawBody);
    } catch (_) {
      return <String, dynamic>{'message': rawBody};
    }
  }

  String _readMessage(dynamic payload, {required String fallback}) {
    if (payload is Map<String, dynamic>) {
      final dynamic message = payload['message'];
      if (message != null && message.toString().trim().isNotEmpty) {
        return message.toString();
      }
    }
    return fallback;
  }

  String? _readCode(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final dynamic details = payload['details'];
      if (details is Map<String, dynamic>) {
        final dynamic code = details['code'];
        if (code != null) {
          return code.toString();
        }
      }
      final dynamic directCode = payload['code'];
      if (directCode != null) {
        return directCode.toString();
      }
    }
    return null;
  }

  Map<String, dynamic>? _readDetails(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final dynamic details = payload['details'];
      if (details is Map<String, dynamic>) {
        return Map<String, dynamic>.from(details);
      }
    }
    return null;
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'svg':
        return 'image/svg+xml';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      default:
        return 'application/octet-stream';
    }
  }

  MediaType? _parseMediaType(String mimeType) {
    if (mimeType == 'application/octet-stream') {
      return null;
    }
    final int slash = mimeType.indexOf('/');
    if (slash <= 0) {
      return null;
    }
    return MediaType(mimeType.substring(0, slash), mimeType.substring(slash + 1));
  }
}
