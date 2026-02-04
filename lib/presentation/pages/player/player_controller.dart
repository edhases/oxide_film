import 'dart:async';
import 'package:flutter/painting.dart' show BoxFit;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/utils/logger.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/watch_party_service.dart';
import '../../../domain/entities/entities.dart';

/// Player state that can be observed by UI
class PlayerState {
  final bool isInitialized;
  final bool isBuffering;
  final bool isPlaying;
  final bool hasError;
  final String? errorMessage;
  final Duration position;
  final Duration duration;
  final double playbackSpeed;
  final BoxFit videoFit;
  final bool isFullscreen;
  final String currentUrl;
  final String? currentVoiceover;
  final StreamQuality? currentQuality;
  final List<VideoTrack> videoTracks;
  final VideoTrack? selectedVideoTrack;

  const PlayerState({
    this.isInitialized = false,
    this.isBuffering = true,
    this.isPlaying = false,
    this.hasError = false,
    this.errorMessage,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playbackSpeed = 1.0,
    this.videoFit = BoxFit.contain,
    this.isFullscreen = false,
    this.currentUrl = '',
    this.currentVoiceover,
    this.currentQuality,
    this.videoTracks = const [],
    this.selectedVideoTrack,
  });

  PlayerState copyWith({
    bool? isInitialized,
    bool? isBuffering,
    bool? isPlaying,
    bool? hasError,
    String? errorMessage,
    Duration? position,
    Duration? duration,
    double? playbackSpeed,
    BoxFit? videoFit,
    bool? isFullscreen,
    String? currentUrl,
    String? currentVoiceover,
    StreamQuality? currentQuality,
    List<VideoTrack>? videoTracks,
    VideoTrack? selectedVideoTrack,
    bool clearError = false,
  }) {
    return PlayerState(
      isInitialized: isInitialized ?? this.isInitialized,
      isBuffering: isBuffering ?? this.isBuffering,
      isPlaying: isPlaying ?? this.isPlaying,
      hasError: clearError ? false : (hasError ?? this.hasError),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      videoFit: videoFit ?? this.videoFit,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      currentUrl: currentUrl ?? this.currentUrl,
      currentVoiceover: currentVoiceover ?? this.currentVoiceover,
      currentQuality: currentQuality ?? this.currentQuality,
      videoTracks: videoTracks ?? this.videoTracks,
      selectedVideoTrack: selectedVideoTrack ?? this.selectedVideoTrack,
    );
  }
}

/// Controller that handles all player logic, separated from UI
///
/// Responsibilities:
/// - Media playback control (play, pause, seek)
/// - Stream/quality switching
/// - History saving
/// - Watch Party synchronization
/// - Fullscreen management
/// - WakeLock management
class PlayerController extends ChangeNotifier {
  static const String _tag = 'PlayerController';

  // Dependencies
  final HistoryService _historyService;
  final SettingsService _settingsService;
  final WatchPartyService _watchPartyService;

  // Media info
  final String initialUrl;
  final String? title;
  final String? mediaId;
  final String? providerId;
  final String? posterUrl;
  final List<StreamSource>? streams;

  // Internal state
  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription> _subscriptions = [];
  Timer? _saveProgressTimer;
  bool _isDisposed = false;

  // Observable state
  PlayerState _state = const PlayerState();
  PlayerState get state => _state;

  // Expose player and controller for Video widget
  Player get player => _player;
  VideoController get videoController => _videoController;

  // Video fit options
  static const List<BoxFit> fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const List<String> fitTooltips = [
    'Вписати',
    'Масштабувати (Cover)',
    'Розтягнути (Fill)',
  ];

  // Speed options
  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  PlayerController({
    required this.initialUrl,
    required HistoryService historyService,
    required SettingsService settingsService,
    required WatchPartyService watchPartyService,
    this.title,
    this.mediaId,
    this.providerId,
    this.posterUrl,
    this.streams,
  }) : _historyService = historyService,
       _settingsService = settingsService,
       _watchPartyService = watchPartyService {
    _initCurrentStreamInfo();
  }

  void _initCurrentStreamInfo() {
    var currentUrl = initialUrl;
    String? currentVoiceover;
    StreamQuality? currentQuality;

    if (streams != null && streams!.isNotEmpty) {
      var current = streams!.firstWhere(
        (s) => s.url == currentUrl,
        orElse: () => streams!.first,
      );

      // Check default quality setting
      final defaultQuality = _settingsService.state.defaultQuality;
      StreamQuality? targetQuality;

      switch (defaultQuality) {
        case DefaultQuality.q480p:
          targetQuality = StreamQuality.q480p;
          break;
        case DefaultQuality.q720p:
          targetQuality = StreamQuality.q720p;
          break;
        case DefaultQuality.q1080p:
          targetQuality = StreamQuality.q1080p;
          break;
        case DefaultQuality.q1440p:
          targetQuality = StreamQuality.q1440p;
          break;
        case DefaultQuality.auto:
          targetQuality = null;
          break;
      }

      if (targetQuality != null) {
        final preferredStream = streams!.firstWhere(
          (s) => s.quality == targetQuality,
          orElse: () => current,
        );
        if (preferredStream != current) {
          current = preferredStream;
          currentUrl = current.url;
        }
      }

      currentVoiceover = current.voiceover;
      currentQuality = current.quality;
    }

    _state = _state.copyWith(
      currentUrl: currentUrl,
      currentVoiceover: currentVoiceover,
      currentQuality: currentQuality,
    );
  }

  /// Initialize player and start playback
  Future<void> initialize() async {
    _player = Player();
    _videoController = VideoController(_player);

    _setupPlayerListeners();
    _setupWatchPartySync();
    _startProgressSaving();

    // Enable wakelock
    WakelockPlus.enable();

    // Auto fullscreen on Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _state = _state.copyWith(isFullscreen: true);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    // Open media
    await _player.open(Media(_state.currentUrl));

    // Resume from last position
    await _resumeLastPosition();

    // Initial sync for Watch Party client
    if (_watchPartyService.state == WatchPartyState.connected &&
        !_watchPartyService.isHost) {
      _watchPartyService.requestSync();
      if (_watchPartyService.isPlaying) {
        _player.play();
      }
    }

    _state = _state.copyWith(isInitialized: true);
    notifyListeners();
  }

  void _setupPlayerListeners() {
    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (_isDisposed) return;
        _state = _state.copyWith(isPlaying: playing);
        notifyListeners();

        // Watch Party sync
        if (_watchPartyService.state == WatchPartyState.connected) {
          if (playing && !_watchPartyService.isPlaying) {
            _watchPartyService.play();
          } else if (!playing && _watchPartyService.isPlaying) {
            _watchPartyService.pause();
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (_isDisposed) return;
        if (completed && _settingsService.state.autoPlayNext) {
          // Notify UI to pop with result
          _onPlaybackCompleted?.call();
        }
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (_isDisposed) return;
        _state = _state.copyWith(position: position);
        notifyListeners();

        if (_watchPartyService.state == WatchPartyState.connected) {
          _watchPartyService.updateLocalPosition(position);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (_isDisposed) return;
        _state = _state.copyWith(duration: duration);
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (_isDisposed) return;
        _state = _state.copyWith(isBuffering: buffering);
        notifyListeners();

        if (_watchPartyService.state == WatchPartyState.connected) {
          _watchPartyService.reportBuffering(buffering);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (_isDisposed) return;
        if (error.isNotEmpty) {
          Logger.w('Player error: $error', tag: _tag);
          if (!_player.state.playing && _state.position == Duration.zero) {
            _state = _state.copyWith(
              hasError: true,
              errorMessage: error,
              isBuffering: false,
            );
            notifyListeners();
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (_isDisposed) return;
        _state = _state.copyWith(videoTracks: tracks.video);
        notifyListeners();
      }),
    );

    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (_isDisposed) return;
        _state = _state.copyWith(selectedVideoTrack: track.video);
        notifyListeners();
      }),
    );
  }

  void _setupWatchPartySync() {
    if (_watchPartyService.state != WatchPartyState.connected) return;

    _watchPartyService.onPlayPauseChanged = (isPlaying) {
      if (_isDisposed) return;
      if (isPlaying) {
        if (_state.hasError) {
          Logger.i(
            'Auto-recovering from error due to Watch Party Play command',
            tag: _tag,
          );
          retryPlayback().then((_) => _player.play());
        } else if (!_player.state.playing) {
          _player.play();
        }
      } else if (!isPlaying && _player.state.playing) {
        _player.pause();
      }
    };

    _watchPartyService.onSeek = (position) {
      if (_isDisposed) return;
      if ((_player.state.position - position).abs() >
          const Duration(seconds: 2)) {
        _player.seek(position);
      }
    };

    _watchPartyService.onSpeedChanged = (speed) {
      if (_isDisposed) return;
      if ((_state.playbackSpeed - speed).abs() > 0.01) {
        _state = _state.copyWith(playbackSpeed: speed);
        _player.setRate(speed);
        notifyListeners();
      }
    };

    _watchPartyService.onSyncStatusChanged = (mode, driftMs) {
      if (_isDisposed) return;
      notifyListeners();
    };

    _watchPartyService.onQualityAdjustRequested = (delta) {
      if (_isDisposed) return;
      if (delta < 0) {
        tryReduceQuality();
      }
    };
  }

  void _startProgressSaving() {
    _saveProgressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  Future<void> _saveProgress() async {
    if (mediaId == null || providerId == null) return;
    if (_state.duration.inSeconds < 1) return;

    try {
      await _historyService.saveProgress(
        mediaId: mediaId!,
        providerId: providerId!,
        title: title ?? 'Невідомо',
        posterUrl: posterUrl,
        mediaType: 'movie',
        position: _state.position,
        duration: _state.duration,
        lastStreamUrl: _state.currentUrl,
        voiceover: _state.currentVoiceover,
      );
    } catch (e) {
      Logger.w('Failed to save progress: $e', tag: _tag);
    }
  }

  Future<void> _resumeLastPosition() async {
    if (!_settingsService.state.rememberPosition) return;
    if (mediaId == null || providerId == null) return;

    try {
      final lastPosition = await _historyService.getLastPosition(
        mediaId!,
        providerId!,
      );

      if (lastPosition != null && lastPosition.inSeconds > 5) {
        final expectedDuration = _state.duration.inSeconds > 0
            ? _state.duration
            : const Duration(minutes: 90);
        final progress = lastPosition.inSeconds / expectedDuration.inSeconds;

        if (progress < 0.95) {
          await _player.seek(lastPosition);
          _onPositionResumed?.call(lastPosition);
        }
      }
    } catch (e) {
      Logger.w('Failed to resume position: $e', tag: _tag);
    }
  }

  // =========================================================================
  // PUBLIC API
  // =========================================================================

  /// Callbacks for UI events
  VoidCallback? _onPlaybackCompleted;
  void Function(Duration)? _onPositionResumed;
  void Function(String)? _onQualityReduced;

  set onPlaybackCompleted(VoidCallback? callback) =>
      _onPlaybackCompleted = callback;
  set onPositionResumed(void Function(Duration)? callback) =>
      _onPositionResumed = callback;
  set onQualityReduced(void Function(String)? callback) =>
      _onQualityReduced = callback;

  void playOrPause() {
    final wasPlaying = _player.state.playing;
    _player.playOrPause();

    if (_watchPartyService.state == WatchPartyState.connected) {
      if (wasPlaying) {
        _watchPartyService.pause();
      } else {
        _watchPartyService.play();
      }
    }
  }

  void seek(Duration position) {
    _player.seek(position);
    if (_watchPartyService.state == WatchPartyState.connected) {
      _watchPartyService.seek(position);
    }
  }

  void seekForward([Duration duration = const Duration(seconds: 10)]) {
    seek(_state.position + duration);
  }

  void seekBackward([Duration duration = const Duration(seconds: 10)]) {
    seek(_state.position - duration);
  }

  void setSpeed(double speed) {
    Logger.d('Setting playback speed: $speed', tag: _tag);
    _state = _state.copyWith(playbackSpeed: speed);
    _player.setRate(speed);
    notifyListeners();

    if (_watchPartyService.state == WatchPartyState.connected) {
      if (_watchPartyService.playbackSpeed != speed) {
        _watchPartyService.setSpeed(speed);
      }
    }
  }

  void cycleFit() {
    final currentIndex = fits.indexOf(_state.videoFit);
    final nextIndex = (currentIndex + 1) % fits.length;
    _state = _state.copyWith(videoFit: fits[nextIndex]);
    notifyListeners();
  }

  Future<void> toggleFullscreen() async {
    Logger.d(
      'Toggle fullscreen: ${_state.isFullscreen ? "Exit" : "Enter"}',
      tag: _tag,
    );
    _state = _state.copyWith(isFullscreen: !_state.isFullscreen);
    notifyListeners();

    // Desktop
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      try {
        await windowManager.setFullScreen(_state.isFullscreen);
      } catch (e) {
        Logger.e('Failed to toggle window fullscreen', tag: _tag, error: e);
      }
    }

    // Mobile
    if (_state.isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> switchStream(StreamSource stream) async {
    if (stream.url == _state.currentUrl) return;

    final currentPosition = _state.position;
    _state = _state.copyWith(
      currentUrl: stream.url,
      currentVoiceover: stream.voiceover,
      currentQuality: stream.quality,
      isBuffering: true,
    );
    notifyListeners();

    await _player.open(Media(stream.url));
    await _player.seek(currentPosition);
  }

  Future<void> setVideoTrack(VideoTrack track) async {
    Logger.i(
      'Selecting video track: ${track.id} (${track.w}x${track.h})',
      tag: _tag,
    );
    await _player.setVideoTrack(track);
  }

  Future<void> retryPlayback() async {
    _state = _state.copyWith(clearError: true, isBuffering: true);
    notifyListeners();

    final positionToSeek = _state.position;
    await _player.open(Media(_state.currentUrl));
    if (positionToSeek > Duration.zero) {
      await _player.seek(positionToSeek);
    }
  }

  Future<void> switchStreamWithRetry(StreamSource stream) async {
    Logger.i('Switching stream with retry: ${stream.url}', tag: _tag);
    _state = _state.copyWith(
      clearError: true,
      isBuffering: true,
      currentUrl: stream.url,
      currentVoiceover: stream.voiceover,
      currentQuality: stream.quality,
    );
    notifyListeners();

    await _player.open(Media(stream.url));
  }

  /// Try to reduce quality when buffering issues detected
  void tryReduceQuality() {
    // Try HLS tracks first
    if (_state.videoTracks.length > 1 && _state.selectedVideoTrack != null) {
      final sortedTracks = List<VideoTrack>.from(_state.videoTracks)
        ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));

      final currentIndex = sortedTracks.indexOf(_state.selectedVideoTrack!);
      if (currentIndex < sortedTracks.length - 1) {
        final lowerTrack = sortedTracks[currentIndex + 1];
        Logger.i(
          'Reducing quality to ${lowerTrack.h}p due to buffering',
          tag: _tag,
        );
        _player.setVideoTrack(lowerTrack);
        _onQualityReduced?.call('${lowerTrack.h}p');
        return;
      }
    }

    // Try stream sources
    if (streams != null && streams!.length > 1) {
      final sortedStreams = List<StreamSource>.from(streams!)
        ..sort((a, b) => b.quality.sortOrder.compareTo(a.quality.sortOrder));

      final currentIndex = sortedStreams.indexWhere(
        (s) => s.url == _state.currentUrl,
      );
      if (currentIndex >= 0 && currentIndex < sortedStreams.length - 1) {
        final lowerStream = sortedStreams[currentIndex + 1];
        Logger.i(
          'Reducing quality to ${lowerStream.quality.displayName} due to buffering',
          tag: _tag,
        );
        switchStream(lowerStream);
        _onQualityReduced?.call(lowerStream.quality.displayName);
      }
    }
  }

  // =========================================================================
  // HELPER METHODS
  // =========================================================================

  bool hasMultipleQualities() {
    if (_state.videoTracks.length > 1) return true;
    if (streams == null || streams!.length <= 1) return false;
    final qualities = streams!.map((s) => s.quality).toSet();
    return qualities.length > 1;
  }

  bool hasMultipleVoiceovers() {
    if (streams == null || streams!.length <= 1) return false;
    final voiceovers = streams!
        .where((s) => s.voiceover != null)
        .map((s) => s.voiceover)
        .toSet();
    return voiceovers.length > 1;
  }

  String buildSubtitleText(String? fallbackSubtitle) {
    final parts = <String>[];
    if (_state.currentQuality != null) {
      if (_state.selectedVideoTrack != null &&
          _state.videoTracks.length > 1 &&
          _state.selectedVideoTrack!.w != null &&
          _state.selectedVideoTrack!.h != null) {
        parts.add('${_state.selectedVideoTrack!.h}p');
      } else {
        parts.add(_state.currentQuality!.displayName);
      }
    }
    if (_state.currentVoiceover != null) {
      parts.add(_state.currentVoiceover!);
    }
    if (parts.isEmpty && fallbackSubtitle != null) {
      return fallbackSubtitle;
    }
    return parts.join(' • ');
  }

  WatchPartyService get watchPartyService => _watchPartyService;
  SettingsService get settingsService => _settingsService;

  @override
  void dispose() {
    _isDisposed = true;

    // Cancel subscriptions
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Clear Watch Party callbacks
    _watchPartyService.onPlayPauseChanged = null;
    _watchPartyService.onSeek = null;
    _watchPartyService.onSpeedChanged = null;
    _watchPartyService.onSyncStatusChanged = null;
    _watchPartyService.onQualityAdjustRequested = null;

    // Disable wakelock
    WakelockPlus.disable();

    // Stop progress saving
    _saveProgressTimer?.cancel();
    _saveProgress();

    // Stop player
    _player.stop();
    _player.dispose();

    // Restore orientation on Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    super.dispose();
  }
}
