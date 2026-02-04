import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:peerdart/peerdart.dart';
import 'package:get_it/get_it.dart';
import 'settings_service.dart';
import '../../core/utils/logger.dart';

/// Watch party connection backend type
enum WatchPartyBackendType { supabase, peerdart, none }

/// Room state for watch party
enum WatchPartyState { idle, hosting, joining, connected, error }

/// Message types for watch party protocol
enum WatchPartyMessageType {
  sync, // Sync playback position
  play, // Play command
  pause, // Pause command
  seek, // Seek to position
  speed, // Playback speed change
  chat, // Chat message
  userJoined, // User joined notification
  userLeft, // User left notification
  roomInfo, // Room information
  requestSync, // Request sync from host
  unknown, // Unknown message type
}

/// Watch party message
class WatchPartyMessage {
  final WatchPartyMessageType type;
  final String senderId;
  final String? senderName;
  final dynamic payload;
  final DateTime timestamp;

  WatchPartyMessage({
    required this.type,
    required this.senderId,
    this.senderName,
    this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory WatchPartyMessage.fromJson(Map<String, dynamic> json) {
    return WatchPartyMessage(
      type: WatchPartyMessageType.values.firstWhere(
        (t) =>
            t.name ==
            (json['action'] ?? json['type']), // Support both for migration
        orElse: () => WatchPartyMessageType.unknown,
      ),
      senderId: json['senderId'] ?? '',
      senderName: json['senderName'],
      payload: json['payload'],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'action': type.name, // Renamed from 'type' to avoid collision
    'senderId': senderId,
    'senderName': senderName,
    'payload': payload,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// Chat message
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
  });
}

/// Participant in watch party
class WatchPartyParticipant {
  final String id;
  final String name;
  final bool isHost;
  final DateTime joinedAt;

  WatchPartyParticipant({
    required this.id,
    required this.name,
    required this.isHost,
    required this.joinedAt,
  });
}

/// Watch party room info
class WatchPartyRoom {
  final String id;
  final String hostId;
  final String hostName;
  final String? mediaTitle;
  final String? mediaUrl;

  WatchPartyRoom({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.mediaTitle,
    this.mediaUrl,
  });

  String get roomCode => id;
}

/// Backend interface
abstract class WatchPartyBackend {
  Future<void> connect({
    required String roomCode,
    required bool isHost,
    required String myId,
    required String myName,
    required Function(WatchPartyMessage) onMessage,
  });
  Future<void> disconnect();
  void sendBroadcast(WatchPartyMessage message);
  void sendMessage(String targetId, WatchPartyMessage message);
}

/// Supabase Backend Implementation
class _SupabaseBackend implements WatchPartyBackend {
  RealtimeChannel? _channel;
  final String _tag = 'WatchParty_Supabase';

  @override
  Future<void> connect({
    required String roomCode,
    required bool isHost,
    required String myId,
    required String myName,
    required Function(WatchPartyMessage) onMessage,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      _channel = supabase.channel(
        'watch_party_$roomCode',
        opts: const RealtimeChannelConfig(self: true),
      );

      final completer = Completer<void>();

      // Presence handling
      _channel!.onPresenceSync((payload) {
        Logger.d('🔄 Presence Sync Event. Payload: $payload', tag: _tag);

        try {
          final state = _channel!.presenceState();
          Logger.d('  -> Current Raw State: $state', tag: _tag);
          // In Supabase Flutter v2, presenceState() typically returns List<SinglePresenceState>
          // But error said "entries" not defined on List.
          // So we should iterate the list directly.

          for (final presence in state) {
            // presence is SinglePresenceState?
            // It likely has 'payload' map.
            // Or maybe the list itself contains the state objects.
            // Let's assume dynamic access to avoid strict type errors for now
            final payloads = (presence as dynamic).payloads as List<dynamic>?;

            if (payloads != null) {
              for (final payload in payloads) {
                final pData = payload as Map<String, dynamic>;
                final payloadId = pData['user_id'];
                if (payloadId != null && payloadId != myId) {
                  onMessage(
                    WatchPartyMessage(
                      type: WatchPartyMessageType.userJoined,
                      senderId: payloadId,
                      senderName: pData['name'],
                      timestamp: DateTime.parse(
                        pData['at'] ?? DateTime.now().toIso8601String(),
                      ),
                    ),
                  );
                }
              }
            }
          }
        } catch (e) {
          Logger.w('Presence sync error: $e', tag: _tag);
        }
      });

      _channel!.onPresenceJoin((payload) {
        Logger.d('Presence join: $payload', tag: _tag);
        try {
          final newPresences = payload.newPresences; // List<Presence>
          for (final presence in newPresences) {
            // Each presence has payloads?
            // Based on Supabase docs:
            final payloads = (presence as dynamic).payloads as List<dynamic>?;
            if (payloads != null) {
              for (final p in payloads) {
                if (p['user_id'] != myId) {
                  onMessage(
                    WatchPartyMessage(
                      type: WatchPartyMessageType.userJoined,
                      senderId: p['user_id'],
                      senderName: p['name'],
                    ),
                  );
                }
              }
            }
          }
        } catch (e) {
          Logger.w('Presence join error: $e', tag: _tag);
        }
      });

      _channel!.onPresenceLeave((payload) {
        Logger.d('Presence leave: $payload', tag: _tag);
        try {
          final leftPresences = payload.leftPresences;
          for (final presence in leftPresences) {
            final payloads = (presence as dynamic).payloads as List<dynamic>?;
            if (payloads != null) {
              for (final p in payloads) {
                if (p['user_id'] != myId) {
                  onMessage(
                    WatchPartyMessage(
                      type: WatchPartyMessageType.userLeft,
                      senderId: p['user_id'],
                    ),
                  );
                }
              }
            }
          }
        } catch (e) {
          Logger.w('Presence leave error: $e', tag: _tag);
        }
      });

      _channel!.onBroadcast(
        event: 'sync',
        callback: (payload) {
          try {
            final message = WatchPartyMessage.fromJson(payload);
            if (message.senderId == myId) return;
            onMessage(message);
          } catch (e) {
            Logger.w('Failed to parse broadcast: $e', tag: _tag);
          }
        },
      );

      _channel!.subscribe((status, error) {
        Logger.d('Channel status changed: $status', tag: _tag);

        if (status == RealtimeSubscribeStatus.subscribed) {
          Logger.i(
            '✅ SUBSCRIBED to Watch Party Channel: watch_party_$roomCode',
            tag: _tag,
          );

          // Track presence
          _channel!
              .track({
                'user_id': myId,
                'name': myName,
                'at': DateTime.now().toIso8601String(),
              })
              .then(
                (_) => Logger.d(
                  'Presence track sent for $myName ($myId)',
                  tag: _tag,
                ),
              )
              .catchError((err) {
                Logger.e('Failed to track presence', tag: _tag, error: err);
                return null;
              });

          if (!completer.isCompleted) completer.complete();
        } else if (status == RealtimeSubscribeStatus.closed) {
          Logger.w('Channel CLOSED', tag: _tag);
        }

        if (error != null) {
          Logger.e('Channel ERROR: $error', tag: _tag);
          if (!completer.isCompleted) completer.completeError(error);
        }
      });

      // Periodic probe to check presence state
      // This is for debugging purposes to see what Supabase thinks the state is
      Timer.periodic(const Duration(seconds: 5), (timer) {
        if (_channel == null) {
          timer.cancel();
          return;
        }
        try {
          // Direct access to internal state for debugging if possible,
          // otherwise just trigger logs implies we are alive.
          // Note: presenceState() returns the local view of state.
          final state = _channel?.presenceState();
          Logger.d(
            '🔍 Periodic Presence Check: ${state?.length ?? 0} entries',
            tag: _tag,
          );
          if (state != null && state.isNotEmpty) {
            for (var entry in state) {
              Logger.d('  - Entry: $entry', tag: _tag);
            }
          }
        } catch (e) {
          // Ignore
        }
      });

      // Wait for subscription to be active
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.w(
            'Supabase subscription timed out (15s), proceeding anyway',
            tag: _tag,
          );
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e) {
      Logger.e('Supabase connection failed', tag: _tag, error: e);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _channel?.unsubscribe();
    _channel = null;
    // Participants cleared in service reset, handled by caller mostly but backend should be clean
  }

  @override
  void sendBroadcast(WatchPartyMessage message) {
    _channel?.sendBroadcastMessage(event: 'sync', payload: message.toJson());
  }

  @override
  void sendMessage(String targetId, WatchPartyMessage message) {
    // Supabase broadcast goes to everyone, we can't easily target one user
    // without private channels or filtering on client side.
    // For now, we broadcast everything.
    sendBroadcast(message);
  }
}

/// PeerDart Backend Implementation
class _PeerDartBackend implements WatchPartyBackend {
  Peer? _peer;
  final List<DataConnection> _connections = [];
  final String _tag = 'WatchParty_PeerDart';
  // DataConnection? _hostConnection; // Removed unused field

  @override
  Future<void> connect({
    required String roomCode,
    required bool isHost,
    required String myId,
    required String myName,
    required Function(WatchPartyMessage) onMessage,
  }) async {
    try {
      final peerId = isHost ? 'oxide-$roomCode' : null; // Custom ID for host
      _peer = Peer(id: peerId);

      final completer = Completer<void>();

      _peer!.on('open').listen((id) {
        Logger.d('PeerDart open: $id', tag: _tag);
        if (!completer.isCompleted) completer.complete();
      });

      _peer!.on('error').listen((err) {
        Logger.e('PeerDart error', tag: _tag, error: err);
        if (!completer.isCompleted) completer.completeError(err);
      });

      // Host logic
      if (isHost) {
        _peer!.on<DataConnection>('connection').listen((conn) {
          Logger.d('PeerDart client connected', tag: _tag);
          _connections.add(conn);
          _setupConnection(conn, onMessage);
        });
      }
      // Client logic
      else {
        // Wait for peer to open before connecting
        await completer.future;

        final hostId = 'oxide-$roomCode';
        Logger.d('Connecting to host: $hostId', tag: _tag);

        final conn = _peer!.connect(hostId);
        // _hostConnection = conn;
        _connections.add(conn);

        conn.on('open').listen((_) {
          Logger.d('Connected to host', tag: _tag);
          // Send initial joint message immediately?
        });

        _setupConnection(conn, onMessage);

        // Wait for connection to actually open?
        // PeerDart connect returns connection immediately but it might not be open.
      }

      if (isHost) {
        await completer.future;
      }
    } catch (e) {
      Logger.e('PeerDart init failed', tag: _tag, error: e);
      rethrow;
    }
  }

  void _setupConnection(
    DataConnection conn,
    Function(WatchPartyMessage) onMessage,
  ) {
    conn.on('data').listen((data) {
      try {
        // PeerDart data is dynamic, usually String or Map
        final json = data is String ? jsonDecode(data) : data;
        final message = WatchPartyMessage.fromJson(json);
        onMessage(message);
      } catch (e) {
        Logger.w('PeerDart parse error: $e', tag: _tag);
      }
    });

    conn.on('close').listen((_) {
      _connections.remove(conn);
    });
  }

  @override
  Future<void> disconnect() async {
    _connections.clear();
    _peer?.dispose();
    _peer = null;
  }

  @override
  void sendBroadcast(WatchPartyMessage message) {
    final json = jsonEncode(message.toJson());
    for (var conn in _connections) {
      conn.send(json);
    }
  }

  @override
  void sendMessage(String targetId, WatchPartyMessage message) {
    // PeerDart doesn't expose remote peer ID easily on DataConnection in all versions,
    // but we just broadcast for now as per Supabase logic.
    sendBroadcast(message);
  }
}

/// Sync correction mode for drift handling
enum SyncCorrectionMode {
  /// No correction needed
  none,

  /// Speed up playback (we're behind)
  speedUp,

  /// Slow down playback (we're ahead)
  slowDown,

  /// Hard seek required (too far out of sync)
  hardSeek,
}

/// Watch party service for synchronized viewing
/// Uses Supabase Realtime with automatic fallback to PeerDart (P2P)
///
/// Fallback Strategy:
/// 1. Try Supabase (Cloud)
/// 2. If fails, try PeerDart (P2P)
///
/// Sync Strategy:
/// - Drift < 2s: Ignore (acceptable)
/// - Drift 2-5s: Smooth correction via playback speed (1.1x or 0.9x)
/// - Drift 5-10s: Fast correction (1.2x or 0.8x)
/// - Drift > 10s: Hard seek
class WatchPartyService extends ChangeNotifier {
  static const String _tag = 'WatchParty';

  // Sync thresholds (in milliseconds)
  static const int _driftIgnoreThreshold = 5000; // < 5s: ignore
  static const int _driftSmoothThreshold = 10000; // 5-10s: smooth correction
  static const int _driftFastThreshold = 15000; // 10-15s: fast correction
  // > 15s: hard seek

  WatchPartyState _state = WatchPartyState.idle;
  WatchPartyBackendType _backendType = WatchPartyBackendType.none;
  WatchPartyBackend? _backend;

  WatchPartyRoom? _room;
  final List<WatchPartyParticipant> _participants = [];
  final List<ChatMessage> _chatMessages = [];
  String? _error;

  // User info
  final String _myId = DateTime.now().millisecondsSinceEpoch.toString();
  String _myName = 'User';
  bool _isHost = false;
  String? _currentRoomCode;

  // Playback state
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  String? _currentMediaUrl;
  String? _currentMediaTitle;
  double _playbackSpeed = 1.0;
  double _baseSyncSpeed = 1.0; // Speed set by user (not correction)

  // Sync state
  SyncCorrectionMode _correctionMode = SyncCorrectionMode.none;
  Duration _lastHostPosition = Duration.zero;
  DateTime _lastSyncTime = DateTime.now();
  int _consecutiveBufferEvents = 0;
  bool _isCorrecting = false;

  // Callbacks
  Function(bool isPlaying)? onPlayPauseChanged;
  Function(Duration position)? onSeek;
  Function(double speed)? onSpeedChanged;
  Function(String url, String title)? onMediaChanged;
  Function(int qualityDelta)?
  onQualityAdjustRequested; // +1 = increase, -1 = decrease
  Function(SyncCorrectionMode mode, int driftMs)? onSyncStatusChanged;

  // Getters
  WatchPartyState get state => _state;
  WatchPartyBackendType get backendType => _backendType;
  WatchPartyRoom? get room => _room;
  List<WatchPartyParticipant> get participants =>
      List.unmodifiable(_participants);
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  String? get error => _error;
  bool get isHost => _isHost;
  String get myId => _myId;
  String? get currentRoomCode => _currentRoomCode;
  String get myName => _myName;
  double get playbackSpeed => _playbackSpeed;
  bool get isPlaying => _isPlaying;
  SyncCorrectionMode get correctionMode => _correctionMode;
  bool get isSynced => _correctionMode == SyncCorrectionMode.none;

  // ... (inside class)

  // Dependency Injection for testing
  final WatchPartyBackend Function(WatchPartyBackendType)? _backendFactory;

  WatchPartyService({
    WatchPartyBackend Function(WatchPartyBackendType)? backendFactory,
  }) : _backendFactory = backendFactory {
    _loadName();
  }

  void _loadName() {
    try {
      final settings = GetIt.I<SettingsService>();
      _myName = settings.state.watchPartyName;
    } catch (e) {
      Logger.w('Failed to load name from settings', tag: _tag);
    }
  }

  void setMyName(String name) {
    _myName = name;
    notifyListeners();
    try {
      GetIt.I<SettingsService>().setWatchPartyName(name);
    } catch (e) {
      Logger.e('Failed to save name', tag: _tag, error: e);
    }
  }

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  // --------------------------------------------------------------------------
  // Host Logic
  // --------------------------------------------------------------------------

  Future<bool> hostRoom({String? mediaUrl, String? mediaTitle}) async {
    _state = WatchPartyState.hosting;
    _error = null;
    notifyListeners();

    final roomCode = _generateRoomCode();
    _currentRoomCode = roomCode;
    _currentMediaUrl = mediaUrl;
    _currentMediaTitle = mediaTitle;
    _isHost = true;

    // 1. Try Supabase
    try {
      Logger.i('Hosting with Supabase: $roomCode', tag: _tag);
      await _initBackend(WatchPartyBackendType.supabase, roomCode);
    } catch (e) {
      Logger.w(
        'Supabase hosting failed ($e), falling back to PeerDart',
        tag: _tag,
      );

      // 2. Fallback to PeerDart
      try {
        await _initBackend(WatchPartyBackendType.peerdart, roomCode);
      } catch (e2) {
        Logger.e('PeerDart hosting failed', tag: _tag, error: e2);
        _setError('Connection failed: $e2');
        return false;
      }
    }

    _setupHostState(roomCode, mediaUrl, mediaTitle);
    return true;
  }

  void _setupHostState(String roomCode, String? mediaUrl, String? mediaTitle) {
    _room = WatchPartyRoom(
      id: roomCode,
      hostId: _myId,
      hostName: _myName,
      mediaTitle: mediaTitle,
      mediaUrl: mediaUrl,
    );

    _participants.add(
      WatchPartyParticipant(
        id: _myId,
        name: _myName,
        isHost: true,
        joinedAt: DateTime.now(),
      ),
    );

    _state = WatchPartyState.connected;
    notifyListeners();

    _startHeartbeat();
  }

  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      // Host always syncs position (even when paused) for new joiners
      if (_isHost) {
        syncPosition(_currentPosition, _isPlaying);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // --------------------------------------------------------------------------
  // Client Logic
  // --------------------------------------------------------------------------

  Future<bool> joinRoom(String roomCode) async {
    _state = WatchPartyState.joining;
    _error = null;
    notifyListeners();

    _isHost = false;
    _currentRoomCode = roomCode.toUpperCase();

    // 1. Try Supabase
    try {
      Logger.i('Joining with Supabase: $_currentRoomCode', tag: _tag);
      await _initBackend(WatchPartyBackendType.supabase, _currentRoomCode!);
    } catch (e) {
      Logger.w(
        'Supabase join failed ($e), falling back to PeerDart',
        tag: _tag,
      );

      // 2. Fallback to PeerDart
      try {
        await _initBackend(WatchPartyBackendType.peerdart, _currentRoomCode!);
      } catch (e2) {
        Logger.e('PeerDart join failed', tag: _tag, error: e2);
        _setError('Connection failed: $e2');
        return false;
      }
    }

    _setupClientState();
    return true;
  }

  void _setupClientState() {
    _participants.add(
      WatchPartyParticipant(
        id: _myId,
        name: _myName,
        isHost: false,
        joinedAt: DateTime.now(),
      ),
    );

    // Send join message
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.userJoined,
        senderId: _myId,
        senderName: _myName,
      ),
    );

    // Request sync
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.requestSync,
        senderId: _myId,
      ),
    );

    _state = WatchPartyState.connected;
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Common Backend Init
  // --------------------------------------------------------------------------

  Future<void> _initBackend(WatchPartyBackendType type, String roomCode) async {
    _backendType = type;

    if (_backendFactory != null) {
      _backend = _backendFactory(type);
    } else if (type == WatchPartyBackendType.supabase) {
      _backend = _SupabaseBackend();
    } else {
      _backend = _PeerDartBackend();
    }

    await _backend!.connect(
      roomCode: roomCode,
      isHost: _isHost,
      myId: _myId,
      myName: _myName,
      onMessage: _onMessageReceived,
    );
  }

  void _setError(String msg) {
    _state = WatchPartyState.error;
    _error = msg;
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Message Handling
  // --------------------------------------------------------------------------

  void _onMessageReceived(WatchPartyMessage message) {
    switch (message.type) {
      case WatchPartyMessageType.userJoined:
        Logger.d('User joined: ${message.senderName}', tag: _tag);

        // Prevent duplicate participants
        if (_participants.any((p) => p.id == message.senderId)) {
          Logger.d(
            'User ${message.senderName} already in list, skipping',
            tag: _tag,
          );
          break;
        }

        _participants.add(
          WatchPartyParticipant(
            id: message.senderId,
            name: message.senderName ?? 'Unknown',
            isHost: false,
            joinedAt: DateTime.now(),
          ),
        );

        // Host sends sync to new user
        if (_isHost) {
          syncPosition(_currentPosition, _isPlaying);
        }
        break;

      case WatchPartyMessageType.userLeft:
        _participants.removeWhere((p) => p.id == message.senderId);
        notifyListeners();
        break;

      case WatchPartyMessageType.sync:
        if (!_isHost) {
          _handleSync(message);
        }
        break;

      case WatchPartyMessageType.play:
        _isPlaying = true;
        onPlayPauseChanged?.call(true);
        notifyListeners();
        break;

      case WatchPartyMessageType.pause:
        _isPlaying = false;
        onPlayPauseChanged?.call(false);
        notifyListeners();
        break;

      case WatchPartyMessageType.seek:
        _currentPosition = Duration(milliseconds: message.payload as int);
        onSeek?.call(_currentPosition);
        notifyListeners();
        break;

      case WatchPartyMessageType.speed:
        final speed = (message.payload as num).toDouble();
        _playbackSpeed = speed;
        onSpeedChanged?.call(speed);
        notifyListeners();
        break;

      case WatchPartyMessageType.chat:
        _chatMessages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            senderId: message.senderId,
            senderName: message.senderName ?? 'Unknown',
            message: message.payload as String,
            timestamp: message.timestamp,
          ),
        );
        notifyListeners();
        break;

      case WatchPartyMessageType.requestSync:
        if (_isHost) {
          syncPosition(_currentPosition, _isPlaying);
        }
        break;

      case WatchPartyMessageType.roomInfo:
        // Handled in sync usually
        break;

      case WatchPartyMessageType.unknown:
        Logger.w(
          'Received unknown message type: ${message.payload}',
          tag: _tag,
        );
        break;
    }
  }

  void _handleSync(WatchPartyMessage message) {
    if (message.payload is! Map<String, dynamic>) {
      Logger.w(
        'Invalid sync payload type: ${message.payload.runtimeType}',
        tag: _tag,
      );
      return;
    }
    final payload = message.payload as Map<String, dynamic>;
    final hostPosition = Duration(milliseconds: payload['position'] ?? 0);
    final hostTimestamp = message.timestamp;

    // Update base speed from host
    final hostSpeed = (payload['speed'] as num?)?.toDouble();
    if (hostSpeed != null) {
      _baseSyncSpeed = hostSpeed;
    }

    // Account for network latency (estimate based on timestamp)
    final networkDelay = DateTime.now().difference(hostTimestamp);
    final adjustedHostPosition = hostPosition + networkDelay;

    _lastHostPosition = adjustedHostPosition;
    _lastSyncTime = DateTime.now();

    // Calculate drift (positive = we're ahead, negative = we're behind)
    final driftMs = (_currentPosition - adjustedHostPosition).inMilliseconds;
    final absDrift = driftMs.abs();

    // Determine correction mode
    final previousMode = _correctionMode;

    if (absDrift <= _driftIgnoreThreshold) {
      // Within acceptable range - no correction needed
      _correctionMode = SyncCorrectionMode.none;
      if (_isCorrecting) {
        _isCorrecting = false;
        // Restore base speed
        if (_playbackSpeed != _baseSyncSpeed) {
          _playbackSpeed = _baseSyncSpeed;
          onSpeedChanged?.call(_playbackSpeed);
        }
      }
    } else if (absDrift <= _driftSmoothThreshold) {
      // 2-5 seconds: smooth correction
      _correctionMode = driftMs > 0
          ? SyncCorrectionMode.slowDown
          : SyncCorrectionMode.speedUp;
      _applySmoothCorrection(driftMs);
    } else if (absDrift <= _driftFastThreshold) {
      // 5-10 seconds: fast correction
      _correctionMode = driftMs > 0
          ? SyncCorrectionMode.slowDown
          : SyncCorrectionMode.speedUp;
      _applyFastCorrection(driftMs);
    } else {
      // > 10 seconds: hard seek
      _correctionMode = SyncCorrectionMode.hardSeek;
      Logger.i(
        'Sync drift too large (${absDrift}ms). Hard seeking to host position.',
        tag: _tag,
      );
      _currentPosition = adjustedHostPosition;
      onSeek?.call(_currentPosition);
      _isCorrecting = false;
      // Restore base speed after seek
      if (_playbackSpeed != _baseSyncSpeed) {
        _playbackSpeed = _baseSyncSpeed;
        onSpeedChanged?.call(_playbackSpeed);
      }
    }

    // Notify about sync status change
    if (_correctionMode != previousMode) {
      onSyncStatusChanged?.call(_correctionMode, driftMs);
      Logger.d(
        'Sync mode changed: $previousMode -> $_correctionMode (drift: ${driftMs}ms)',
        tag: _tag,
      );
    }

    final wasPlaying = _isPlaying;
    _isPlaying = payload['isPlaying'] ?? false;

    // Update room info if needed
    if (_room == null && payload.containsKey('mediaTitle')) {
      _room = WatchPartyRoom(
        id: _currentRoomCode ?? '',
        hostId: message.senderId,
        hostName: message.senderName ?? 'Host',
        mediaUrl: payload['mediaUrl'],
        mediaTitle: payload['mediaTitle'],
      );
      _currentMediaUrl = payload['mediaUrl'];
      _currentMediaTitle = payload['mediaTitle'];
      onMediaChanged?.call(_currentMediaUrl!, _currentMediaTitle!);
    }

    // Only call onSeek for hard seek mode (already called above when needed)
    // For smooth/fast correction, we use speed adjustment instead of seeking
    // Note: onSeek is already called in the hardSeek branch above

    if (_isPlaying != wasPlaying) {
      onPlayPauseChanged?.call(_isPlaying);
    }

    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  Future<void> leaveRoom() async {
    _stopHeartbeat(); // Stop timer
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.userLeft,
        senderId: _myId,
        senderName: _myName,
      ),
    );

    await _backend?.disconnect();
    _backend = null;
    _backendType = WatchPartyBackendType.none;

    _room = null;
    _participants.clear();
    _chatMessages.clear();
    _isHost = false;
    _state = WatchPartyState.idle;
    notifyListeners();
  }

  void play() {
    _isPlaying = true;
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.play,
        senderId: _myId,
        senderName: _myName,
      ),
    );
    notifyListeners();
  }

  void pause() {
    _isPlaying = false;
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.pause,
        senderId: _myId,
        senderName: _myName,
      ),
    );
    notifyListeners();
  }

  void seek(Duration position) {
    _currentPosition = position;
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.seek,
        senderId: _myId,
        senderName: _myName,
        payload: position.inMilliseconds,
      ),
    );
    notifyListeners();
  }

  void requestSync() {
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.requestSync,
        senderId: _myId,
      ),
    );
  }

  void setSpeed(double speed) {
    _baseSyncSpeed = speed; // Remember user's preferred speed
    _playbackSpeed = speed;
    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.speed,
        senderId: _myId,
        senderName: _myName,
        payload: speed,
      ),
    );
    notifyListeners();
  }

  /// Apply smooth correction for 2-5 second drift
  void _applySmoothCorrection(int driftMs) {
    _isCorrecting = true;
    final correctionSpeed = driftMs > 0
        ? _baseSyncSpeed *
              0.9 // We're ahead, slow down
        : _baseSyncSpeed * 1.1; // We're behind, speed up

    if (_playbackSpeed != correctionSpeed) {
      _playbackSpeed = correctionSpeed;
      onSpeedChanged?.call(_playbackSpeed);
      Logger.d(
        'Smooth correction: speed set to ${correctionSpeed}x (drift: ${driftMs}ms)',
        tag: _tag,
      );
    }
  }

  /// Apply fast correction for 5-10 second drift
  void _applyFastCorrection(int driftMs) {
    _isCorrecting = true;
    final correctionSpeed = driftMs > 0
        ? _baseSyncSpeed *
              0.8 // We're ahead, slow down more
        : _baseSyncSpeed * 1.2; // We're behind, speed up more

    if (_playbackSpeed != correctionSpeed) {
      _playbackSpeed = correctionSpeed;
      onSpeedChanged?.call(_playbackSpeed);
      Logger.d(
        'Fast correction: speed set to ${correctionSpeed}x (drift: ${driftMs}ms)',
        tag: _tag,
      );
    }
  }

  /// Report buffering event (for adaptive quality)
  void reportBuffering(bool isBuffering) {
    if (isBuffering) {
      _consecutiveBufferEvents++;
      if (_consecutiveBufferEvents >= 3) {
        // Too many buffer events, request quality reduction
        Logger.i(
          'Too many buffer events ($_consecutiveBufferEvents), requesting quality reduction',
          tag: _tag,
        );
        onQualityAdjustRequested?.call(-1);
        _consecutiveBufferEvents = 0;
      }
    } else {
      // Reset on successful playback
      _consecutiveBufferEvents = 0;
    }
  }

  /// Get current sync drift in milliseconds (for UI)
  int getCurrentDriftMs() {
    return (_currentPosition - _lastHostPosition).inMilliseconds;
  }

  void updateLocalPosition(Duration position) {
    _currentPosition = position;
  }

  void syncPosition(Duration position, bool isPlaying) {
    if (!_isHost) return;

    _currentPosition = position;
    _isPlaying = isPlaying;

    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.sync,
        senderId: _myId,
        senderName: _myName,
        payload: {
          'position': position.inMilliseconds,
          'isPlaying': isPlaying,
          'speed': _playbackSpeed,
          'mediaUrl': _currentMediaUrl,
          'mediaTitle': _currentMediaTitle,
        },
      ),
    );
  }

  void sendChatMessage(String message) {
    final chatMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _myId,
      senderName: _myName,
      message: message,
      timestamp: DateTime.now(),
    );
    _chatMessages.add(chatMsg);

    _send(
      WatchPartyMessage(
        type: WatchPartyMessageType.chat,
        senderId: _myId,
        senderName: _myName,
        payload: message,
      ),
    );
    notifyListeners();
  }

  void _send(WatchPartyMessage message) {
    _backend?.sendBroadcast(message);
  }
}
