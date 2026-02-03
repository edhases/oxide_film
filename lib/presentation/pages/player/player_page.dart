import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/utils/logger.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';

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

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player;
  late final VideoController _controller;
  final _focusNode = FocusNode();
  final _historyService = GetIt.instance<HistoryService>();
  final _settingsService = GetIt.instance<SettingsService>();
  Timer? _saveProgressTimer;

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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _initCurrentStreamInfo();
    _initPlayer();
    _focusNode.requestFocus();
    _startProgressSaving();

    // Enable wakelock to keep screen on
    WakelockPlus.enable();

    // Auto-hide controls after delay
    _scheduleHideControls();
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
      // 1. Try to find stream matching widget.url (initial)
      var current = widget.streams!.firstWhere(
        (s) => s.url == _currentUrl,
        orElse: () => widget.streams!.first,
      );

      // 2. Check if we should override with Default Quality setting
      final defaultQuality = _settingsService.state.defaultQuality;
      // Only override if the default isn't "auto" (assuming auto means "use provided")
      // Actually, if user set a specific preference (e.g. 1080p), we should try to find it.

      final preferredStream = widget.streams!.firstWhere(
        (s) => s.quality == defaultQuality,
        orElse: () => current,
      );

      // If we found a stream with the preferred quality, use it
      if (preferredStream != current) {
        current = preferredStream;
        _currentUrl = current.url;
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
    _player.stream.playing.listen((playing) {
      if (mounted) setState(() {});
    });

    _player.stream.completed.listen((completed) {
      if (completed) {
        if (_settingsService.state.autoPlayNext) {
          // Verify if we can signal playing next
          // For now, simpler approach: just close with specific result or show UI
          // Since PlayerPage is generic, handling "Next Episode" requires external logic
          // usually via a callback or by returning "completed" result.
          // We will return 'true' on pop if completed to signal "try next"
          if (mounted) {
            context.pop(true);
          }
        }
      }
    });

    _player.stream.position.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });

    _player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() => _isBuffering = buffering);
      }
    });

    // Listen to player errors
    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
          _isBuffering = false;
        });
      }
    });

    // Open media and start playing
    await _player.open(Media(_currentUrl));

    // Resume from last position if available
    await _resumeLastPosition();

    if (mounted) {
      setState(() => _isInitialized = true);
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
    WakelockPlus.disable(); // Disable wakelock
    _saveProgressTimer?.cancel();
    _saveProgress(); // Save final progress
    _focusNode.dispose();
    _player.dispose();
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
                // Video
                if (_isInitialized && !_hasError)
                  Video(
                    controller: _controller,
                    fit: _videoFit,
                    fill: Colors.black,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _cycleFit() {
    setState(() {
      final currentIndex = _fits.indexOf(_videoFit);
      final nextIndex = (currentIndex + 1) % _fits.length;
      _videoFit = _fits[nextIndex];
    });
  }

  void _toggleControls() {
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
    await _player.open(Media(_currentUrl));
  }

  Future<void> _switchStreamWithRetry(StreamSource stream) async {
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 12),

            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.title != null)
                    Text(
                      widget.title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  // Show current quality/voiceover
                  Text(
                    _buildSubtitleText(),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            // Quality selector (if multiple streams available)
            if (_hasMultipleQualities())
              PopupMenuButton<StreamSource>(
                icon: const Icon(Icons.high_quality, color: Colors.white),
                tooltip: 'Якість',
                onSelected: _switchStream,
                itemBuilder: (context) => _buildQualityMenuItems(),
              ),

            // Voiceover selector (if multiple voiceovers available)
            if (_hasMultipleVoiceovers())
              PopupMenuButton<StreamSource>(
                icon: const Icon(Icons.record_voice_over, color: Colors.white),
                tooltip: 'Озвучка',
                onSelected: _switchStream,
                itemBuilder: (context) => _buildVoiceoverMenuItems(),
              ),

            // Speed selector
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed, color: Colors.white),
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
              icon: const Icon(Icons.settings, color: Colors.white),
              tooltip: 'Налаштування',
              onPressed: _showSettingsSheet,
            ),

            // Scaling toggle
            IconButton(
              icon: Icon(
                _fitIcons[_fits.indexOf(_videoFit)],
                color: Colors.white,
              ),
              tooltip: _fitTooltips[_fits.indexOf(_videoFit)],
              onPressed: _cycleFit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
                },
              ),
            ),

            // Time and controls row
            Row(
              children: [
                // Time
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),

                const Spacer(),

                // Rewind 10s
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () =>
                      _player.seek(_position - const Duration(seconds: 10)),
                ),

                // Play/Pause
                IconButton(
                  iconSize: 48,
                  icon: Icon(
                    _player.state.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  onPressed: () => _player.playOrPause(),
                ),

                // Forward 10s
                IconButton(
                  iconSize: 28,
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () =>
                      _player.seek(_position + const Duration(seconds: 10)),
                ),

                const Spacer(),

                // Speed indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),

                const SizedBox(width: 8),

                // Fullscreen
                IconButton(
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: 28,
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
    setState(() => _playbackSpeed = speed);
    _player.setRate(speed);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ===========================================================================
  // QUALITY & VOICEOVER SELECTORS
  // ===========================================================================

  String _buildSubtitleText() {
    final parts = <String>[];
    if (_currentQuality != null) {
      parts.add(_currentQuality!.displayName);
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

  List<PopupMenuItem<StreamSource>> _buildQualityMenuItems() {
    if (widget.streams == null) return [];

    // Group by quality, prefer current voiceover
    final qualities = <StreamQuality, StreamSource>{};
    for (final stream in widget.streams!) {
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
      return PopupMenuItem<StreamSource>(
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
