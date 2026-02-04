import '../entities/entities.dart';

/// Central repository for accessing content from multiple providers
abstract class UnifiedContentRepository {
  /// Get content providers
  List<String> get providerIds;

  /// Search for content across all enabled providers
  Stream<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  });

  /// Get details for a specific media item
  ///
  /// [id] - unique ID (usually "providerId:itemId")
  Future<MediaDetails> getDetails(String id);

  /// Get streams for a specific media item
  Future<List<StreamSource>> getStreams(String id, {int? season, int? episode});

  /// Get popular content (aggregated or from specific provider)
  Stream<List<MediaItem>> getPopular({
    ContentType? type,
    int page = 1,
    String? providerId,
  });

  /// Get new content (aggregated or from specific provider)
  Stream<List<MediaItem>> getNew({
    ContentType? type,
    int page = 1,
    String? providerId,
  });

  /// Get content by category
  Stream<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
    String? providerId,
  });

  /// Get full watch history
  Future<List<MediaItem>> getHistory({int? limit});

  /// Get favorite items
  Future<List<MediaItem>> getFavorites();

  /// Toggle favorite status
  Future<bool> toggleFavorite(String id);

  /// Check if item is favorited
  Future<bool> isFavorite(String id);

  /// Get watch progress (position, duration) for media or specific episode
  Future<(Duration, Duration)?> getWatchProgress(
    String id, {
    int? season,
    int? episode,
  });

  /// Update watch progress
  Future<void> updateWatchProgress(
    String id,
    Duration position,
    Duration duration, {
    int? season,
    int? episode,
    String? episodeTitle,
    String? lastStreamUrl,
    String? voiceover,
  });

  /// Remove item from history
  Future<void> removeFromHistory(String id);

  /// Clear all history
  Future<void> clearHistory();
}
