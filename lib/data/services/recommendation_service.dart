import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/utils/logger.dart';
import '../../core/constants/content_constants.dart';
import '../../domain/entities/entities.dart';
import '../providers/provider_registry.dart';
import '../database/app_database.dart';
import 'history_service.dart';

import 'favorites_service.dart';
import '../database/dao/media_items_dao.dart';

/// Service for generating personalized content recommendations
class RecommendationService extends ChangeNotifier {
  static const String _tag = 'RecommendationService';

  final HistoryService _historyService;
  final FavoritesService _favoritesService;
  final ProviderRegistry _providerRegistry;
  final MediaItemsDao _mediaItemsDao;

  List<MediaItem> _recommendations = [];
  List<MediaItem> get recommendations => _recommendations;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  RecommendationService({
    required HistoryService historyService,
    required FavoritesService favoritesService,
    required ProviderRegistry providerRegistry,
    required MediaItemsDao mediaItemsDao,
  }) : _historyService = historyService,
       _favoritesService = favoritesService,
       _providerRegistry = providerRegistry,
       _mediaItemsDao = mediaItemsDao;

  /// Initialize and load recommendations
  Future<void> init() async {
    // Wait for other services to be ready
    if (_historyService.history.isEmpty) {
      // Using listen to wait for history might be too complex for now,
      // just try to load, if empty it will use fallback.
      // The UI can trigger refresh later.
    }
    await refresh();
  }

  /// Refresh recommendations
  Future<void> refresh() async {
    if (_isLoading) return;

    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final recommendations = await _generateRecommendations();

      _recommendations = recommendations;
      Logger.i(
        'Generated ${_recommendations.length} recommendations',
        tag: _tag,
      );
    } catch (e, stack) {
      Logger.e(
        'Failed to generate recommendations',
        error: e,
        stackTrace: stack,
        tag: _tag,
      );
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<MediaItem>> _generateRecommendations() async {
    final history = _historyService.history.take(10).toList(); // Last 10 viewed
    final favorites = _favoritesService.favorites
        .take(10)
        .toList(); // Top 10 favorites

    if (history.isEmpty && favorites.isEmpty) {
      Logger.d(
        'No history or favorites found, falling back to popular content',
        tag: _tag,
      );
      return _getPopularFallback();
    }

    // 1. Analyze History & Favorites to find Top Genres
    final topGenres = await _analyzeCombinedGenres(history, favorites);

    if (topGenres.isEmpty) {
      Logger.d(
        'No genres found in analysis, falling back to popular',
        tag: _tag,
      );
      return _getPopularFallback();
    }

    Logger.d('Top genres for user: ${topGenres.join(', ')}', tag: _tag);

    // 2. Fetch content for top genres from multiple providers
    final results = <MediaItem>[];
    final providers = _providerRegistry.homeProviders;

    if (providers.isEmpty) return [];

    // Aggregate from multiple providers for variety
    for (final genre in topGenres) {
      // Pick a random provider for this genre to spread the load and increase variety
      final provider = providers[Random().nextInt(providers.length)];
      try {
        final slug = ProviderGenreMappings.getSlugForProvider(
          provider.id,
          genre,
        );
        final items = await provider.getByCategory(slug, page: 1);
        results.addAll(items.take(8)); // Take more to allow filtering
      } catch (e) {
        Logger.w(
          'Failed to fetch category $genre from ${provider.name}: $e',
          tag: _tag,
        );
      }
    }

    // 3. Fallback/Fill if not enough
    if (results.length < 15) {
      final popular = await _getPopularFallback();
      results.addAll(popular);
    }

    // 4. Deduplicate and Filter Viewed
    final viewedTitles = history.map((h) => h.title.toLowerCase()).toSet();
    final favoriteTitles = favorites.map((f) => f.title.toLowerCase()).toSet();

    final uniqueResults = <MediaItem>[];
    final addedTitles = <String>{};

    for (final item in results) {
      final titleKey = item.title.toLowerCase();
      // Don't recommend what's already viewed or favorited
      if (!viewedTitles.contains(titleKey) &&
          !favoriteTitles.contains(titleKey) &&
          !addedTitles.contains(titleKey)) {
        uniqueResults.add(item);
        addedTitles.add(titleKey);
      }
    }

    // Shuffle final results to avoid static order
    uniqueResults.shuffle();

    return uniqueResults.take(20).toList();
  }

  /// Analyze history and favorite items to find most frequent genres
  Future<List<String>> _analyzeCombinedGenres(
    List<WatchHistoryData> history,
    List<Favorite> favorites,
  ) async {
    final genreCounts = <String, int>{};

    // Analyze history (last 5)
    for (final h in history.take(5)) {
      final cached = await _mediaItemsDao.get(h.mediaId, h.providerId);
      if (cached?.genres != null) {
        for (final genre in cached!.genres!) {
          genreCounts[genre] =
              (genreCounts[genre] ?? 0) + 2; // History has weight 2
        }
      }
    }

    // Analyze favorites (last 5)
    for (final f in favorites.take(5)) {
      final cached = await _mediaItemsDao.get(f.mediaId, f.providerId);
      if (cached?.genres != null) {
        for (final genre in cached!.genres!) {
          genreCounts[genre] =
              (genreCounts[genre] ?? 0) + 3; // Favorites have weight 3
        }
      }
    }

    if (genreCounts.isEmpty) return [];

    final sortedGenres = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Filter out very low frequency if needed, but here we just take top 3
    return sortedGenres.take(3).map((e) => e.key).toList();
  }

  Future<List<MediaItem>> _getPopularFallback() async {
    final providers = _providerRegistry.homeProviders;
    if (providers.isEmpty) return [];

    final provider = providers[Random().nextInt(providers.length)];
    try {
      return await provider.getPopular(page: 1);
    } catch (e) {
      Logger.e('Fallback popular fetch failed', error: e, tag: _tag);
      return [];
    }
  }
}
