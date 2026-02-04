import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/utils/responsive_utils.dart';
import '../../../data/services/watch_party_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';
import 'player_controller.dart';

class PlayerControls extends StatelessWidget {
  final PlayerController controller;
  final bool showControls;
  final VoidCallback onToggleControls;
  final VoidCallback onToggleChat;
  final bool showChat;
  final int newChatMessages;

  const PlayerControls({
    super.key,
    required this.controller,
    required this.showControls,
    required this.onToggleControls,
    required this.onToggleChat,
    required this.showChat,
    required this.newChatMessages,
  });

  @override
  Widget build(BuildContext context) {
    if (controller.state.hasError) return const SizedBox.shrink();

    return AnimatedOpacity(
      opacity: showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !showControls,
        child: Container(
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
            children: [
              _TopBar(
                controller: controller,
                onToggleChat: onToggleChat,
                showChat: showChat,
                newChatMessages: newChatMessages,
              ),
              const Spacer(),
              _BottomControls(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final PlayerController controller;
  final VoidCallback onToggleChat;
  final bool showChat;
  final int newChatMessages;

  const _TopBar({
    required this.controller,
    required this.onToggleChat,
    required this.showChat,
    required this.newChatMessages,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = context.isCompact;
    final isMobile = context.isMobile;
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
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.title != null)
                        Text(
                          controller.title!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (!useCompactControls)
                        Text(
                          controller.buildSubtitleText(null),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: subtitleFontSize,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (useCompactControls)
              _CompactMenu(controller: controller, iconSize: iconSize)
            else
              _ExpandedMenu(
                controller: controller,
                iconSize: iconSize,
                onToggleChat: onToggleChat,
                showChat: showChat,
                newChatMessages: newChatMessages,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactMenu extends StatelessWidget {
  final PlayerController controller;
  final double iconSize;

  const _CompactMenu({required this.controller, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.white, size: iconSize),
      tooltip: 'Меню',
      itemBuilder: (context) => [
        if (controller.hasMultipleQualities())
          const PopupMenuItem(
            value: 'quality',
            child: ListTile(
              leading: Icon(Icons.high_quality),
              title: Text('Якість'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (controller.hasMultipleVoiceovers())
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
            leading: Icon(
              PlayerController.fitTooltips.contains(
                    controller.state.videoFit.toString(),
                  )
                  ? Icons.aspect_ratio
                  : Icons.fit_screen, // Simplify icon logic for now
            ),
            title: const Text('Масштаб'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'quality':
            _showQualitySheet(context, controller);
            break;
          case 'voice':
            _showVoiceoverSheet(context, controller);
            break;
          case 'speed':
            _showSpeedSheet(context, controller);
            break;
          case 'settings':
            // TODO: Implement Settings Sheet
            break;
          case 'fit':
            controller.cycleFit();
            break;
        }
      },
    );
  }
}

class _ExpandedMenu extends StatelessWidget {
  final PlayerController controller;
  final double iconSize;
  final VoidCallback onToggleChat;
  final bool showChat;
  final int newChatMessages;

  const _ExpandedMenu({
    required this.controller,
    required this.iconSize,
    required this.onToggleChat,
    required this.showChat,
    required this.newChatMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (controller.hasMultipleQualities())
          PopupMenuButton<dynamic>(
            icon: Icon(Icons.high_quality, color: Colors.white, size: iconSize),
            tooltip: 'Якість',
            itemBuilder: (context) => _buildQualityMenuItems(controller),
            onSelected: (value) {
              if (value is VideoTrack) {
                controller.setVideoTrack(value);
              } else if (value is StreamSource) {
                controller.switchStream(value);
              }
            },
          ),
        if (controller.hasMultipleVoiceovers())
          PopupMenuButton<StreamSource>(
            icon: Icon(
              Icons.record_voice_over,
              color: Colors.white,
              size: iconSize,
            ),
            tooltip: 'Озвучка',
            onSelected: controller.switchStream,
            itemBuilder: (context) => _buildVoiceoverMenuItems(controller),
          ),
        PopupMenuButton<double>(
          icon: Icon(Icons.speed, color: Colors.white, size: iconSize),
          tooltip: 'Швидкість',
          onSelected: controller.setSpeed,
          itemBuilder: (context) => PlayerController.speeds.map((speed) {
            return PopupMenuItem(
              value: speed,
              child: Row(
                children: [
                  if (speed == controller.state.playbackSpeed)
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
        IconButton(
          icon: Icon(Icons.settings, color: Colors.white, size: iconSize),
          tooltip: 'Налаштування',
          onPressed: () {
            // TODO: Settings
          },
        ),
        if (controller.watchPartyService.state == WatchPartyState.connected)
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline,
              color: Colors.white,
              size: iconSize,
            ),
            tooltip: 'Чат',
            onPressed: onToggleChat,
          ),
        IconButton(
          icon: Icon(Icons.aspect_ratio, color: Colors.white, size: iconSize),
          tooltip: 'Масштаб',
          onPressed: controller.cycleFit,
        ),
      ],
    );
  }
}

class _BottomControls extends StatelessWidget {
  final PlayerController controller;

  const _BottomControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isCompact = context.isCompact;
    final isMobile = context.isMobile;
    final padding = ResponsiveUtils.getPlayerBottomPadding(context);
    final iconSize = isCompact ? 24.0 : (isMobile ? 28.0 : 28.0);
    final playPauseSize = isCompact ? 40.0 : (isMobile ? 44.0 : 48.0);
    final fontSize = isCompact ? 11.0 : 13.0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final duration = controller.state.duration;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<Duration>(
                  valueListenable: controller.positionNotifier,
                  builder: (context, position, _) {
                    return SliderTheme(
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
                        value: duration.inMilliseconds > 0
                            ? (position.inMilliseconds /
                                      duration.inMilliseconds)
                                  .clamp(0.0, 1.0)
                            : 0,
                        onChanged: (value) {
                          final seekTo = Duration(
                            milliseconds: (value * duration.inMilliseconds)
                                .toInt(),
                          );
                          controller.seek(seekTo);
                        },
                      ),
                    );
                  },
                ),
                Row(
                  children: [
                    ValueListenableBuilder<Duration>(
                      valueListenable: controller.positionNotifier,
                      builder: (context, position, _) {
                        return Text(
                          '${_formatDuration(position)} / ${_formatDuration(duration)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    IconButton(
                      iconSize: iconSize,
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                      onPressed: () => controller.seekBackward(),
                    ),
                    IconButton(
                      iconSize: playPauseSize,
                      icon: Icon(
                        controller.state.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                      onPressed: controller.playOrPause,
                    ),
                    IconButton(
                      iconSize: iconSize,
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                      onPressed: () => controller.seekForward(),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        controller.state.isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white,
                        size: iconSize,
                      ),
                      onPressed: controller.toggleFullscreen,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
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
}

// Helper methods for sheets and menu items
List<PopupMenuItem<dynamic>> _buildQualityMenuItems(
  PlayerController controller,
) {
  final items = <PopupMenuItem<dynamic>>[];

  // HLS Tracks
  if (controller.state.videoTracks.length > 1) {
    final sortedTracks = List<VideoTrack>.from(controller.state.videoTracks)
      ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));

    // Filter duplicates
    final seenHeights = <int>{};
    for (final track in sortedTracks) {
      if (track.h != null && track.h! > 0) {
        if (seenHeights.contains(track.h)) continue;
        seenHeights.add(track.h!);
        items.add(
          PopupMenuItem(
            value: track,
            child: Row(
              children: [
                if (controller.state.selectedVideoTrack == track)
                  const Icon(Icons.check, size: 18)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text('${track.h}p'),
              ],
            ),
          ),
        );
      }
    }
    // Auto
    final autoTrack = VideoTrack.auto();
    items.add(
      PopupMenuItem(
        value: autoTrack,
        child: Row(
          children: [
            if (controller.state.selectedVideoTrack?.id == 'auto')
              const Icon(Icons.check, size: 18)
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            const Text('Auto'),
          ],
        ),
      ),
    );
  } else if (controller.streams != null) {
    // Stream sources
    final uniqueQualities = <StreamQuality, StreamSource>{};
    for (final s in controller.streams!) {
      // Filter by current voiceover
      if (s.voiceover == controller.state.currentVoiceover) {
        uniqueQualities[s.quality] = s;
      }
    }

    final sorted = uniqueQualities.values.toList()
      ..sort((a, b) => b.quality.sortOrder.compareTo(a.quality.sortOrder));

    for (final s in sorted) {
      items.add(
        PopupMenuItem(
          value: s,
          child: Row(
            children: [
              if (controller.state.currentUrl == s.url)
                const Icon(Icons.check, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(s.quality.displayName),
            ],
          ),
        ),
      );
    }
  }

  return items;
}

List<PopupMenuItem<StreamSource>> _buildVoiceoverMenuItems(
  PlayerController controller,
) {
  final items = <PopupMenuItem<StreamSource>>[];
  if (controller.streams != null) {
    final voiceovers = <String, StreamSource>{};
    for (final s in controller.streams!) {
      if (s.voiceover != null) {
        // Store one stream per voiceover (first found)
        if (!voiceovers.containsKey(s.voiceover)) {
          voiceovers[s.voiceover!] = s;
        }
      }
    }

    for (final entry in voiceovers.entries) {
      items.add(
        PopupMenuItem(
          value: entry.value,
          child: Row(
            children: [
              if (controller.state.currentVoiceover == entry.key)
                const Icon(Icons.check, size: 18)
              else
                const SizedBox(width: 18),
              const SizedBox(width: 8),
              Text(entry.key),
            ],
          ),
        ),
      );
    }
  }
  return items;
}

void _showQualitySheet(BuildContext context, PlayerController controller) {
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
          ..._buildQualityMenuItems(controller).map(
            (item) => ListTile(
              title: (item.child as Row).children.last,
              leading: (item.child as Row).children.first,
              onTap: () {
                Navigator.pop(context);
                if (item.value is VideoTrack) {
                  controller.setVideoTrack(item.value as VideoTrack);
                } else if (item.value is StreamSource) {
                  controller.switchStream(item.value as StreamSource);
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

void _showVoiceoverSheet(BuildContext context, PlayerController controller) {
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
          ..._buildVoiceoverMenuItems(controller).map(
            (item) => ListTile(
              title: (item.child as Row).children.last,
              leading: (item.child as Row).children.first,
              onTap: () {
                Navigator.pop(context);
                controller.switchStream(item.value!);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

void _showSpeedSheet(BuildContext context, PlayerController controller) {
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
          ...PlayerController.speeds.map(
            (speed) => ListTile(
              title: Text('${speed}x'),
              leading: speed == controller.state.playbackSpeed
                  ? const Icon(Icons.check, color: AppTheme.primaryColor)
                  : const SizedBox(width: 24),
              onTap: () {
                Navigator.pop(context);
                controller.setSpeed(speed);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
