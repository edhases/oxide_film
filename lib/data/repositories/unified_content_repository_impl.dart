import '../../data/database/app_database.dart' hide WatchHistory, Favorites;
import '../../data/database/dao/favorites_dao.dart';
import '../../data/database/dao/history_dao.dart';
import '../../data/database/dao/media_items_dao.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../../domain/repositories/unified_content_repository.dart';

class UnifiedContentRepositoryImpl implements UnifiedContentRepository {
  static const String _tag = 'UnifiedContentRepository';

  final List<ContentProvider> _providers;
  final HistoryDao _historyDao;
  final FavoritesDao _favoritesDao;
  final MediaItemsDao _mediaItemsDao;

  UnifiedContentRepositoryImpl(
    this._providers,
    this._historyDao,
    this._favoritesDao,
    this._mediaItemsDao,
  );

  @override
  List<String> get providerIds => _providers.map((p) => p.id).toList();

  ContentProvider? _getProviderById(String id) {
    return _providers.where((p) => p.id == id && p.isEnabled).firstOrNull;
  }

  // Helper to parse "providerId:itemId"
  (ContentProvider?, String) _resolveProviderAndId(String fullId) {
    if (!fullId.contains(':')) return (null, fullId);

    final parts = fullId.split(':');
    final providerId = parts[0];
    final itemId = parts
        .sublist(1)
        .join(':'); // Join back just in case ID has colons

    return (_getProviderById(providerId), itemId);
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) async {
    final results = <MediaItem>[];

    // Create list of futures for enabled providers
    final futures = _providers.where((p) => p.isEnabled).map((provider) async {
      try {
        final items = await provider.search(query, type: type, page: page);
        return items.map((item) => _ensureGlobalId(item, provider.id)).toList();
      } catch (e) {
        Logger.w('Search failed for ${provider.name}', tag: _tag, error: e);
        return <MediaItem>[];
      }
    });

    final resultsList = await Future.wait(futures);
    for (final list in resultsList) {
      results.addAll(list);
    }

    return results;
  }

  @override
  Future<MediaDetails> getDetails(String id) async {
    final (provider, itemId) = _resolveProviderAndId(id);

    if (provider == null) {
      throw Exception('Provider not found for ID: $id');
    }

    try {
      final details = await provider.getDetails(itemId);
      final globalItem = _ensureGlobalId(details.item, provider.id);

      // Cache metadata
      await _mediaItemsDao.upsert(globalItem);

      return details.copyWith(item: globalItem);
    } catch (e, stack) {
      Logger.e(
        'Get details failed for $id',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) async {
    final (provider, itemId) = _resolveProviderAndId(id);

    if (provider == null) {
      throw Exception('Provider not found for ID: $id');
    }

    try {
      return await provider.getStreams(
        itemId,
        season: season,
        episode: episode,
      );
    } catch (e, stack) {
      Logger.e(
        'Get streams failed for $id',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<List<MediaItem>> getHistory({int? limit}) async {
    final historyData = await _historyDao.getAll(limit: limit);
    final results = <MediaItem>[];

    for (final entry in historyData) {
      // Try to get from metadata cache first
      final cached = await _mediaItemsDao.get(entry.mediaId, entry.providerId);
      if (cached != null) {
        results.add(cached);
      } else {
        // Fallback to basic info from history record
        results.add(
          MediaItem(
            id: entry.mediaId,
            providerId: entry.providerId,
            title: entry.title,
            posterUrl: entry.posterUrl,
            year: entry.year,
            rating: entry.rating,
            ratingSource: entry.ratingSource,
            type: _parseType(entry.mediaType),
          ),
        );
      }
    }
    return results;
  }

  @override
  Future<List<MediaItem>> getFavorites() async {
    final favoriteData = await _favoritesDao.getAll();
    final results = <MediaItem>[];

    for (final entry in favoriteData) {
      final cached = await _mediaItemsDao.get(entry.mediaId, entry.providerId);
      if (cached != null) {
        results.add(cached);
      } else {
        results.add(
          MediaItem(
            id: entry.mediaId,
            providerId: entry.providerId,
            title: entry.title,
            posterUrl: entry.posterUrl,
            year: entry.year,
            rating: entry.rating,
            ratingSource: entry.ratingSource,
            type: _parseType(entry.mediaType),
          ),
        );
      }
    }
    return results;
  }

  @override
  Future<bool> toggleFavorite(String id) async {
    final (provider, itemId) = _resolveProviderAndId(id);
    if (provider == null) return false;

    final item = await _mediaItemsDao.get(itemId, provider.id);
    if (item == null) {
      // If not cached, we need to fetch details or at least have minimal info
      // Usually toggle happens on details page where it IS cached.
      throw Exception('Item metadata not found for toggle: $id');
    }

    return await _favoritesDao.toggle(
      mediaId: itemId,
      providerId: provider.id,
      title: item.title,
      posterUrl: item.posterUrl,
      year: item.year,
      mediaType: item.type.name,
    );
  }

  @override
  Future<bool> isFavorite(String id) async {
    final (provider, itemId) = _resolveProviderAndId(id);
    if (provider == null) return false;
    return await _favoritesDao.isFavorite(itemId, provider.id);
  }

  @override
  Future<(Duration, Duration)?> getWatchProgress(
    String id, {
    int? season,
    int? episode,
  }) async {
    final (provider, itemId) = _resolveProviderAndId(id);
    if (provider == null) return null;

    final entry = await _historyDao.getForMedia(
      itemId,
      provider.id,
      season: season,
      episode: episode,
    );

    if (entry == null) return null;
    return (
      Duration(milliseconds: entry.positionMs),
      Duration(milliseconds: entry.durationMs),
    );
  }

  @override
  Future<void> updateWatchProgress(
    String id,
    Duration position,
    Duration duration, {
    int? season,
    int? episode,
    String? episodeTitle,
    String? lastStreamUrl,
    String? voiceover,
  }) async {
    final (provider, itemId) = _resolveProviderAndId(id);
    if (provider == null) return;

    final item = await _mediaItemsDao.get(itemId, provider.id);
    if (item == null) return; // Should be cached by getDetails

    await _historyDao.saveProgress(
      mediaId: itemId,
      providerId: provider.id,
      title: item.title,
      posterUrl: item.posterUrl,
      year: item.year,
      mediaType: item.type.name,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      lastStreamUrl: lastStreamUrl,
      voiceover: voiceover,
      rating: item.rating,
      ratingSource: item.ratingSource,
    );
  }

  @override
  Future<void> removeFromHistory(String id) async {
    final (provider, itemId) = _resolveProviderAndId(id);
    if (provider == null) return;
    await _historyDao.remove(itemId, provider.id);
  }

  @override
  Future<void> clearHistory() async {
    await _historyDao.clearAll();
  }

  ContentType _parseType(String type) {
    return ContentType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => ContentType.unknown,
    );
  }

  @override
  Future<List<MediaItem>> getPopular({
    ContentType? type,
    int page = 1,
    String? providerId,
  }) async {
    if (providerId != null) {
      final provider = _getProviderById(providerId);
      if (provider != null) {
        try {
          final items = await provider.getPopular(type: type, page: page);
          return items.map((i) => _ensureGlobalId(i, provider.id)).toList();
        } catch (e) {
          Logger.w('Get popular failed for $providerId', tag: _tag, error: e);
          return [];
        }
      }
      return [];
    }

    // Aggregate from all (or first enabled?)
    // For "Popular", usually we pick one primary or mix.
    // Let's mix from all enabled.
    final futures = _providers.where((p) => p.isEnabled).map((provider) async {
      try {
        final items = await provider.getPopular(type: type, page: page);
        return items.map((i) => _ensureGlobalId(i, provider.id)).toList();
      } catch (e) {
        Logger.w(
          'Get popular failed for ${provider.name}',
          tag: _tag,
          error: e,
        );
        return <MediaItem>[];
      }
    });

    final resultsList = await Future.wait(futures);
    final results = <MediaItem>[];
    for (final list in resultsList) {
      results.addAll(list);
    }
    results.shuffle(); // Shuffle for variety? Or keep usage specific?
    // Usually user wants consistent order.
    // For now, let's just append.
    return results;
  }

  @override
  Future<List<MediaItem>> getNew({
    ContentType? type,
    int page = 1,
    String? providerId,
  }) async {
    // Similar to getPopular
    if (providerId != null) {
      final provider = _getProviderById(providerId);
      if (provider != null) {
        try {
          final items = await provider.getNew(type: type, page: page);
          return items.map((i) => _ensureGlobalId(i, provider.id)).toList();
        } catch (e) {
          Logger.w('Get new failed for $providerId', tag: _tag, error: e);
          return [];
        }
      }
      return [];
    }

    final futures = _providers.where((p) => p.isEnabled).map((provider) async {
      try {
        final items = await provider.getNew(type: type, page: page);
        return items.map((i) => _ensureGlobalId(i, provider.id)).toList();
      } catch (e) {
        Logger.w('Get new failed for ${provider.name}', tag: _tag, error: e);
        return <MediaItem>[];
      }
    });

    final resultsList = await Future.wait(futures);
    final results = <MediaItem>[];
    for (final list in resultsList) {
      results.addAll(list);
    }
    return results;
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
    String? providerId,
  }) async {
    // Logic for category
    if (providerId != null) {
      final provider = _getProviderById(providerId);
      if (provider != null) {
        try {
          final items = await provider.getByCategory(
            category,
            type: type,
            page: page,
          );
          return items.map((i) => _ensureGlobalId(i, provider.id)).toList();
        } catch (e) {
          Logger.w('Get category failed for $providerId', tag: _tag, error: e);
          return [];
        }
      }
    }
    // If no provider specified?
    return [];
  }

  MediaItem _ensureGlobalId(MediaItem item, String providerId) {
    if (item.id.startsWith('$providerId:')) return item;
    // Do not double prefix?
    // Providers might already return prefixed IDs?
    // Usually providers return local IDs.
    // We should enforce global IDs.
    return item.copyWith(id: '$providerId:${item.id}');
  }
}
