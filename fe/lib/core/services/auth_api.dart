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

  Future<PublicUser> register({
    required String displayName,
    required String username,
    required int age,
    required String password,
    List<String> favoriteTopics = const <String>[],
  }) async {
    final dynamic response = await _api.post(
      '/api/auth/register',
      authRequired: false,
      body: <String, dynamic>{
        'displayName': displayName,
        'username': username,
        'age': age,
        'password': password,
        'favoriteTopics': favoriteTopics,
      },
    );

    return _storeSessionFromAuthResponse(response);
  }

  Future<String?> requestPasswordReset({required String username}) async {
    final dynamic response = await _api.post(
      '/api/auth/password/forgot',
      authRequired: false,
      body: <String, dynamic>{'username': username},
    );
    final Map<String, dynamic> data = _toMap(response);
    final dynamic resetToken = data['resetToken'];
    return resetToken?.toString();
  }

  Future<void> resetPassword({
    required String username,
    required String token,
    required String password,
  }) async {
    await _api.post(
      '/api/auth/password/reset',
      authRequired: false,
      body: <String, dynamic>{
        'username': username,
        'token': token,
        'password': password,
      },
    );
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
