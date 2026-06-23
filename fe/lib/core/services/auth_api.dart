import '../models/public_user.dart';
import '../network/api_client.dart';
import '../session/auth_session.dart';
import 'realtime_service.dart';

class AuthApi {
  AuthApi._();

  static final AuthApi instance = AuthApi._();

  final ApiClient _api = ApiClient.instance;

  Future<PublicUser> login({
    required String username,
    required String password,
  }) async {
    final dynamic response = await _api.post(
      '/api/auth/login',
      authRequired: false,
      body: <String, dynamic>{'username': username, 'password': password},
    );

    return _storeSessionFromAuthResponse(response);
  }

  Future<void> sendVerificationCode({required String email}) async {
    await _api.post(
      '/api/auth/send-verification',
      authRequired: false,
      body: <String, dynamic>{'email': email},
    );
  }

  Future<PublicUser> register({
    required String displayName,
    required String username,
    required DateTime birthDate,
    required String password,
    String? email,
    String? verificationCode,
    List<String> favoriteTopics = const <String>[],
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'displayName': displayName,
      'username': username,
      'birthDate': birthDate.toIso8601String(),
      'password': password,
      'favoriteTopics': favoriteTopics,
    };
    if (email != null && email.isNotEmpty) {
      body['email'] = email;
    }
    if (verificationCode != null && verificationCode.isNotEmpty) {
      body['verificationCode'] = verificationCode;
    }

    final dynamic response = await _api.post(
      '/api/auth/register',
      authRequired: false,
      body: body,
    );

    return _storeSessionFromAuthResponse(response);
  }

  Future<void> sendPasswordResetCode({required String email}) async {
    await _api.post(
      '/api/auth/password/forgot',
      authRequired: false,
      body: <String, dynamic>{'email': email},
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    await _api.post(
      '/api/auth/password/reset',
      authRequired: false,
      body: <String, dynamic>{
        'email': email,
        'code': code,
        'password': password,
      },
    );
  }

  Future<PublicUser> googleLogin({required String idToken}) async {
    final dynamic response = await _api.post(
      '/api/auth/google',
      authRequired: false,
      body: <String, dynamic>{'idToken': idToken},
    );

    return _storeSessionFromAuthResponse(response);
  }

  Future<PublicUser> getMe() async {
    final dynamic response = await _api.get('/api/auth/me');
    final Map<String, dynamic> data = _toMap(response);
    final PublicUser user = PublicUser.fromJson(_toMap(data['user']));
    await AuthSession.instance.updateUser(<String, dynamic>{
      'id': user.id,
      'displayName': user.displayName,
      'username': user.username,
      'age': user.age,
      'role': user.role,
      'avatarUrl': user.avatarUrl,
      'coverUrl': user.coverUrl,
      'bio': user.bio,
      'favoriteTopics': user.favoriteTopics,
      'privacy': user.privacy.toJson(),
    });
    return user;
  }

  Future<PublicUser> _storeSessionFromAuthResponse(dynamic response) async {
    final Map<String, dynamic> data = _toMap(response);
    final String token = (data['token'] ?? '').toString();
    final Map<String, dynamic> userJson = _toMap(data['user']);

    final PublicUser user = PublicUser.fromJson(userJson);
    await AuthSession.instance.setAuthenticated(token: token, user: userJson);
    RealtimeService.instance.connect();
    return user;
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }
}
