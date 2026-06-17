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

    // Android emulator cannot reach host machine via localhost.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }

    return 'http://127.0.0.1:5000';
  }
}
