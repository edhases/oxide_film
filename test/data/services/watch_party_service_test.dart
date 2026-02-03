import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:oxide_film/data/services/services.dart';
import 'package:oxide_film/data/services/watch_party_service.dart';
// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart'; // For list equality if needed

// Manual Mocks
class MockWatchPartyBackend implements WatchPartyBackend {
  final List<String> log = [];

  Function(WatchPartyMessage)? onMessageCallback;
  bool isConnected = false;

  @override
  Future<void> connect({
    required String roomCode,
    required bool isHost,
    required String myId,
    required String myName,
    required Function(WatchPartyMessage) onMessage,
  }) async {
    log.add('connect(roomCode: $roomCode, isHost: $isHost)');
    onMessageCallback = onMessage;
    isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    log.add('disconnect');
    isConnected = false;
  }

  @override
  void sendBroadcast(WatchPartyMessage message) {
    log.add('sendBroadcast(${message.type})');
  }

  @override
  void sendMessage(String targetId, WatchPartyMessage message) {
    log.add('sendMessage($targetId, ${message.type})');
  }
}

class MockSettingsService extends Fake implements SettingsService {
  String _name = 'Test User';

  @override
  SettingsState get state => SettingsState(watchPartyName: _name);

  @override
  Future<void> setWatchPartyName(String name) async {
    _name = name;
  }
}

void main() {
  late WatchPartyService service;
  late MockWatchPartyBackend mockBackend;
  late MockSettingsService mockSettings;

  setUp(() {
    GetIt.I.reset();
    mockSettings = MockSettingsService();
    GetIt.I.registerSingleton<SettingsService>(mockSettings);

    mockBackend = MockWatchPartyBackend();

    // Inject factory to return our mock backend
    service = WatchPartyService(backendFactory: (_) => mockBackend);
  });

  group('WatchPartyService Connection', () {
    test('hostRoom connects using generated room code', () async {
      final result = await service.hostRoom(
        mediaUrl: 'http://test.com',
        mediaTitle: 'Test Movie',
      );

      expect(result, isTrue);
      expect(service.isHost, isTrue);
      expect(service.currentRoomCode, isNotNull);
      expect(service.state, WatchPartyState.connected);
      expect(
        mockBackend.log,
        contains(predicate((String s) => s.startsWith('connect(roomCode: '))),
      );
    });

    test('joinRoom connects using provided room code', () async {
      const roomCode = 'ABC123';
      final result = await service.joinRoom(roomCode);

      expect(result, isTrue);
      expect(service.isHost, isFalse);
      expect(service.currentRoomCode, equals(roomCode));
      expect(service.state, WatchPartyState.connected);
      expect(
        mockBackend.log,
        contains('connect(roomCode: $roomCode, isHost: false)'),
      );
    });
  });

  group('WatchPartyService Message Handling', () {
    test('Handles userJoined message', () async {
      await service.joinRoom('ROOM');

      // Simulate incoming message
      final msg = WatchPartyMessage(
        type: WatchPartyMessageType.userJoined,
        senderId: 'user2',
        senderName: 'Alice',
      );
      mockBackend.onMessageCallback?.call(msg);

      expect(service.participants.length, 2); // Me + Alice
      expect(service.participants.last.name, 'Alice');
    });

    test('Handles chat message', () async {
      await service.joinRoom('ROOM');

      final msg = WatchPartyMessage(
        type: WatchPartyMessageType.chat,
        senderId: 'user2',
        senderName: 'Alice',
        payload: 'Hello World',
      );
      mockBackend.onMessageCallback?.call(msg);

      expect(service.chatMessages.length, 1);
      expect(service.chatMessages.first.message, 'Hello World');
    });
  });

  group('WatchPartyService Sync Logic', () {
    // Callbacks to verify actions
    double? lastSpeed;
    Duration? lastSeek;
    SyncCorrectionMode? lastMode;

    setUp(() async {
      // Reset state for sync tests
      lastSpeed = null;
      lastSeek = null;
      lastMode = null;

      service.onSpeedChanged = (speed) => lastSpeed = speed;
      service.onSeek = (pos) => lastSeek = pos;
      service.onSyncStatusChanged = (mode, drift) => lastMode = mode;

      // Connect as client
      await service.joinRoom('ROOM');
    });

    void simulateSyncMessage({required int hostPosMs, required double speed}) {
      final msg = WatchPartyMessage(
        type: WatchPartyMessageType.sync,
        senderId: 'host_id',
        senderName: 'Host',
        payload: {
          'position': hostPosMs,
          'isPlaying': true,
          'speed': speed,
          'mediaUrl': 'url',
          'mediaTitle': 'title',
        },
        // Timestamp is roughly now, so network delay ~0 for tested logic
        timestamp: DateTime.now(),
      );
      mockBackend.onMessageCallback?.call(msg);
    }

    test('Drift < 2s (ignore threshold) - No Correction', () {
      // Host at 10s, Me at 10.5s (Drift 500ms)
      service.updateLocalPosition(const Duration(milliseconds: 10500));
      simulateSyncMessage(hostPosMs: 10000, speed: 1.0);

      expect(service.correctionMode, SyncCorrectionMode.none);
      expect(lastSpeed, isNull); // No speed change
      expect(lastSeek, isNull); // No seek
    });

    test('Drift 3s (behind) - Smooth Correction (Speed Up)', () {
      // Host at 13s, Me at 10s (Drift -3000ms)
      service.updateLocalPosition(const Duration(milliseconds: 10000));
      simulateSyncMessage(hostPosMs: 13000, speed: 1.0);

      expect(service.correctionMode, SyncCorrectionMode.speedUp);
      expect(lastSpeed, closeTo(1.1, 0.01)); // 1.1x speed
    });

    test('Drift 3s (ahead) - Smooth Correction (Slow Down)', () {
      // Host at 10s, Me at 13s (Drift +3000ms)
      service.updateLocalPosition(const Duration(milliseconds: 13000));
      simulateSyncMessage(hostPosMs: 10000, speed: 1.0);

      expect(service.correctionMode, SyncCorrectionMode.slowDown);
      expect(lastSpeed, closeTo(0.9, 0.01)); // 0.9x speed
    });

    test('Drift 7s (behind) - Fast Correction (Speed Up)', () {
      // Host at 17s, Me at 10s (Drift -7000ms)
      service.updateLocalPosition(const Duration(milliseconds: 10000));
      simulateSyncMessage(hostPosMs: 17000, speed: 1.0);

      expect(service.correctionMode, SyncCorrectionMode.speedUp);
      expect(lastSpeed, closeTo(1.2, 0.01)); // 1.2x speed
    });

    test('Drift 15s (behind) - Hard Seek', () {
      // Host at 25s, Me at 10s (Drift -15000ms)
      service.updateLocalPosition(const Duration(milliseconds: 10000));
      simulateSyncMessage(hostPosMs: 25000, speed: 1.0);

      expect(service.correctionMode, SyncCorrectionMode.hardSeek);
      expect(lastSeek, isNotNull);
      // Wait, calculation includes Network Delay. Sync payload has timestamp.
      // In simulateSync, we use DateTime.now().
      // _handleSync logic: networkDelay = DateTime.now().difference(hostTimestamp);
      // Since executed immediately, delay ~0.
      // adjustedHostPos = 25000 + 0 = 25000.
      expect(lastSeek!.inMilliseconds, 25000);
    });
  });
}
