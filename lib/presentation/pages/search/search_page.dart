import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers/provider_registry.dart';
import '../../../data/services/history_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';
import '../../widgets/media_card.dart';
import '../../widgets/custom_titlebar.dart';

/// Search page with autocomplete suggestions
class SearchPage extends StatefulWidget {
  final String? initialQuery;

  const SearchPage({super.key, this.initialQuery});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _registry = GetIt.instance<ProviderRegistry>();
  final _historyService = GetIt.instance<HistoryService>();
  final _settings = GetIt.instance<SettingsService>();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  List<MediaItem> _results = [];
  List<MediaItem> _suggestions = [];
  bool _isLoading = false;
  bool _isLoadingSuggestions = false;
  String? _error;
  bool _hasSearched = false;
  bool _showSuggestions = false;
  Timer? _debounceTimer;

  // Recent searches
  List<String> _recentSearches = [];

  UISettings get _ui => _settings.uiSettings;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _focusNode.addListener(_onFocusChanged);

    if (widget.initialQuery != null) {
      _searchController.text = widget.initialQuery!;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _searchController.text.isEmpty) {
      setState(() => _showSuggestions = true);
    }
  }

  Future<void> _loadRecentSearches() async {
    // Get recent searches from history titles
    final history = _historyService.history.take(10).toList();
    setState(() {
      _recentSearches = history.map((h) => h.title).toSet().take(5).toList();
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = true;
      });
      return;
    }

    // Debounce for 300ms before fetching suggestions
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(query);
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.length < 2) return;

    setState(() => _isLoadingSuggestions = true);

    try {
      final providers = _registry.enabled;
      final allSuggestions = <MediaItem>[];

      // Only use first provider for faster suggestions
      if (providers.isNotEmpty) {
        try {
          final results = await providers.first.search(query);
          allSuggestions.addAll(results.take(5));
        } catch (e) {
          debugPrint('Suggestions failed: $e');
        }
      }

      if (mounted && _searchController.text == query) {
        setState(() {
          _suggestions = allSuggestions;
          _showSuggestions = true;
          _isLoadingSuggestions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSuggestions = false);
      }
    }
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _hasSearched = true;
      _showSuggestions = false;
    });

    // Add to recent searches
    if (!_recentSearches.contains(query)) {
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 5) {
        _recentSearches = _recentSearches.take(5).toList();
      }
    }

    try {
      final providers = _registry.enabled;
      final allResults = <MediaItem>[];

      for (final provider in providers) {
        try {
          final results = await provider.search(query);
          allResults.addAll(results);
        } catch (e) {
          debugPrint('Search failed for ${provider.name}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _results = allResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _selectSuggestion(MediaItem item) {
    setState(() => _showSuggestions = false);
    context.push('/details/${item.providerId}/${Uri.encodeComponent(item.id)}');
  }

  void _useRecentSearch(String query) {
    _searchController.text = query;
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Scaffold(
      body: Column(
        children: [
          if (isDesktop) const CustomTitleBar(),
          _buildSearchBar(),
          if (_showSuggestions) _buildSuggestions(),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.darkSurface,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Пошук фільмів, серіалів...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLoadingSuggestions)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _suggestions = [];
                            _hasSearched = false;
                            _showSuggestions = true;
                          });
                        },
                      ),
                  ],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.darkCard,
              ),
              onSubmitted: (_) => _performSearch(),
              onChanged: _onSearchChanged,
              onTap: () => setState(() => _showSuggestions = true),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _performSearch,
            child: const Text('Знайти'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      color: AppTheme.darkSurface,
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView(
        shrinkWrap: true,
        children: [
          // Recent searches
          if (_searchController.text.isEmpty && _recentSearches.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Нещодавні пошуки',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ..._recentSearches.map(
              (query) => ListTile(
                leading: const Icon(Icons.history),
                title: Text(query),
                dense: true,
                onTap: () => _useRecentSearch(query),
              ),
            ),
          ],

          // Search suggestions
          if (_suggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Пропозиції',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ..._suggestions.map(
              (item) => ListTile(
                leading: item.posterUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          item.posterUrl!,
                          width: 40,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.movie, size: 40),
                        ),
                      )
                    : const Icon(Icons.movie, size: 40),
                title: Text(item.title),
                subtitle: Text(
                  '${item.type.displayName}${item.year != null ? ' • ${item.year}' : ''}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                dense: true,
                onTap: () => _selectSuggestion(item),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Помилка: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _performSearch,
              child: const Text('Спробувати знову'),
            ),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              'Введіть запит для пошуку',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_filter, size: 80, color: AppTheme.textMuted),
            const SizedBox(height: 16),
            Text(
              'Нічого не знайдено',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Спробуйте інший запит',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(_ui.gridSpacing.padding),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _getMaxCrossAxisExtent(),
        childAspectRatio: _ui.posterSize.aspectRatio,
        crossAxisSpacing: _ui.gridSpacing.crossAxisSpacing,
        mainAxisSpacing: _ui.gridSpacing.mainAxisSpacing,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return MediaCard(
          item: item,
          onTap: () => context.push(
            '/details/${item.providerId}/${Uri.encodeComponent(item.id)}',
          ),
        );
      },
    );
  }

  double _getMaxCrossAxisExtent() {
    switch (_ui.posterSize) {
      case PosterSize.small:
        return 130;
      case PosterSize.medium:
        return 180;
      case PosterSize.large:
        return 250;
    }
  }
}
