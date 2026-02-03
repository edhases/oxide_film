import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

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
        (t) => t.name == json['type'],
        orElse: () => WatchPartyMessageType.sync,
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
    'type': type.name,
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
  final int port;
  final String? ipAddress;

  WatchPartyRoom({
    required this.id,
    required this.hostId,
    required this.hostName,
    this.mediaTitle,
    this.mediaUrl,
    required this.port,
    this.ipAddress,
  });

  String get connectionString => '$ipAddress:$port';
}

/// Watch party service for synchronized viewing
/// Uses TCP sockets for LAN-based watch parties
class WatchPartyService extends ChangeNotifier {
  WatchPartyState _state = WatchPartyState.idle;
  WatchPartyRoom? _room;
  final List<WatchPartyParticipant> _participants = [];
  final List<ChatMessage> _chatMessages = [];
  String? _error;

  // Networking
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];

  // User info
  final String _myId = DateTime.now().millisecondsSinceEpoch.toString();
  String _myName = 'User';

  // Playback state
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  String? _currentMediaUrl;
  String? _currentMediaTitle;

  // Playback speed
  double _playbackSpeed = 1.0;

  // Callbacks
  Function(bool isPlaying)? onPlayPauseChanged;
  Function(Duration position)? onSeek;
  Function(double speed)? onSpeedChanged;
  Function(String url, String title)? onMediaChanged;

  // Getters
  WatchPartyState get state => _state;
  WatchPartyRoom? get room => _room;
  List<WatchPartyParticipant> get participants =>
      List.unmodifiable(_participants);
  List<ChatMessage> get chatMessages => List.unmodifiable(_chatMessages);
  String? get error => _error;
  bool get isHost => _room?.hostId == _myId;
  String get myId => _myId;
  String get myName => _myName;
  double get playbackSpeed => _playbackSpeed;

  /// Set user display name
  void setMyName(String name) {
    _myName = name;
    notifyListeners();
  }

  /// Create and host a new watch party
  Future<bool> hostRoom({String? mediaUrl, String? mediaTitle}) async {
    try {
      _state = WatchPartyState.hosting;
      _error = null;
      notifyListeners();

      // Find available port
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _serverSocket = server;

      // Get local IP address
      String? localIp;
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            localIp = addr.address;
            break;
          }
        }
        if (localIp != null) break;
      }

      _room = WatchPartyRoom(
        id: _myId,
        hostId: _myId,
        hostName: _myName,
        mediaTitle: mediaTitle,
        mediaUrl: mediaUrl,
        port: server.port,
        ipAddress: localIp ?? 'localhost',
      );

      _currentMediaUrl = mediaUrl;
      _currentMediaTitle = mediaTitle;

      _participants.add(
        WatchPartyParticipant(
          id: _myId,
          name: _myName,
          isHost: true,
          joinedAt: DateTime.now(),
        ),
      );

      // Listen for connections
      server.listen(_onClientConnected);

      _state = WatchPartyState.connected;
      notifyListeners();

      debugPrint('Watch party hosted at ${_room!.connectionString}');
      return true;
    } catch (e) {
      _state = WatchPartyState.error;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Join an existing watch party
  Future<bool> joinRoom(String host, int port) async {
    try {
      _state = WatchPartyState.joining;
      _error = null;
      notifyListeners();

      final socket = await Socket.connect(host, port);
      _clientSocket = socket;

      // Send join message
      _sendMessage(
        socket,
        WatchPartyMessage(
          type: WatchPartyMessageType.userJoined,
          senderId: _myId,
          senderName: _myName,
        ),
      );

      // Listen for messages
      socket.listen(
        (data) => _onDataReceived(data, socket),
        onError: (e) => _onError(e),
        onDone: () => _onDisconnected(),
      );

      _participants.add(
        WatchPartyParticipant(
          id: _myId,
          name: _myName,
          isHost: false,
          joinedAt: DateTime.now(),
        ),
      );

      _state = WatchPartyState.connected;
      notifyListeners();

      return true;
    } catch (e) {
      _state = WatchPartyState.error;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Leave the current room
  Future<void> leaveRoom() async {
    if (isHost) {
      // Notify all clients
      _broadcastMessage(
        WatchPartyMessage(
          type: WatchPartyMessageType.userLeft,
          senderId: _myId,
          senderName: _myName,
        ),
      );

      // Close all connections
      for (final client in _connectedClients) {
        await client.close();
      }
      _connectedClients.clear();

      await _serverSocket?.close();
      _serverSocket = null;
    } else {
      // Notify host
      if (_clientSocket != null) {
        _sendMessage(
          _clientSocket!,
          WatchPartyMessage(
            type: WatchPartyMessageType.userLeft,
            senderId: _myId,
            senderName: _myName,
          ),
        );
        await _clientSocket!.close();
      }
      _clientSocket = null;
    }

    _room = null;
    _participants.clear();
    _chatMessages.clear();
    _state = WatchPartyState.idle;
    notifyListeners();
  }

  /// Send play command (anyone can trigger)
  void play() {
    _isPlaying = true;
    final message = WatchPartyMessage(
      type: WatchPartyMessageType.play,
      senderId: _myId,
    );

    if (isHost) {
      _broadcastMessage(message);
    } else if (_clientSocket != null) {
      _sendMessage(_clientSocket!, message);
    }
    notifyListeners();
  }

  /// Send pause command (anyone can trigger)
  void pause() {
    _isPlaying = false;
    final message = WatchPartyMessage(
      type: WatchPartyMessageType.pause,
      senderId: _myId,
    );

    if (isHost) {
      _broadcastMessage(message);
    } else if (_clientSocket != null) {
      _sendMessage(_clientSocket!, message);
    }
    notifyListeners();
  }

  /// Send seek command
  void seek(Duration position) {
    // Anyone can seek in collaborative mode
    _currentPosition = position;
    if (isHost) {
      _broadcastMessage(
        WatchPartyMessage(
          type: WatchPartyMessageType.seek,
          senderId: _myId,
          payload: position.inMilliseconds,
        ),
      );
    } else if (_clientSocket != null) {
      _sendMessage(
        _clientSocket!,
        WatchPartyMessage(
          type: WatchPartyMessageType.seek,
          senderId: _myId,
          payload: position.inMilliseconds,
        ),
      );
    }
    notifyListeners();
  }

  /// Send speed change command
  void setSpeed(double speed) {
    _playbackSpeed = speed;
    final message = WatchPartyMessage(
      type: WatchPartyMessageType.speed,
      senderId: _myId,
      payload: speed,
    );

    if (isHost) {
      _broadcastMessage(message);
    } else if (_clientSocket != null) {
      _sendMessage(_clientSocket!, message);
    }
    notifyListeners();
  }

  /// Request sync from host (for clients who feel out of sync)
  void requestSync() {
    if (isHost || _clientSocket == null) return;

    _sendMessage(
      _clientSocket!,
      WatchPartyMessage(
        type: WatchPartyMessageType.requestSync,
        senderId: _myId,
      ),
    );
  }

  /// Sync current position (called periodically by host)
  void syncPosition(Duration position, bool isPlaying) {
    if (!isHost) return;

    _currentPosition = position;
    _isPlaying = isPlaying;

    _broadcastMessage(
      WatchPartyMessage(
        type: WatchPartyMessageType.sync,
        senderId: _myId,
        payload: {
          'position': position.inMilliseconds,
          'isPlaying': isPlaying,
          'speed': _playbackSpeed,
        },
      ),
    );
  }

  /// Send chat message
  void sendChatMessage(String message) {
    final chatMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: _myId,
      senderName: _myName,
      message: message,
      timestamp: DateTime.now(),
    );

    _chatMessages.add(chatMsg);

    final partyMessage = WatchPartyMessage(
      type: WatchPartyMessageType.chat,
      senderId: _myId,
      senderName: _myName,
      payload: message,
    );

    if (isHost) {
      _broadcastMessage(partyMessage);
    } else if (_clientSocket != null) {
      _sendMessage(_clientSocket!, partyMessage);
    }

    notifyListeners();
  }

  // Private methods

  void _onClientConnected(Socket client) {
    debugPrint('Client connected: ${client.remoteAddress}');
    _connectedClients.add(client);

    // Send room info
    _sendMessage(
      client,
      WatchPartyMessage(
        type: WatchPartyMessageType.roomInfo,
        senderId: _myId,
        senderName: _myName,
        payload: {
          'mediaUrl': _currentMediaUrl,
          'mediaTitle': _currentMediaTitle,
          'position': _currentPosition.inMilliseconds,
          'isPlaying': _isPlaying,
        },
      ),
    );

    client.listen(
      (data) => _onDataReceived(data, client),
      onError: (e) {
        debugPrint('Client error: $e');
        _connectedClients.remove(client);
      },
      onDone: () {
        debugPrint('Client disconnected');
        _connectedClients.remove(client);
      },
    );
  }

  void _onDataReceived(List<int> data, Socket socket) {
    try {
      final jsonStr = utf8.decode(data);
      final message = WatchPartyMessage.fromJson(jsonDecode(jsonStr));
      _handleMessage(message, socket);
    } catch (e) {
      debugPrint('Failed to parse message: $e');
    }
  }

  void _handleMessage(WatchPartyMessage message, Socket socket) {
    switch (message.type) {
      case WatchPartyMessageType.userJoined:
        _participants.add(
          WatchPartyParticipant(
            id: message.senderId,
            name: message.senderName ?? 'Unknown',
            isHost: false,
            joinedAt: DateTime.now(),
          ),
        );
        // Broadcast to other clients
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.userLeft:
        _participants.removeWhere((p) => p.id == message.senderId);
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.roomInfo:
        final payload = message.payload as Map<String, dynamic>;
        _currentMediaUrl = payload['mediaUrl'];
        _currentMediaTitle = payload['mediaTitle'];
        _currentPosition = Duration(milliseconds: payload['position'] ?? 0);
        _isPlaying = payload['isPlaying'] ?? false;

        _room = WatchPartyRoom(
          id: message.senderId,
          hostId: message.senderId,
          hostName: message.senderName ?? 'Host',
          mediaUrl: _currentMediaUrl,
          mediaTitle: _currentMediaTitle,
          port: 0,
        );

        if (_currentMediaUrl != null && _currentMediaTitle != null) {
          onMediaChanged?.call(_currentMediaUrl!, _currentMediaTitle!);
        }
        break;

      case WatchPartyMessageType.sync:
        if (!isHost) {
          final payload = message.payload as Map<String, dynamic>;
          _currentPosition = Duration(milliseconds: payload['position'] ?? 0);
          _isPlaying = payload['isPlaying'] ?? false;
          final newSpeed = (payload['speed'] as num?)?.toDouble();
          if (newSpeed != null && newSpeed != _playbackSpeed) {
            _playbackSpeed = newSpeed;
            onSpeedChanged?.call(_playbackSpeed);
          }
        }
        break;

      case WatchPartyMessageType.play:
        _isPlaying = true;
        onPlayPauseChanged?.call(true);
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.pause:
        _isPlaying = false;
        onPlayPauseChanged?.call(false);
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.seek:
        _currentPosition = Duration(milliseconds: message.payload as int);
        onSeek?.call(_currentPosition);
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
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
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.speed:
        _playbackSpeed = (message.payload as num).toDouble();
        onSpeedChanged?.call(_playbackSpeed);
        if (isHost) {
          _broadcastMessage(message, exclude: socket);
        }
        break;

      case WatchPartyMessageType.requestSync:
        // Host responds with current state
        if (isHost) {
          _sendMessage(
            socket,
            WatchPartyMessage(
              type: WatchPartyMessageType.sync,
              senderId: _myId,
              payload: {
                'position': _currentPosition.inMilliseconds,
                'isPlaying': _isPlaying,
                'speed': _playbackSpeed,
              },
            ),
          );
        }
        break;
    }
    notifyListeners();
  }

  void _sendMessage(Socket socket, WatchPartyMessage message) {
    try {
      socket.write(jsonEncode(message.toJson()));
    } catch (e) {
      debugPrint('Failed to send message: $e');
    }
  }

  void _broadcastMessage(WatchPartyMessage message, {Socket? exclude}) {
    for (final client in _connectedClients) {
      if (client != exclude) {
        _sendMessage(client, message);
      }
    }
  }

  void _onError(dynamic error) {
    _state = WatchPartyState.error;
    _error = error.toString();
    notifyListeners();
  }

  void _onDisconnected() {
    if (_state == WatchPartyState.connected) {
      _state = WatchPartyState.idle;
      _room = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    leaveRoom();
    super.dispose();
  }
}
