import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/services/history_service.dart';
import '../../../data/database/app_database.dart'; // For WatchHistoryData
import '../../../domain/entities/entities.dart';
// Removed unused skeleton import

/// Section that displays "Continue Watching" items from history
class ContinueWatchingSection extends StatefulWidget {
  const ContinueWatchingSection({super.key});

  @override
  State<ContinueWatchingSection> createState() =>
      _ContinueWatchingSectionState();
}

class _ContinueWatchingSectionState extends State<ContinueWatchingSection> {
  final _historyService = GetIt.instance<HistoryService>();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _historyService.addListener(_update);
  }

  @override
  void dispose() {
    _historyService.removeListener(_update);
    _scrollController.dispose();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // List is already filtered by progress in HistoryService/DAO
    final items = _historyService.continueWatching;

    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Продовжити перегляд',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 140,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: false, // Only show when scrolling
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = items[index];
                return _ContinueWatchingCard(item: item);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  final WatchHistoryData item;

  const _ContinueWatchingCard({required this.item});

  @override
  Widget build(BuildContext context) {
    // Calculate progress
    final progress = item.durationMs > 0
        ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final isLocal = item.providerId == 'local';
            // For online content, good luck with lastStreamUrl validity.
            // Ideally we should open DetailsPage if we can't play directly.
            // But let's try playing.
            context.push(
              '/player',
              extra: {
                'url': isLocal
                    ? 'file://${item.mediaId}'
                    : (item.lastStreamUrl ?? ''),
                'mediaId': item.mediaId,
                'providerId': item.providerId,
                'title': item.title,
                'posterUrl': item.posterUrl,
                'mediaType': _mapMediaType(item.mediaType),
                'initialSeason': item.season,
                'initialEpisode': item.episode,
                'initialEpisodeTitle': item.episodeTitle,
                'isOffline': isLocal,
              },
            );
          },
          child: Row(
            children: [
              // Poster / Thumbnail
              SizedBox(
                width: 93, // 2/3 aspect ratio approx for 140 height
                height: 140,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterUrl != null && item.posterUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.posterUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey[800],
                          child: const Icon(Icons.movie, color: Colors.white54),
                        ),
                      )
                    else
                      Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.movie, color: Colors.white54),
                      ),

                    // Play icon overlay
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (item.season != null && item.episode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'S${item.season} E${item.episode}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (item.episodeTitle != null &&
                          item.episodeTitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.episodeTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.grey[700],
                          color: Theme.of(context).colorScheme.primary,
                          minHeight: 3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatRemaining(item.durationMs - item.positionMs),
                        style: TextStyle(color: Colors.grey[500], fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRemaining(int ms) {
    if (ms <= 0) return 'Завершено';
    final duration = Duration(milliseconds: ms);
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} хв';
    } else {
      return '${duration.inHours} год ${duration.inMinutes % 60} хв';
    }
  }

  ContentType _mapMediaType(String type) {
    // Basic mapping, fallback to movie
    return ContentType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => ContentType.movie,
    );
  }
}
