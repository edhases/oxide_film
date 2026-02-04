import 'dart:async';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import '../../../core/utils/logger.dart';
import '../../../domain/entities/entities.dart';
import '../../database/dao/search_history_dao.dart';
import '../../providers/provider_registry.dart';
import '../search_service.dart';
import 'transliteration_service.dart';

/// Smart search service with fuzzy matching, transliteration, and history
///
/// Features:
/// - Automatic Latin ↔ Cyrillic transliteration
/// - Fuzzy matching for typo tolerance
/// - Search history for autocomplete
/// - Memory cache for fast suggestions
/// - Result ranking by relevance
class SmartSearchService {
  static const String _tag = 'SmartSearch';

  /// Fuzzy matching threshold (0-100)
  /// 75 = allows 1-2 typos
  static const int _fuzzyThreshold = 75;

  /// Deduplication threshold (0-100)
  /// 85 = very similar titles are merged
  static const int _deduplicationThreshold = 85;

  final SearchService _searchService;
  // ignore: unused_field - reserved for future provider-specific logic
  final ProviderRegistry _registry;
  final TransliterationService _transliteration;
  final SearchHistoryDao _historyDao;

  /// Memory cache for search results (cleared on app restart)
  final Map<String, AggregatedSearchResult> _memoryCache = {};

  /// Cache TTL (10 minutes)
  static const Duration _cacheTtl = Duration(minutes: 10);
  final Map<String, DateTime> _cacheTimestamps = {};

  SmartSearchService(this._searchService, this._registry, this._historyDao)
    : _transliteration = TransliterationService();

  /// Perform smart search with transliteration and fuzzy matching
  ///
  /// 1. Generates search variants (transliterated, translated)
  /// 2. Searches all variants in parallel
  /// 3. Merges and deduplicates results
  /// 4. Ranks by relevance
  /// 5. Saves to history
  Future<SmartSearchResult> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) async {
    final normalized = _transliteration.normalizeQuery(query);
    if (normalized.isEmpty) {
      return SmartSearchResult.empty(query);
    }

    final stopwatch = Stopwatch()..start();

    // Check memory cache
    final cacheKey = '$normalized:$type:$page';
    if (_isCacheValid(cacheKey)) {
      Logger.d('Cache hit for "$normalized"', tag: _tag);
      final cached = _memoryCache[cacheKey]!;
      return SmartSearchResult(
        originalQuery: query,
        normalizedQuery: normalized,
        searchVariants: [normalized],
        aggregatedResult: cached,
        rankedItems: _rankResults(cached.allItems, normalized),
        totalDuration: stopwatch.elapsed,
        fromCache: true,
      );
    }

    // Generate search variants
    final variants = _transliteration.generateSearchVariants(query);
    Logger.d('Search variants for "$query": $variants', tag: _tag);

    // Search all variants
    final allResults = <MediaItem>[];
    AggregatedSearchResult? primaryResult;

    for (final variant in variants) {
      try {
        final result = await _searchService.search(
          variant,
          type: type,
          page: page,
        );

        if (primaryResult == null ||
            result.totalCount > primaryResult.totalCount) {
          primaryResult = result;
        }

        allResults.addAll(result.allItems);
      } catch (e) {
        Logger.w('Search failed for variant "$variant": $e', tag: _tag);
      }
    }

    // Deduplicate results
    final deduped = _deduplicateResults(allResults);

    // Rank results
    final ranked = _rankResults(deduped, normalized);

    // Cache the result
    if (primaryResult != null) {
      _memoryCache[cacheKey] = primaryResult;
      _cacheTimestamps[cacheKey] = DateTime.now();
    }

    // Save to history
    await _saveToHistory(query, normalized, ranked.length);

    stopwatch.stop();

    Logger.i(
      'Smart search "$query": ${ranked.length} results in ${stopwatch.elapsedMilliseconds}ms',
      tag: _tag,
    );

    return SmartSearchResult(
      originalQuery: query,
      normalizedQuery: normalized,
      searchVariants: variants,
      aggregatedResult:
          primaryResult ??
          AggregatedSearchResult(
            query: query,
            providerResults: [],
            totalDuration: stopwatch.elapsed,
          ),
      rankedItems: ranked,
      totalDuration: stopwatch.elapsed,
      fromCache: false,
    );
  }

  /// Get quick suggestions from history and memory cache
  Future<List<SearchSuggestion>> getSuggestions(
    String query, {
    int limit = 10,
  }) async {
    if (query.length < 2) return [];

    final normalized = _transliteration.normalizeQuery(query);
    final suggestions = <SearchSuggestion>[];

    // 1. Get matching history entries
    try {
      final historyMatches = await _historyDao.searchByPrefix(
        normalized,
        limit: 5,
      );

      for (final entry in historyMatches) {
        suggestions.add(
          SearchSuggestion(
            text: entry.query,
            type: SuggestionType.history,
            searchCount: entry.searchCount,
          ),
        );
      }
    } catch (e) {
      Logger.w('Failed to get history suggestions: $e', tag: _tag);
    }

    // 2. Check memory cache for partial matches
    for (final cacheKey in _memoryCache.keys) {
      if (suggestions.length >= limit) break;

      final cachedQuery = cacheKey.split(':').first;
      if (cachedQuery.startsWith(normalized) && cachedQuery != normalized) {
        // Don't add duplicates
        if (!suggestions.any((s) => s.text == cachedQuery)) {
          suggestions.add(
            SearchSuggestion(text: cachedQuery, type: SuggestionType.cached),
          );
        }
      }
    }

    // 3. Get live suggestions from providers (fast timeout)
    if (suggestions.length < limit) {
      try {
        final liveSuggestions = await _searchService.getSuggestions(
          query,
          maxPerProvider: 2,
          maxTotal: limit - suggestions.length,
        );

        for (final item in liveSuggestions) {
          if (suggestions.length >= limit) break;

          // Add as title suggestion
          if (!suggestions.any(
            (s) => s.text.toLowerCase() == item.title.toLowerCase(),
          )) {
            suggestions.add(
              SearchSuggestion(
                text: item.title,
                type: SuggestionType.live,
                mediaItem: item,
              ),
            );
          }
        }
      } catch (e) {
        Logger.w('Failed to get live suggestions: $e', tag: _tag);
      }
    }

    return suggestions.take(limit).toList();
  }

  /// Check if query might have a typo based on fuzzy matching with history
  Future<String?> suggestCorrection(String query) async {
    final normalized = _transliteration.normalizeQuery(query);
    if (normalized.length < 3) return null;

    try {
      // Get successful searches from history
      final successful = await _historyDao.getSuccessful(limit: 50);

      String? bestMatch;
      int bestScore = 0;

      for (final entry in successful) {
        final score = ratio(normalized, entry.normalizedQuery);

        // If similar but not exact, and better than threshold
        if (score >= _fuzzyThreshold && score < 100 && score > bestScore) {
          bestScore = score;
          bestMatch = entry.query;
        }
      }

      return bestMatch;
    } catch (e) {
      Logger.w('Failed to suggest correction: $e', tag: _tag);
      return null;
    }
  }

  /// Get recent searches for display
  Future<List<String>> getRecentSearches({int limit = 10}) async {
    try {
      final history = await _historyDao.getRecent(limit: limit);
      return history.map((e) => e.query).toList();
    } catch (e) {
      Logger.w('Failed to get recent searches: $e', tag: _tag);
      return [];
    }
  }

  /// Clear search history
  Future<void> clearHistory() async {
    try {
      await _historyDao.clearAll();
      Logger.i('Search history cleared', tag: _tag);
    } catch (e) {
      Logger.e('Failed to clear history', tag: _tag, error: e);
    }
  }

  /// Clear memory cache
  void clearCache() {
    _memoryCache.clear();
    _cacheTimestamps.clear();
    Logger.d('Memory cache cleared', tag: _tag);
  }

  // =========================================================================
  // Private methods
  // =========================================================================

  bool _isCacheValid(String key) {
    if (!_memoryCache.containsKey(key)) return false;

    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;

    return DateTime.now().difference(timestamp) < _cacheTtl;
  }

  Future<void> _saveToHistory(
    String query,
    String normalizedQuery,
    int resultCount,
  ) async {
    try {
      await _historyDao.addSearch(
        query: query,
        normalizedQuery: normalizedQuery,
        resultCount: resultCount,
      );
    } catch (e) {
      Logger.w('Failed to save search history: $e', tag: _tag);
    }
  }

  /// Deduplicate results based on title similarity
  List<MediaItem> _deduplicateResults(List<MediaItem> items) {
    if (items.length <= 1) return items;

    final unique = <MediaItem>[];
    final seenTitles = <String>[];

    for (final item in items) {
      final normalizedTitle = item.title.toLowerCase().trim();

      // Check if we've seen a very similar title
      bool isDuplicate = false;
      for (final seen in seenTitles) {
        final similarity = ratio(normalizedTitle, seen);
        if (similarity >= _deduplicationThreshold) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        unique.add(item);
        seenTitles.add(normalizedTitle);
      }
    }

    return unique;
  }

  /// Rank results by relevance to query
  List<MediaItem> _rankResults(List<MediaItem> items, String query) {
    if (items.isEmpty) return items;

    final scored = items.map((item) {
      final score = _calculateRelevanceScore(item, query);
      return _ScoredItem(item, score);
    }).toList();

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.item).toList();
  }

  double _calculateRelevanceScore(MediaItem item, String query) {
    var score = 0.0;
    final normalizedTitle = item.title.toLowerCase().trim();
    final normalizedQuery = query.toLowerCase().trim();

    // Exact match
    if (normalizedTitle == normalizedQuery) {
      score += 100;
    }
    // Starts with query
    else if (normalizedTitle.startsWith(normalizedQuery)) {
      score += 50;
    }
    // Contains query
    else if (normalizedTitle.contains(normalizedQuery)) {
      score += 25;
    }

    // Fuzzy similarity bonus
    final similarity = ratio(normalizedTitle, normalizedQuery);
    score += similarity * 0.3; // 0-30 points

    // Rating bonus
    if (item.rating != null) {
      score += item.rating! * 2; // 0-20 points
    }

    // Year recency bonus (newer = better, for popular searches)
    if (item.year != null) {
      final yearsOld = DateTime.now().year - item.year!;
      if (yearsOld < 5) {
        score += (5 - yearsOld) * 3; // 0-15 points for recent content
      }
    }

    // Has poster bonus
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      score += 10;
    }

    return score;
  }
}

/// Result of smart search
class SmartSearchResult {
  final String originalQuery;
  final String normalizedQuery;
  final List<String> searchVariants;
  final AggregatedSearchResult aggregatedResult;
  final List<MediaItem> rankedItems;
  final Duration totalDuration;
  final bool fromCache;

  const SmartSearchResult({
    required this.originalQuery,
    required this.normalizedQuery,
    required this.searchVariants,
    required this.aggregatedResult,
    required this.rankedItems,
    required this.totalDuration,
    required this.fromCache,
  });

  factory SmartSearchResult.empty(String query) {
    return SmartSearchResult(
      originalQuery: query,
      normalizedQuery: query,
      searchVariants: [],
      aggregatedResult: AggregatedSearchResult(
        query: query,
        providerResults: [],
        totalDuration: Duration.zero,
      ),
      rankedItems: [],
      totalDuration: Duration.zero,
      fromCache: false,
    );
  }

  bool get isEmpty => rankedItems.isEmpty;
  int get totalCount => rankedItems.length;
}

/// Search suggestion type
enum SuggestionType {
  history, // From search history
  cached, // From memory cache
  live, // From live provider search
}

/// Search suggestion item
class SearchSuggestion {
  final String text;
  final SuggestionType type;
  final int? searchCount;
  final MediaItem? mediaItem;

  const SearchSuggestion({
    required this.text,
    required this.type,
    this.searchCount,
    this.mediaItem,
  });
}

/// Helper class for sorting
class _ScoredItem {
  final MediaItem item;
  final double score;

  _ScoredItem(this.item, this.score);
}
