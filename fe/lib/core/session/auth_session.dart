import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/realtime_service.dart';
import '../../features/call/services/call_service.dart';

/// Persists the JWT and the cached user payload across app launches.
///
/// The token is stored in [FlutterSecureStorage] so that it lives in the
/// platform keychain/keystore. The user payload is JSON encoded next to it.
///
/// To avoid logging signed-in users out when they upgrade the app, the first
/// call to [restore] will also read the legacy [SharedPreferences] keys and
/// migrate them into secure storage. After that, [SharedPreferences] is no
/// longer touched.
class AuthSession {
  AuthSession._();

  static final AuthSession instance = AuthSession._();

  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user_json';

  static const String _legacyTokenKey = 'auth_token';
  static const String _legacyUserKey = 'auth_user_json';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final ValueNotifier<bool> isAuthenticated = ValueNotifier<bool>(false);

  String? _token;
  Map<String, dynamic>? _user;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;

  Future<void> restore() async {
    String? token = await _secureStorage.read(key: _tokenKey);
    String? rawUser = await _secureStorage.read(key: _userKey);

    if (token == null || rawUser == null) {
      // First-launch / upgraded install: read the legacy SharedPreferences
      // entries and copy them into secure storage.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      token = prefs.getString(_legacyTokenKey);
      rawUser = prefs.getString(_legacyUserKey);

      if (token != null && token.isNotEmpty && rawUser != null && rawUser.isNotEmpty) {
        try {
          await _secureStorage.write(key: _tokenKey, value: token);
          await _secureStorage.write(key: _userKey, value: rawUser);
        } catch (_) {
          // Best-effort migration; fall through and continue with in-memory
          // values below.
        }
        await prefs.remove(_legacyTokenKey);
        await prefs.remove(_legacyUserKey);
      }
    }

    if (token == null || token.isEmpty || rawUser == null || rawUser.isEmpty) {
      _token = null;
      _user = null;
      isAuthenticated.value = false;
      return;
    }

    try {
      final dynamic decoded = jsonDecode(rawUser);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid persisted user payload.');
      }

      _token = token;
      _user = decoded;
      isAuthenticated.value = true;
      // Start listening for call events so incoming calls are handled
      // even on cold start.
      CallService.instance.bootstrap();
    } catch (_) {
      await _clearStorage();
      _token = null;
      _user = null;
      isAuthenticated.value = false;
    }
  }

  Future<void> setAuthenticated({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    _token = token;
    _user = user;
    isAuthenticated.value = true;
    await _persist();
    // Start listening for call events immediately so incoming calls are
    // registered even before the user taps anything.
    CallService.instance.bootstrap();
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    _user = user;
    await _persist();
  }

  Future<void> clear() async {
    _token = null;
    _user = null;
    isAuthenticated.value = false;
    // Tear down the call service so the next user gets a clean slate.
    CallService.instance.resetSession();
    RealtimeService.instance.disconnect();
    await _clearStorage();
  }

  Future<void> _persist() async {
    if (_token == null || _token!.isEmpty || _user == null) {
      await _clearStorage();
      return;
    }

    try {
      await _secureStorage.write(key: _tokenKey, value: _token!);
      await _secureStorage.write(key: _userKey, value: jsonEncode(_user));
    } catch (error) {
      debugPrint('AuthSession: failed to persist credentials: $error');
    }
  }

  Future<void> _clearStorage() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _userKey);
    } catch (error) {
      debugPrint('AuthSession: failed to clear secure storage: $error');
    }
  }
}
