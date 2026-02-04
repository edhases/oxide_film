import '../entities/entities.dart';

/// Central repository for accessing content from multiple providers
abstract class UnifiedContentRepository {
  /// Get content providers
  List<String> get providerIds;

  /// Search for content across all enabled providers
  Future<List<MediaItem>> search(
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
  Future<List<MediaItem>> getPopular({
    ContentType? type,
    int page = 1,
    String? providerId,
  });

  /// Get new content (aggregated or from specific provider)
  Future<List<MediaItem>> getNew({
    ContentType? type,
    int page = 1,
    String? providerId,
  });

  /// Get content by category
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
    String? providerId,
  });
}
