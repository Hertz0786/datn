import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static String get apiBaseUrl {
    final String? fromEnv = dotenv.env['API_BASE_URL'];
    if (fromEnv != null && fromEnv.isNotEmpty) {
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
    return dotenv.env['AGORA_APP_ID'] ?? '';
  }

  static String get googleClientId {
    return dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  }
}
