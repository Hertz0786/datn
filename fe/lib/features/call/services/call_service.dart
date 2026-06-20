import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/realtime_service.dart';
import '../models/call_session.dart';
import 'call_api.dart';

/// Lifecycle of a 1-1 call as observed by the local user.
enum CallState { idle, initiating, ringing, connecting, connected, ended, failed }

/// High-level wrapper around the Agora RTC engine + backend signaling.
///
/// The service is intentionally a singleton (`CallService.instance`) so the
/// in-call UI screens, the incoming call prompt, and the app shell can all
/// observe the same call state and react to the same Agora events.
class CallService extends ChangeNotifier {
  CallService._();
  static final CallService instance = CallService._();

  // ----- Public state -----
  RtcEngine? _engine;
  CallState _state = CallState.idle;
  CallSession? _activeSession;
  String? _errorMessage;
  int _remoteUid = 0;
  bool _isMuted = false;
  bool _isCameraOff = false;
  Duration _callDuration = Duration.zero;
  Timer? _durationTimer;
  IncomingCall? _pendingIncoming;
  bool _isInitializing = false;

  /// Underlying Agora engine. May be null before the first call has been
  /// placed. Used by widgets that need to render local/remote video.
  RtcEngine? get engine => _engine;

  CallState get state => _state;
  CallSession? get activeSession => _activeSession;
  String? get errorMessage => _errorMessage;
  int get remoteUid => _remoteUid;
  bool get isMuted => _isMuted;
  bool get isCameraOff => _isCameraOff;
  Duration get callDuration => _callDuration;
  IncomingCall? get pendingIncoming => _pendingIncoming;
  bool get isInCall =>
      _state == CallState.connecting || _state == CallState.connected;
  bool get hasPendingIncoming => _pendingIncoming != null;

  // -----------------------------------------------------------------------
  // Setup
  // -----------------------------------------------------------------------

  /// Lazily create and configure the Agora engine. Safe to call multiple
  /// times. Idempotent.
  Future<void> ensureInitialized() async {
    if (_engine != null) return;
    if (_isInitializing) return;
    _isInitializing = true;
    try {
      if (AppConfig.agoraAppId.isEmpty) {
        throw StateError(
          'AGORA_APP_ID is not configured. Add it to fe/.env first.',
        );
      }
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AppConfig.agoraAppId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            _setState(CallState.connected);
            _startDurationTimer();
          },
          onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
            _remoteUid = remoteUid;
            notifyListeners();
          },
          onUserOffline:
              (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
            _remoteUid = 0;
            // Remote user left - end the call locally. The backend will
            // independently record this.
            _handleRemoteEnded();
          },
          onError: (ErrorCodeType code, String message) {
            _setError('Agora error ($code): $message');
          },
        ),
      );

      _attachSocketListeners();
    } finally {
      _isInitializing = false;
    }
  }

  // -----------------------------------------------------------------------
  // Outgoing call flow
  // -----------------------------------------------------------------------

  Future<CallSession> startOutgoingCall({
    required String calleeId,
    required String callType,
  }) async {
    await ensureInitialized();
    await _requestPermissions(callType);

    _setState(CallState.initiating);
    _errorMessage = null;

    try {
      final Map<String, dynamic> data = await CallApi.instance.initCall(
        calleeId: calleeId,
        callType: callType,
      );
      final CallSession session = CallSession.fromJson(data);
      _activeSession = session;
      _setState(CallState.ringing);
      return session;
    } catch (error) {
      _setError(_readMessage(error));
      rethrow;
    }
  }

  Future<void> cancelOutgoingCall() async {
    final CallSession? session = _activeSession;
    if (session == null) return;
    try {
      await CallApi.instance.endCall(session.callId);
    } catch (_) {
      // Best-effort: if backend call fails we still tear down locally.
    }
    await _leaveChannelSafely();
    _reset();
  }

  // -----------------------------------------------------------------------
  // Incoming call flow
  // -----------------------------------------------------------------------

  void registerIncoming(IncomingCall incoming) {
    _pendingIncoming = incoming;
    notifyListeners();
  }

  Future<void> acceptIncoming() async {
    final IncomingCall? incoming = _pendingIncoming;
    if (incoming == null) return;
    await ensureInitialized();
    await _requestPermissions(incoming.callType);

    try {
      final Map<String, dynamic> data =
          await CallApi.instance.acceptCall(incoming.callId);
      _activeSession = CallSession.fromJson(data);
      _pendingIncoming = null;
      notifyListeners();
      await _joinActiveChannel();
    } catch (error) {
      _setError(_readMessage(error));
      _pendingIncoming = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> rejectIncoming() async {
    final IncomingCall? incoming = _pendingIncoming;
    if (incoming == null) return;
    try {
      await CallApi.instance.rejectCall(incoming.callId);
    } catch (_) {
      // Ignore - the timeout will eventually mark it as missed.
    }
    _pendingIncoming = null;
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // Active call controls
  // -----------------------------------------------------------------------

  Future<void> hangUp() async {
    final CallSession? session = _activeSession;
    if (session == null) {
      _reset();
      return;
    }
    try {
      await CallApi.instance.endCall(session.callId);
    } catch (_) {
      // Ignore network errors when hanging up.
    }
    await _leaveChannelSafely();
    _reset();
  }

  Future<void> toggleMute() async {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    _isMuted = !_isMuted;
    await engine.muteLocalAudioStream(_isMuted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    _isCameraOff = !_isCameraOff;
    await engine.muteLocalVideoStream(_isCameraOff);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    await engine.switchCamera();
  }

  Future<void> setSpeaker(bool enabled) async {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    await engine.setEnableSpeakerphone(enabled);
  }

  // -----------------------------------------------------------------------
  // Internals
  // -----------------------------------------------------------------------

  Future<void> _joinActiveChannel() async {
    final CallSession? session = _activeSession;
    final RtcEngine? engine = _engine;
    if (session == null || engine == null) return;

    _setState(CallState.connecting);

    await engine.enableVideo();
    await engine.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 360, height: 640),
        frameRate: 15,
        bitrate: 400,
      ),
    );

    await engine.joinChannel(
      token: session.token,
      channelId: session.channelName,
      uid: session.uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        publishCameraTrack: true,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
      ),
    );
  }

  Future<void> _leaveChannelSafely() async {
    final RtcEngine? engine = _engine;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (error) {
      debugPrint('CallService: leaveChannel failed: $error');
    }
  }

  void _attachSocketListeners() {
    final RealtimeService realtime = RealtimeService.instance;

    realtime.on('call:accepted', (dynamic payload) {
      // Caller is informed when callee picks up; join the channel now.
      if (_activeSession == null) return;
      if (_state != CallState.ringing) return;
      _joinActiveChannel().catchError((Object error) {
        _setError(_readMessage(error));
        return null;
      });
    });

    realtime.on('call:rejected', (dynamic payload) {
      if (_activeSession == null) return;
      _setError('Call was declined');
      _reset();
    });

    realtime.on('call:ended', (dynamic payload) {
      if (!isInCall) return;
      _handleRemoteEnded();
    });

    realtime.on('call:cancelled', (dynamic payload) {
      if (!isInCall && _state != CallState.ringing) return;
      _setError('Call was cancelled');
      _reset();
    });

    realtime.on('call:timeout', (dynamic payload) {
      if (_activeSession == null) return;
      _setError('No answer');
      _reset();
    });
  }

  void _handleRemoteEnded() {
    _setState(CallState.ended);
    _stopDurationTimer();
    _leaveChannelSafely();
    Future<void>.delayed(const Duration(milliseconds: 600), _reset);
  }

  void _startDurationTimer() {
    _stopDurationTimer();
    _callDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _setState(CallState next) {
    _state = next;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    debugPrint('CallService: $message');
    notifyListeners();
  }

  void _reset() {
    _stopDurationTimer();
    _activeSession = null;
    _remoteUid = 0;
    _isMuted = false;
    _isCameraOff = false;
    _callDuration = Duration.zero;
    _state = CallState.idle;
    notifyListeners();
  }

  Future<void> _requestPermissions(String callType) async {
    final List<Permission> permissions = <Permission>[
      Permission.microphone,
      if (callType == 'video') Permission.camera,
    ];
    final Map<Permission, PermissionStatus> results = await permissions.request();
    if (results.values.any((PermissionStatus status) => status.isPermanentlyDenied)) {
      throw StateError(
        'Required permissions are blocked. Enable them in Settings.',
      );
    }
  }

  String _readMessage(Object error) {
    return error.toString().replaceFirst('ApiException', 'Call error');
  }

  @override
  void dispose() {
    _stopDurationTimer();
    _engine?.release();
    _engine = null;
    super.dispose();
  }
}
