import 'dart:async';
import 'package:flutter/foundation.dart'; // Added
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart'; // Added window_manager

import '../../../core/utils/logger.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/watch_party_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';
import 'player_chat_overlay.dart'; // Added

/// Video player page with full controls
class PlayerPage extends StatefulWidget {
  final String url;
  final String? title;
  final String? subtitle;
  final List<StreamSource>? streams;
  final String? mediaId;
  final String? providerId;
  final String? posterUrl;

  const PlayerPage({
    super.key,
    required this.url,
    this.title,
    this.subtitle,
    this.streams,
    this.mediaId,
    this.providerId,
    this.posterUrl,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  final _focusNode = FocusNode();
  final _historyService = GetIt.instance<HistoryService>();
  final _settingsService = GetIt.instance<SettingsService>();
  final _watchPartyService = GetIt.instance<WatchPartyService>();
  Timer? _saveProgressTimer;
  final List<StreamSubscription> _subscriptions = [];
  bool _isDisposing = false; // Flag to prevent callbacks during dispose

  bool _isInitialized = false;
  bool _showControls = true;
  bool _isBuffering = true;
  bool _isFullscreen = false;
  bool _hasError = false;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Playback settings
  double _playbackSpeed = 1.0;
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // Scaling settings
  BoxFit _videoFit = BoxFit.contain;
  static const _fits = [BoxFit.contain, BoxFit.cover, BoxFit.fill];
  static const _fitIcons = [
    Icons.fit_screen,
    Icons.crop_free,
    Icons.aspect_ratio,
  ];
  static const _fitTooltips = [
    'Вписати',
    'Масштабувати (Cover)',
    'Розтягнути (Fill)',
  ];

  // Stream selection
  String _currentUrl = '';
  String? _currentVoiceover;
  StreamQuality? _currentQuality;

  // HLS Tracks
  List<VideoTrack> _videoTracks = [];
  VideoTrack? _selectedVideoTrack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _initCurrentStreamInfo();
    _initPlayer();
    _focusNode.requestFocus();
    _startProgressSaving();

    // Enable wakelock to keep screen on
    WakelockPlus.enable();

    // Auto-hide controls after delay
    _scheduleHideControls();

    // Auto fullscreen on Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _isFullscreen = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes to prevent crashes on hot restart
    if (state == AppLifecycleState.detached) {
      _cleanupPlayer();
    }
  }

  void _cleanupPlayer() {
    if (_isDisposing) return;
    _isDisposing = true;

    // Cancel all subscriptions first
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    // Stop playback before disposing
    _player.stop();
  }

  void _startProgressSaving() {
    // Save progress every 10 seconds
    _saveProgressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
  }

  Future<void> _saveProgress() async {
    if (widget.mediaId == null || widget.providerId == null) return;
    if (_duration.inSeconds < 1) return;

    try {
      await _historyService.saveProgress(
        mediaId: widget.mediaId!,
        providerId: widget.providerId!,
        title: widget.title ?? 'Невідомо',
        posterUrl: widget.posterUrl,
        mediaType: 'movie',
        position: _position,
        duration: _duration,
        lastStreamUrl: _currentUrl,
        voiceover: _currentVoiceover,
      );
    } catch (e) {
      Logger.w('Failed to save progress: $e', tag: 'Player');
    }
  }

  void _initCurrentStreamInfo() {
    if (widget.streams != null && widget.streams!.isNotEmpty) {
      // 1. Try to find stream matching widget.url (initial - user's choice)
      var current = widget.streams!.firstWhere(
        (s) => s.url == _currentUrl,
        orElse: () => widget.streams!.first,
      );

      // Save the user-selected voiceover to preserve it
      final selectedVoiceover = current.voiceover;

      // 2. Check if we should override with Default Quality setting
      // BUT only within the SAME voiceover to preserve user's choice
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
        // Find preferred quality ONLY within the same voiceover
        final preferredStream = widget.streams!.firstWhere(
          (s) => s.quality == targetQuality && s.voiceover == selectedVoiceover,
          orElse: () => current,
        );

        // If we found a stream with the preferred quality, use it
        if (preferredStream != current) {
          current = preferredStream;
          _currentUrl = current.url;
        }
      }

      _currentVoiceover = current.voiceover;
      _currentQuality = current.quality;
    }
  }

  Future<void> _resumeLastPosition() async {
    // Check setting first!
    if (!_settingsService.state.rememberPosition) return;

    if (widget.mediaId == null || widget.providerId == null) return;

    try {
      final lastPosition = await _historyService.getLastPosition(
        widget.mediaId!,
        widget.providerId!,
      );

      if (lastPosition != null && lastPosition.inSeconds > 5) {
        // Don't resume if almost finished (>95%)
        final expectedDuration = _duration.inSeconds > 0
            ? _duration
            : const Duration(minutes: 90); // Assume 90 min if unknown
        final progress = lastPosition.inSeconds / expectedDuration.inSeconds;

        if (progress < 0.95) {
          await _player.seek(lastPosition);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Продовжено з ${_formatDuration(lastPosition)}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      Logger.w('Failed to resume position: $e', tag: 'Player');
    }
  }

  Future<void> _initPlayer() async {
    _player = Player();
    _controller = VideoController(_player);

    // Listen to player state
    // Track playing state to avoid unnecessary rebuilds
    bool lastPlayingState = false;

    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (!mounted || _isDisposing) return;

        // Only update if state actually changed
        if (lastPlayingState != playing) {
          lastPlayingState = playing;
          setState(() {});
        }

        // Watch Party: Host broadcasts state
        if (_watchPartyService.state == WatchPartyState.connected) {
          if (playing) {
            // Avoid loops if we just received a command
            if (!_watchPartyService.isPlaying) _watchPartyService.play();
          } else {
            if (_watchPartyService.isPlaying) _watchPartyService.pause();
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (!mounted || _isDisposing) return;
        if (completed) {
          if (_settingsService.state.autoPlayNext) {
            context.pop(true);
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (!mounted || _isDisposing) return;

        // Optimize: only update UI if position changed by at least 250ms
        // This prevents excessive rebuilds that cause lag
        final diff = (position - _position).abs();
        if (diff >= const Duration(milliseconds: 250) ||
            _position == Duration.zero) {
          setState(() => _position = position);
        } else {
          // Still update the internal value for accuracy
          _position = position;
        }

        // Update local position in watch party service for both host and client
        // This allows proper drift calculation on the client side
        if (_watchPartyService.state == WatchPartyState.connected) {
          _watchPartyService.updateLocalPosition(position);
        }
      }),
    );

    // Watch Party: Sync position periodically or on significant change?
    // Usually seek is enough, but periodic sync helps drift.
    // For now, let's rely on seek events from UI, but we can't catch "seek" event easily from this stream
    // without diffing position.
    // Better to handle seek in the UI controls or check sudden jumps.

    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (!mounted || _isDisposing) return;
        // Only update if duration actually changed
        if (_duration != duration) {
          setState(() => _duration = duration);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (!mounted || _isDisposing) return;
        // Only update if buffering state changed
        if (_isBuffering != buffering) {
          setState(() => _isBuffering = buffering);
        }
        // Report buffering to watch party for adaptive quality
        if (_watchPartyService.state == WatchPartyState.connected) {
          _watchPartyService.reportBuffering(buffering);
        }
      }),
    );

    // Listen to player errors
    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (!mounted || _isDisposing) return;
        if (error.isNotEmpty) {
          Logger.w('Player error: $error', tag: 'Player');
          // Only show error UI if playback actually stopped
          // Some errors like network timeouts don't stop playback
          if (_player.state.playing == false && _position == Duration.zero) {
            setState(() {
              _hasError = true;
              _errorMessage = error;
              _isBuffering = false;
            });
          }
        }
      }),
    );

    // Listen to tracks (HLS)
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (!mounted || _isDisposing) return;
        setState(() {
          _videoTracks = tracks.video;
        });
      }),
    );

    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (!mounted || _isDisposing) return;
        setState(() {
          _selectedVideoTrack = track.video;
        });
      }),
    );

    // Open media and start playing
    await _player.open(Media(_currentUrl));

    // Resume from last position if available
    await _resumeLastPosition();

    // Watch Party: Sync
    if (_watchPartyService.state == WatchPartyState.connected) {
      _watchPartyService.onPlayPauseChanged = (isPlaying) {
        if (!mounted || _isDisposing) return;
        if (isPlaying) {
          if (_hasError) {
            Logger.i(
              'Auto-recovering from error due to Watch Party Play command',
              tag: 'Player',
            );
            _retryPlayback().then((_) {
              if (mounted) _player.play();
            });
          } else if (!_player.state.playing) {
            _player.play();
          }
        } else if (!isPlaying && _player.state.playing) {
          _player.pause();
        }
      };

      _watchPartyService.onSeek = (position) {
        if (!mounted || _isDisposing) return;
        if ((_player.state.position - position).abs() >
            const Duration(seconds: 2)) {
          _player.seek(position);
        }
      };

      _watchPartyService.onSpeedChanged = (speed) {
        if (!mounted || _isDisposing) return;
        // Only apply if it's different (avoids loops)
        if ((_playbackSpeed - speed).abs() > 0.01) {
          setState(() => _playbackSpeed = speed);
          _player.setRate(speed);
        }
      };

      // Sync status updates
      _watchPartyService.onSyncStatusChanged = (mode, driftMs) {
        if (!mounted || _isDisposing) return;
        setState(() {}); // Trigger rebuild to update sync indicator
      };

      // Adaptive quality callback
      _watchPartyService.onQualityAdjustRequested = (delta) {
        if (!mounted || _isDisposing) return;
        if (delta < 0) {
          _tryReduceQuality();
        }
      };

      // Listen for new chat messages when chat is closed
      _watchPartyService.addListener(_onWatchPartyUpdate);

      // Initial sync if we are client
      if (!_watchPartyService.isHost) {
        _watchPartyService.requestSync();
        if (_watchPartyService.isPlaying) {
          _player.play();
        }
      }
    }

    if (mounted) {
      setState(() => _isInitialized = true);
    }
  }

  void _onWatchPartyUpdate() {
    if (!mounted) return;
    // Track new messages when chat is closed
    final totalMessages = _watchPartyService.chatMessages.length;
    if (!_showChat && totalMessages > _lastSeenMessageCount) {
      setState(() {
        _newChatMessages = totalMessages - _lastSeenMessageCount;
      });
    } else {
      setState(() {}); // Just refresh UI for sync status etc.
    }
  }

  /// Try to reduce quality when buffering issues detected
  void _tryReduceQuality() {
    // Try HLS tracks first
    if (_videoTracks.length > 1 && _selectedVideoTrack != null) {
      final sortedTracks = List<VideoTrack>.from(_videoTracks)
        ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));

      final currentIndex = sortedTracks.indexOf(_selectedVideoTrack!);
      if (currentIndex < sortedTracks.length - 1) {
        final lowerTrack = sortedTracks[currentIndex + 1];
        Logger.i(
          'Watch Party: Reducing quality to ${lowerTrack.h}p due to buffering',
          tag: 'Player',
        );
        _player.setVideoTrack(lowerTrack);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Якість знижено до ${lowerTrack.h}p'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    // Try stream sources
    if (widget.streams != null && widget.streams!.length > 1) {
      final sortedStreams = List<StreamSource>.from(widget.streams!)
        ..sort((a, b) => b.quality.sortOrder.compareTo(a.quality.sortOrder));

      final currentIndex = sortedStreams.indexWhere(
        (s) => s.url == _currentUrl,
      );
      if (currentIndex >= 0 && currentIndex < sortedStreams.length - 1) {
        final lowerStream = sortedStreams[currentIndex + 1];
        Logger.i(
          'Watch Party: Reducing quality to ${lowerStream.quality.displayName} due to buffering',
          tag: 'Player',
        );
        _switchStream(lowerStream);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Якість знижено до ${lowerStream.quality.displayName}',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _switchStream(StreamSource stream) async {
    if (stream.url == _currentUrl) return;

    final currentPosition = _position;
    setState(() {
      _currentUrl = stream.url;
      _currentVoiceover = stream.voiceover;
      _currentQuality = stream.quality;
      _isBuffering = true;
    });

    await _player.open(Media(stream.url));
    await _player.seek(currentPosition);
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _player.state.playing) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupPlayer();

    _watchPartyService.onPlayPauseChanged = null;
    _watchPartyService.onSeek = null;
    _watchPartyService.onSpeedChanged = null;
    _watchPartyService.onSyncStatusChanged = null;
    _watchPartyService.onQualityAdjustRequested = null;
    _watchPartyService.removeListener(_onWatchPartyUpdate);
    WakelockPlus.disable(); // Disable wakelock
    _saveProgressTimer?.cancel();
    _saveProgress(); // Save final progress
    _focusNode.dispose();
    _player.dispose();

    // Restore orientation and exit fullscreen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Desktop: exit fullscreen if still in it
    if (_isFullscreen &&
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      // Fire and forget - can't await in dispose
      windowManager.setFullScreen(false).catchError((_) {});
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: MouseRegion(
          onHover: (_) {
            if (!_showControls) {
              setState(() => _showControls = true);
              _scheduleHideControls();
            }
          },
          child: GestureDetector(
            onTap: _toggleControls,
            onDoubleTap: _toggleFullscreen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video - wrapped in RepaintBoundary to isolate repaints
                if (_isInitialized && !_hasError)
                  RepaintBoundary(
                    child: Video(
                      controller: _controller,
                      fit: _videoFit,
                      fill: Colors.black,
                      controls: NoVideoControls,
                    ),
                  )
                else if (_hasError)
                  _buildErrorWidget()
                else
                  const Center(child: CircularProgressIndicator()),

                // Buffering indicator
                if (_isBuffering && _isInitialized && !_hasError)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                // Controls overlay
                if (!_hasError)
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: _showControls ? _buildControls() : const SizedBox(),
                  ),

                // Chat Overlay (Right side)
                if (_showChat)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: PlayerChatOverlay(
                      service: _watchPartyService,
                      onClose: _toggleChatOverlay,
                    ),
                  ),

                // Persistent Watch Party indicators (always visible when in party)
                if (_watchPartyService.state == WatchPartyState.connected)
                  _buildWatchPartyFloatingUI(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build floating UI elements for Watch Party (always visible)
  Widget _buildWatchPartyFloatingUI() {
    return Positioned(
      right: _showChat ? 316 : 16,
      bottom: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sync status indicator
          _buildSyncIndicator(),
          const SizedBox(height: 8),
          // Chat FAB
          _buildChatFAB(),
        ],
      ),
    );
  }

  /// Sync status indicator - minimal icon only
  Widget _buildSyncIndicator() {
    final mode = _watchPartyService.correctionMode;

    if (_watchPartyService.isHost) {
      // Host shows participant count as icon with badge
      return Tooltip(
        message: '${_watchPartyService.participants.length} учасників',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Badge(
            label: Text('${_watchPartyService.participants.length}'),
            backgroundColor: Colors.green,
            child: const Icon(Icons.groups, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    // Guest shows sync status as icon only
    Color iconColor;
    IconData icon;
    String tooltip;

    switch (mode) {
      case SyncCorrectionMode.none:
        iconColor = Colors.green;
        icon = Icons.check_circle;
        tooltip = 'Синхронізовано';
        break;
      case SyncCorrectionMode.speedUp:
        iconColor = Colors.orange;
        icon = Icons.fast_forward;
        tooltip = 'Наздоганяємо...';
        break;
      case SyncCorrectionMode.slowDown:
        iconColor = Colors.orange;
        icon = Icons.slow_motion_video;
        tooltip = 'Уповільнюємо...';
        break;
      case SyncCorrectionMode.hardSeek:
        iconColor = Colors.red;
        icon = Icons.sync_problem;
        tooltip = 'Пересинхронізація...';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
    );
  }

  /// Chat FAB (always visible during Watch Party)
  Widget _buildChatFAB() {
    return FloatingActionButton(
      heroTag: 'chat_fab',
      mini: true,
      backgroundColor: _showChat
          ? AppTheme.primaryColor
          : Colors.black.withValues(alpha: 0.7),
      onPressed: _toggleChatOverlay,
      child: Badge(
        isLabelVisible: _newChatMessages > 0 && !_showChat,
        label: Text('$_newChatMessages'),
        child: Icon(
          _showChat ? Icons.chat : Icons.chat_bubble_outline,
          color: Colors.white,
        ),
      ),
    );
  }

  bool _showChat = false;
  int _newChatMessages = 0; // Track unread messages
  int _lastSeenMessageCount = 0; // Track last seen message count

  void _toggleChatOverlay() {
    setState(() {
      _showChat = !_showChat;
      if (_showChat) {
        _newChatMessages = 0; // Clear unread count when opening
        _lastSeenMessageCount = _watchPartyService.chatMessages.length;
      }
    });
  }

  void _cycleFit() {
    setState(() {
      final currentIndex = _fits.indexOf(_videoFit);
      final nextIndex = (currentIndex + 1) % _fits.length;
      _videoFit = _fits[nextIndex];
      Logger.d('Changed video fit to: $_videoFit', tag: 'Player');

      // Add feedback
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Масштаб: ${_fitTooltips[nextIndex]}'),
          duration: const Duration(seconds: 1),
        ),
      );
    });
  }

  void _toggleControls() {
    if (_showChat) {
      // If tapping outside chat while it's open, maybe close it?
      // Or rely on close button.
    }

    Logger.d(
      'Toggle controls: ${_showControls ? "Hide" : "Show"}',
      tag: 'Player',
    );
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHideControls();
    }
  }

  Widget _buildErrorWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Помилка відтворення',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Не вдалося завантажити відео',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _retryPlayback,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Спробувати знову'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Назад'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                  ),
                ],
              ),
              // Show alternative streams if available
              if (widget.streams != null && widget.streams!.length > 1) ...[
                const SizedBox(height: 24),
                Text(
                  'Або спробуйте інший потік:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.streams!
                      .where((s) => s.url != _currentUrl)
                      .take(3)
                      .map(
                        (stream) => ActionChip(
                          label: Text(
                            stream.voiceover ?? stream.quality.displayName,
                          ),
                          onPressed: () => _switchStreamWithRetry(stream),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _retryPlayback() async {
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
    });
    // Save position before retrying
    final positionToSeek = _position;
    await _player.open(Media(_currentUrl));
    if (positionToSeek > Duration.zero) {
      await _player.seek(positionToSeek);
    }
  }

  Future<void> _switchStreamWithRetry(StreamSource stream) async {
    Logger.i('Switching stream with retry: ${stream.url}', tag: 'Player');
    setState(() {
      _hasError = false;
      _errorMessage = null;
      _isBuffering = true;
      _currentUrl = stream.url;
      _currentVoiceover = stream.voiceover;
      _currentQuality = stream.quality;
    });
    await _player.open(Media(stream.url));
  }

  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.8),
          ],
          stops: const [0.0, 0.15, 0.75, 1.0],
        ),
      ),
      child: Column(
        children: [_buildTopBar(), const Spacer(), _buildBottomControls()],
      ),
    );
  }

  Widget _buildTopBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = context.isCompact;
    final isMobile = context.isMobile;
    // Use compact mode for screens narrower than 500px to prevent overflow
    final useCompactControls = isCompact || screenWidth < 500;
    final padding = useCompactControls ? 6.0 : (isMobile ? 10.0 : 16.0);
    final iconSize = useCompactControls ? 20.0 : (isMobile ? 22.0 : 28.0);
    final titleFontSize = useCompactControls ? 13.0 : (isMobile ? 15.0 : 18.0);
    final subtitleFontSize = useCompactControls
        ? 10.0
        : (isMobile ? 11.0 : 14.0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: padding,
          vertical: padding / 2,
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white, size: iconSize),
              onPressed: () => context.pop(),
              padding: EdgeInsets.all(useCompactControls ? 4 : 8),
              constraints: BoxConstraints(
                minWidth: useCompactControls ? 32 : 40,
                minHeight: useCompactControls ? 32 : 40,
              ),
            ),
            SizedBox(width: useCompactControls ? 4 : 10),

            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.title != null)
                    Text(
                      widget.title!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Show current quality/voiceover
                  if (!useCompactControls)
                    Text(
                      _buildSubtitleText(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: subtitleFontSize,
                      ),
                    ),
                ],
              ),
            ),

            // On compact screens, show fewer buttons
            if (useCompactControls) ...[
              // Combined settings menu for compact screens
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.white,
                  size: iconSize,
                ),
                tooltip: 'Меню',
                itemBuilder: (context) => [
                  if (_hasMultipleQualities())
                    const PopupMenuItem(
                      value: 'quality',
                      child: ListTile(
                        leading: Icon(Icons.high_quality),
                        title: Text('Якість'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (_hasMultipleVoiceovers())
                    const PopupMenuItem(
                      value: 'voice',
                      child: ListTile(
                        leading: Icon(Icons.record_voice_over),
                        title: Text('Озвучка'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'speed',
                    child: ListTile(
                      leading: Icon(Icons.speed),
                      title: Text('Швидкість'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('Налаштування'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'fit',
                    child: ListTile(
                      leading: Icon(_fitIcons[_fits.indexOf(_videoFit)]),
                      title: Text(_fitTooltips[_fits.indexOf(_videoFit)]),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
                onSelected: (value) {
                  switch (value) {
                    case 'quality':
                      _showQualitySheet();
                      break;
                    case 'voice':
                      _showVoiceoverSheet();
                      break;
                    case 'speed':
                      _showSpeedSheet();
                      break;
                    case 'settings':
                      _showSettingsSheet();
                      break;
                    case 'fit':
                      _cycleFit();
                      break;
                  }
                },
              ),
            ] else ...[
              // Full controls for larger screens
              // Quality selector (if multiple streams/tracks available)
              if (_hasMultipleQualities())
                PopupMenuButton<dynamic>(
                  icon: Icon(
                    Icons.high_quality,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  tooltip: 'Якість',
                  itemBuilder: (context) => _buildQualityMenuItems(),
                  onSelected: (value) async {
                    if (value is VideoTrack) {
                      Logger.i(
                        'Selecting video track: ${value.id} (${value.w}x${value.h})',
                        tag: 'Player',
                      );
                      await _player.setVideoTrack(value);
                    } else if (value is StreamSource) {
                      Logger.i(
                        'Selecting stream source: ${value.quality.displayName}',
                        tag: 'Player',
                      );
                      _switchStream(value);
                    }
                  },
                ),

              // Voiceover selector (if multiple voiceovers available)
              if (_hasMultipleVoiceovers())
                PopupMenuButton<StreamSource>(
                  icon: Icon(
                    Icons.record_voice_over,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  tooltip: 'Озвучка',
                  onSelected: _switchStream,
                  itemBuilder: (context) => _buildVoiceoverMenuItems(),
                ),

              // Speed selector
              PopupMenuButton<double>(
                icon: Icon(Icons.speed, color: Colors.white, size: iconSize),
                tooltip: 'Швидкість',
                onSelected: _setSpeed,
                itemBuilder: (context) => _speeds.map((speed) {
                  return PopupMenuItem(
                    value: speed,
                    child: Row(
                      children: [
                        if (speed == _playbackSpeed)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text('${speed}x'),
                      ],
                    ),
                  );
                }).toList(),
              ),

              // Settings button
              IconButton(
                icon: Icon(Icons.settings, color: Colors.white, size: iconSize),
                tooltip: 'Налаштування',
                onPressed: _showSettingsSheet,
              ),

              // Chat toggle (Watch Party only)
              if (_watchPartyService.state == WatchPartyState.connected)
                IconButton(
                  icon: Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  tooltip: 'Чат',
                  onPressed: _toggleChatOverlay,
                ),

              // Scaling toggle
              IconButton(
                icon: Icon(
                  _fitIcons[_fits.indexOf(_videoFit)],
                  color: Colors.white,
                  size: iconSize,
                ),
                tooltip: _fitTooltips[_fits.indexOf(_videoFit)],
                onPressed: _cycleFit,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Bottom sheet versions for compact screens
  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Якість',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._buildQualityMenuItems().map(
              (item) => ListTile(
                title: (item.child as Row).children.last,
                leading: (item.child as Row).children.first,
                onTap: () {
                  Navigator.pop(context);
                  if (item.value is VideoTrack) {
                    _player.setVideoTrack(item.value as VideoTrack);
                  } else if (item.value is StreamSource) {
                    _switchStream(item.value as StreamSource);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showVoiceoverSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Озвучка',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._buildVoiceoverMenuItems().map(
              (item) => ListTile(
                title: (item.child as Row).children.last,
                leading: (item.child as Row).children.first,
                onTap: () {
                  Navigator.pop(context);
                  _switchStream(item.value!);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Швидкість',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ..._speeds.map(
              (speed) => ListTile(
                title: Text('${speed}x'),
                leading: speed == _playbackSpeed
                    ? const Icon(Icons.check, color: AppTheme.primaryColor)
                    : const SizedBox(width: 24),
                onTap: () {
                  Navigator.pop(context);
                  _setSpeed(speed);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final isCompact = context.isCompact;
    final isMobile = context.isMobile;
    final padding = ResponsiveUtils.getPlayerBottomPadding(context);
    final iconSize = isCompact ? 24.0 : (isMobile ? 28.0 : 28.0);
    final playPauseSize = isCompact ? 40.0 : (isMobile ? 44.0 : 48.0);
    final fontSize = isCompact ? 11.0 : 13.0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            SliderTheme(
              data: SliderThemeData(
                trackHeight: isCompact ? 3 : 4,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: isCompact ? 6 : 8,
                ),
                overlayShape: RoundSliderOverlayShape(
                  overlayRadius: isCompact ? 12 : 16,
                ),
                activeTrackColor: AppTheme.primaryColor,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                thumbColor: AppTheme.primaryColor,
              ),
              child: Slider(
                value: _duration.inMilliseconds > 0
                    ? (_position.inMilliseconds / _duration.inMilliseconds)
                          .clamp(0.0, 1.0)
                    : 0,
                onChanged: (value) {
                  final seekTo = Duration(
                    milliseconds: (value * _duration.inMilliseconds).toInt(),
                  );
                  _player.seek(seekTo);
                  if (_watchPartyService.state == WatchPartyState.connected) {
                    _watchPartyService.seek(seekTo);
                  }
                },
              ),
            ),

            // Time and controls row
            Row(
              children: [
                // Time
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: TextStyle(color: Colors.white, fontSize: fontSize),
                ),

                const Spacer(),

                // Rewind 10s
                IconButton(
                  iconSize: iconSize,
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  padding: EdgeInsets.all(isCompact ? 4 : 8),
                  constraints: BoxConstraints(
                    minWidth: isCompact ? 36 : 44,
                    minHeight: isCompact ? 36 : 44,
                  ),
                  onPressed: () {
                    final newPos = _position - const Duration(seconds: 10);
                    _player.seek(newPos);
                    if (_watchPartyService.state == WatchPartyState.connected) {
                      _watchPartyService.seek(newPos);
                    }
                  },
                ),

                // Play/Pause
                IconButton(
                  iconSize: playPauseSize,
                  icon: Icon(
                    _player.state.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  padding: EdgeInsets.all(isCompact ? 2 : 4),
                  onPressed: () {
                    Logger.d('Play/Pause toggle', tag: 'Player');
                    final wasPlaying = _player.state.playing;
                    _player.playOrPause();

                    if (_watchPartyService.state == WatchPartyState.connected) {
                      if (wasPlaying) {
                        _watchPartyService.pause();
                      } else {
                        _watchPartyService.play();
                      }
                    }
                  },
                ),

                // Forward 10s
                IconButton(
                  iconSize: iconSize,
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  padding: EdgeInsets.all(isCompact ? 4 : 8),
                  constraints: BoxConstraints(
                    minWidth: isCompact ? 36 : 44,
                    minHeight: isCompact ? 36 : 44,
                  ),
                  onPressed: () {
                    final newPos = _position + const Duration(seconds: 10);
                    _player.seek(newPos);
                    if (_watchPartyService.state == WatchPartyState.connected) {
                      _watchPartyService.seek(newPos);
                    }
                  },
                ),

                const Spacer(),

                // Speed indicator
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 6 : 8,
                    vertical: isCompact ? 2 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: TextStyle(color: Colors.white, fontSize: fontSize),
                  ),
                ),

                SizedBox(width: isCompact ? 4 : 8),

                // Fullscreen
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  padding: EdgeInsets.all(isCompact ? 4 : 8),
                  constraints: BoxConstraints(
                    minWidth: isCompact ? 36 : 44,
                    minHeight: isCompact ? 36 : 44,
                  ),
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _setSpeed(double speed) {
    Logger.d('Setting playback speed: $speed', tag: 'Player');
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);

    // Broadcast if connected and we are the source (this check is tricky for receive vs send)
    // To avoid loops: changing speed via callback -> setSpeed -> broadcast -> callback -> setSpeed...
    // We need to differentiate user action vs sync action.
    // Simpler: Just broadcast. The receiver will set speed. The service should filter echoes?
    // Supabase broadcasts are received by sender too?
    // Service filters `if (message.senderId == myId) return;`. So it is safe.
    if (_watchPartyService.state == WatchPartyState.connected) {
      // Only broadcast if the value implies a change that needs syncing
      // Actually `_setSpeed` is called by `onSpeedChanged` wrapper too.
      // We should check if the new speed matches what service thinks or if we are originating it.
      // Let's add a `fromSync` param? Or just check service speed?
      if (_watchPartyService.playbackSpeed != speed) {
        _watchPartyService.setSpeed(speed);
      }
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_isDisposing) return;

    final newFullscreen = !_isFullscreen;
    Logger.d(
      'Toggle fullscreen: ${newFullscreen ? "Enter" : "Exit"}',
      tag: 'Player',
    );

    // Desktop: use window_manager FIRST, then update state
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      try {
        await windowManager.setFullScreen(newFullscreen);
        // Small delay to let window resize complete
        await Future<void>.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        Logger.e('Failed to toggle window fullscreen', tag: 'Player', error: e);
        return; // Don't update state if failed
      }
    }

    if (!mounted || _isDisposing) return;
    setState(() => _isFullscreen = newFullscreen);

    // Mobile/General: use SystemChrome
    if (newFullscreen) {
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

  // ===========================================================================
  // QUALITY & VOICEOVER SELECTORS
  // ===========================================================================

  String _buildSubtitleText() {
    final parts = <String>[];
    if (_currentQuality != null) {
      // If using native HLS tracks, show resolution from track
      if (_selectedVideoTrack != null &&
          _videoTracks.length > 1 &&
          _selectedVideoTrack!.w != null &&
          _selectedVideoTrack!.h != null) {
        parts.add('${_selectedVideoTrack!.h}p');
      } else {
        parts.add(_currentQuality!.displayName);
      }
    }
    if (_currentVoiceover != null) {
      parts.add(_currentVoiceover!);
    }
    if (parts.isEmpty && widget.subtitle != null) {
      return widget.subtitle!;
    }
    return parts.join(' • ');
  }

  bool _hasMultipleQualities() {
    // Check HLS tracks first
    if (_videoTracks.length > 1) return true;

    if (widget.streams == null || widget.streams!.length <= 1) return false;
    final qualities = widget.streams!.map((s) => s.quality).toSet();
    return qualities.length > 1;
  }

  bool _hasMultipleVoiceovers() {
    if (widget.streams == null || widget.streams!.length <= 1) return false;
    final voiceovers = widget.streams!
        .where((s) => s.voiceover != null)
        .map((s) => s.voiceover)
        .toSet();
    return voiceovers.length > 1;
  }

  List<PopupMenuItem<dynamic>> _buildQualityMenuItems() {
    // 1. If we have native HLS video tracks (more than just auto), use them
    if (_videoTracks.length > 1) {
      // Sort tracks by resolution (descending)
      final sortedTracks = List<VideoTrack>.from(_videoTracks)
        ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));

      // Filter out duplicate "auto" tracks
      final seenLabels = <String>{};
      final uniqueTracks = <VideoTrack>[];
      for (final track in sortedTracks) {
        final isAuto =
            track.id == 'auto' || (track.w == null && track.h == null);
        final label = isAuto ? 'Авто' : '${track.h}p';
        if (!seenLabels.contains(label)) {
          seenLabels.add(label);
          uniqueTracks.add(track);
        }
      }

      return uniqueTracks.map((track) {
        final isSelected = track == _selectedVideoTrack;
        final isAuto =
            track.id == 'auto' || (track.w == null && track.h == null);

        String label;
        if (isAuto) {
          label = 'Авто';
        } else {
          label = '${track.h}p';
          if (track.bitrate != null) {
            final bitrate = (track.bitrate! / 1000000).toStringAsFixed(1);
            label += ' ($bitrate Mbps)';
          }
        }

        return PopupMenuItem<dynamic>(
          value: track,
          child: Row(
            children: [
              if (isSelected)
                const Icon(Icons.check, size: 18, color: AppTheme.primaryColor)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        );
      }).toList();
    }

    // 2. Fallback to StreamSource switching
    if (widget.streams == null) return [];

    // Group by quality, prefer current voiceover
    // Skip unknown quality if there are other qualities available
    final qualities = <StreamQuality, StreamSource>{};
    final hasKnownQuality = widget.streams!.any(
      (s) => s.quality != StreamQuality.unknown,
    );

    for (final stream in widget.streams!) {
      // Skip unknown if we have known qualities (avoid "Авто" when not needed)
      if (stream.quality == StreamQuality.unknown && hasKnownQuality) continue;

      if (!qualities.containsKey(stream.quality)) {
        qualities[stream.quality] = stream;
      }
      // Prefer stream with same voiceover
      if (stream.voiceover == _currentVoiceover) {
        qualities[stream.quality] = stream;
      }
    }

    final sorted = qualities.entries.toList()
      ..sort((a, b) => b.key.sortOrder.compareTo(a.key.sortOrder));

    return sorted.map((entry) {
      final isSelected = entry.key == _currentQuality;
      return PopupMenuItem<dynamic>(
        value: entry.value,
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 18, color: AppTheme.primaryColor)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Text(entry.key.displayName),
          ],
        ),
      );
    }).toList();
  }

  List<PopupMenuItem<StreamSource>> _buildVoiceoverMenuItems() {
    if (widget.streams == null) return [];

    // Group by voiceover, prefer current quality
    final voiceovers = <String, StreamSource>{};
    for (final stream in widget.streams!) {
      final voiceover = stream.voiceover ?? 'Оригінал';
      if (!voiceovers.containsKey(voiceover)) {
        voiceovers[voiceover] = stream;
      }
      // Prefer stream with same quality
      if (stream.quality == _currentQuality) {
        voiceovers[voiceover] = stream;
      }
    }

    final sorted = voiceovers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return sorted.map((entry) {
      final isSelected = entry.key == (_currentVoiceover ?? 'Оригінал');
      return PopupMenuItem<StreamSource>(
        value: entry.value,
        child: Row(
          children: [
            if (isSelected)
              const Icon(Icons.check, size: 18, color: AppTheme.primaryColor)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(entry.key, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }).toList();
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.white70),
                    SizedBox(width: 12),
                    Text(
                      'Налаштування відтворення',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Auto-play next
              SwitchListTile(
                secondary: const Icon(Icons.skip_next, color: Colors.white70),
                title: const Text(
                  'Автовідтворення наступного',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Автоматично запускати наступну серію',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                value: _settingsService.state.autoPlayNext,
                onChanged: (value) {
                  _settingsService.setAutoPlayNext(value);
                  setSheetState(() {});
                },
              ),

              // Remember position
              SwitchListTile(
                secondary: const Icon(Icons.bookmark, color: Colors.white70),
                title: const Text(
                  'Запам\'ятовувати позицію',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Продовжувати з місця зупинки',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                value: _settingsService.state.rememberPosition,
                onChanged: (value) {
                  _settingsService.setRememberPosition(value);
                  setSheetState(() {});
                },
              ),

              const Divider(color: Colors.white24),

              // Quality preference
              ListTile(
                leading: const Icon(Icons.high_quality, color: Colors.white70),
                title: const Text(
                  'Якість за замовчуванням',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Text(
                  _settingsService.state.defaultQuality.displayName,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                onTap: () => _showQualityPicker(setSheetState),
              ),

              // Speed preference
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.white70),
                title: const Text(
                  'Швидкість',
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
                onTap: () => _showSpeedPicker(setSheetState),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showQualityPicker(StateSetter setSheetState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Якість за замовчуванням'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: DefaultQuality.values.map((q) {
            final isSelected = q == _settingsService.state.defaultQuality;
            return ListTile(
              leading: isSelected
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : const SizedBox(width: 24),
              title: Text(q.displayName),
              onTap: () {
                _settingsService.setDefaultQuality(q);
                Navigator.pop(context);
                setSheetState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showSpeedPicker(StateSetter setSheetState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text('Швидкість відтворення'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _speeds.map((s) {
            final isSelected = s == _playbackSpeed;
            return ListTile(
              leading: isSelected
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : const SizedBox(width: 24),
              title: Text('${s}x'),
              onTap: () {
                _setSpeed(s);
                Navigator.pop(context);
                setSheetState(() {});
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.select:
        _player.playOrPause();
        break;
      case LogicalKeyboardKey.arrowLeft:
        _player.seek(_position - const Duration(seconds: 10));
        break;
      case LogicalKeyboardKey.arrowRight:
        _player.seek(_position + const Duration(seconds: 10));
        break;
      case LogicalKeyboardKey.arrowUp:
        // Increase volume
        break;
      case LogicalKeyboardKey.arrowDown:
        // Decrease volume
        break;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.backspace:
        context.pop();
        break;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        break;
      default:
        break;
    }

    // Show controls on any key press
    if (!_showControls) {
      setState(() => _showControls = true);
      _scheduleHideControls();
    }
  }
}
