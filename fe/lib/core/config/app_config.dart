import 'package:flutter/foundation.dart';

class AppConfig {
  static String get apiBaseUrl {
    const String fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    if (kIsWeb) {
      return 'http://localhost:5000';
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }

    return 'http://127.0.0.1:5000';
  }

  static String get agoraAppId {
    const String fromEnv = String.fromEnvironment('AGORA_APP_ID');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }
    return '';
  }
}
