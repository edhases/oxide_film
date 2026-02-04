import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/utils/logger.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/watch_party_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';
import 'player_chat_overlay.dart';
import 'player_controller.dart';
import 'player_controls.dart';
import 'player_gesture_layer.dart';

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
  late final PlayerController _controller;
  final FocusNode _focusNode = FocusNode();

  // UI State managed by Page, not Controller (purely visual toggles)
  bool _showControls = true;
  bool _showChat = false;
  int _newChatMessages = 0;
  int _lastSeenMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = PlayerController(
      initialUrl: widget.url,
      historyService: GetIt.instance<HistoryService>(),
      settingsService: GetIt.instance<SettingsService>(),
      watchPartyService: GetIt.instance<WatchPartyService>(),
      title: widget.title,
      mediaId: widget.mediaId,
      providerId: widget.providerId,
      posterUrl: widget.posterUrl,
      streams: widget.streams,
    );

    _controller.initialize();

    // UI Callbacks
    _controller.onPlaybackCompleted = () {
      if (mounted) context.pop(true);
    };

    _controller.onPositionResumed = (pos) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Продовжено з ${_formatDuration(pos)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };

    _controller.onQualityReduced = (quality) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Якість знижено до $quality'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };

    // Watch Party Listener for Chat
    _controller.watchPartyService.addListener(_onWatchPartyUpdate);

    _focusNode.requestFocus();
    _scheduleHideControls();
  }

  @override
  void didChangeMetrics() {
    Logger.d('PlayerPage: didChangeMetrics called', tag: 'PlayerPage');
    // When window metrics change (resize/fullscreen), the GPU texture context
    // may become invalidated on Windows. The PlayerController handles this via
    // textureKey, but we still need to trigger a rebuild to pick up the changes.
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Logger.d(
            'PlayerPage: postFrameCallback triggered rebuild',
            tag: 'PlayerPage',
          );
          setState(() {});
        }
      });
    }
    super.didChangeMetrics();
  }

  void _onWatchPartyUpdate() {
    if (!mounted) return;
    // Track new messages when chat is closed
    final totalMessages = _controller.watchPartyService.chatMessages.length;
    if (!_showChat && totalMessages > _lastSeenMessageCount) {
      if (mounted) {
        setState(() {
          _newChatMessages = totalMessages - _lastSeenMessageCount;
        });
      }
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHideControls();
    }
  }

  void _scheduleHideControls() {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _controller.state.isPlaying && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleChatOverlay() {
    setState(() {
      _showChat = !_showChat;
      if (_showChat) {
        _newChatMessages = 0;
        _lastSeenMessageCount =
            _controller.watchPartyService.chatMessages.length;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.watchPartyService.removeListener(_onWatchPartyUpdate);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
        case LogicalKeyboardKey.enter:
          _controller.playOrPause();
          _showControlsTemp();
          break;
        case LogicalKeyboardKey.arrowRight:
          _controller.seekForward();
          _showControlsTemp();
          break;
        case LogicalKeyboardKey.arrowLeft:
          _controller.seekBackward();
          _showControlsTemp();
          break;
        case LogicalKeyboardKey.escape:
          if (_controller.state.isFullscreen) {
            _controller.toggleFullscreen();
          } else {
            context.pop();
          }
          break;
      }
    }
  }

  void _showControlsTemp() {
    if (!_showControls) {
      setState(() => _showControls = true);
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}'
        : '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    Logger.d(
      'PlayerPage: build called. isFullscreen: ${_controller.state.isFullscreen}',
      tag: 'PlayerPage',
    );
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        // If in fullscreen, exit fullscreen first
        if (_controller.state.isFullscreen) {
          await _controller.toggleFullscreen();
          return;
        }

        // Otherwise close player
        if (context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: _handleKeyEvent,
          child: MouseRegion(
            onHover: (_) => _showControlsTemp(),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final state = _controller.state;

                // Video Layer
                if (!state.isInitialized) {
                  return const Center(child: CircularProgressIndicator());
                }

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Video Layer - simple approach, let media_kit handle resizing
                    if (!state.hasError)
                      Video(
                        controller: _controller.videoController,
                        fit: state.videoFit,
                        fill: Colors.black,
                        controls: NoVideoControls,
                      )
                    else
                      _buildErrorWidget(state.errorMessage),

                    // Buffering Layer
                    if (state.isBuffering && !state.hasError)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),

                    // Gesture Layer
                    PlayerGestureLayer(
                      onTap: _toggleControls,
                      onDoubleTap: _controller.toggleFullscreen,
                      child: Container(color: Colors.transparent),
                    ),

                    // Controls Layer
                    PlayerControls(
                      controller: _controller,
                      showControls: _showControls,
                      onToggleControls: _toggleControls,
                      showChat: _showChat,
                      onToggleChat: _toggleChatOverlay,
                      newChatMessages: _newChatMessages,
                    ),

                    // Chat Layer
                    if (_showChat)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        child: PlayerChatOverlay(
                          service: _controller.watchPartyService,
                          onClose: _toggleChatOverlay,
                        ),
                      ),

                    // Watch Party UI (Sync Status)
                    if (_controller.watchPartyService.state ==
                        WatchPartyState.connected)
                      _buildWatchPartyFloatingUI(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String? error) {
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
                error ?? 'Не вдалося завантажити відео',
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
                    onPressed: _controller.retryPlayback,
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
                      .where((s) => s.url != _controller.state.currentUrl)
                      .take(3)
                      .map(
                        (stream) => ActionChip(
                          label: Text(
                            stream.voiceover ?? stream.quality.displayName,
                          ),
                          onPressed: () =>
                              _controller.switchStreamWithRetry(stream),
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

  Widget _buildWatchPartyFloatingUI() {
    return Positioned(
      right: _showChat ? 316 : 16,
      bottom: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSyncIndicator(),
          const SizedBox(height: 8),
          _buildChatFAB(),
        ],
      ),
    );
  }

  Widget _buildSyncIndicator() {
    final service = _controller.watchPartyService;
    final mode = service.correctionMode;

    if (service.isHost) {
      return Tooltip(
        message: '${service.participants.length} учасників',
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Badge(
            label: Text('${service.participants.length}'),
            backgroundColor: Colors.green,
            child: const Icon(Icons.groups, color: Colors.white, size: 20),
          ),
        ),
      );
    }

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
}
