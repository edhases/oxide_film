import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../../domain/repositories/unified_content_repository.dart';

class UnifiedContentRepositoryImpl implements UnifiedContentRepository {
  static const String _tag = 'UnifiedContentRepository';

  final List<ContentProvider> _providers;

  UnifiedContentRepositoryImpl(this._providers);

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
        // Ensure items have provider prefix in ID if not already?
        // MediaItem usually has providerId field.
        // But UI expects unique IDs.
        // Let's ensure the returned items have correct IDs for global context.
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

    // Deduplicate logic could go here if providers return same content (unlikely for now)

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
      // Ensure global ID
      return details.copyWith(item: _ensureGlobalId(details.item, provider.id));
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
