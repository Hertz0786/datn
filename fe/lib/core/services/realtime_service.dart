import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../session/auth_session.dart';

class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;
  String? _activeToken;

  bool get isConnected => _socket?.connected == true;

  void connect() {
    final String? token = AuthSession.instance.token;
    if (token == null || token.isEmpty) {
      // No credentials: drop any existing connection.
      _teardownSocket();
      return;
    }

    if (_socket != null && _activeToken == token) {
      if (!_socket!.connected) {
        _socket!.connect();
      }
      return;
    }

    // Token changed (login, register, or account switch). Rebuild the socket
    // from scratch so listeners from the previous account never leak.
    _teardownSocket();

    _socket = io.io(
      AppConfig.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .disableAutoConnect()
          .setAuth(<String, dynamic>{'token': token})
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1500)
          .build(),
    );

    _activeToken = token;
    _socket!.connect();
  }

  void disconnect() {
    _teardownSocket();
    _activeToken = null;
  }

  void _teardownSocket() {
    final io.Socket? socket = _socket;
    _socket = null;
    if (socket == null) {
      return;
    }
    try {
      socket.clearListeners();
      socket.dispose();
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  void on(String event, void Function(dynamic payload) handler) {
    connect();
    _socket?.on(event, handler);
  }

  void off(String event, [dynamic handler]) {
    if (handler == null) {
      _socket?.off(event);
      return;
    }
    _socket?.off(event, handler);
  }

  void emit(String event, dynamic payload) {
    connect();
    _socket?.emit(event, payload);
  }
}
