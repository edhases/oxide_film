import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers/provider_registry.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/episode_update_service.dart';
import '../../../domain/entities/entities.dart';
import '../../widgets/media_card.dart';
import '../../widgets/custom_titlebar.dart';
import '../../widgets/filter_sheet.dart';
import '../../widgets/new_episodes_widget.dart';

/// Home page with content browsing
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _registry = GetIt.instance<ProviderRegistry>();
  final _settings = GetIt.instance<SettingsService>();
  final _episodeUpdateService = GetIt.instance<EpisodeUpdateService>();
  final _scrollController = ScrollController();

  List<MediaItem> _allItems = [];
  List<MediaItem> _filteredItems = [];
  bool _isLoading = true;
  String? _error;
  ContentFilter _filter = const ContentFilter();

  // For D-Pad navigation
  final int _focusedIndex = 0;

  UISettings get _ui => _settings.uiSettings;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _loadContent();

    // Check for new episodes on startup
    _episodeUpdateService.checkForUpdates();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContent() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final providers = _registry.enabled;
      final allItems = <MediaItem>[];
      final seenIds = <String>{};

      for (final provider in providers) {
        try {
          final items = await provider.getPopular(page: 1);
          for (final item in items) {
            // Deduplicate by unique ID
            if (!seenIds.contains(item.uniqueId)) {
              seenIds.add(item.uniqueId);
              allItems.add(item);
            }
          }
        } catch (e) {
          // Continue with other providers
          debugPrint('Failed to load from ${provider.name}: $e');
        }
      }

      if (mounted) {
        setState(() {
          _allItems = allItems;
          _applyFilter();
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

  void _applyFilter() {
    _filteredItems = _filter.apply(_allItems);
  }

  Future<void> _showFilterSheet() async {
    final newFilter = await FilterSheet.show(context, initialFilter: _filter);
    if (newFilter != null && mounted) {
      setState(() {
        _filter = newFilter;
        _applyFilter();
      });
    }
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
          // Custom titlebar for desktop
          if (isDesktop) const CustomTitleBar(),

          // Main content
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNav(),
    );
  }

  Widget _buildBody() {
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
            Text(
              'Помилка завантаження',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadContent,
              child: const Text('Спробувати знову'),
            ),
          ],
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filter.hasActiveFilters
                  ? Icons.filter_alt_off
                  : Icons.movie_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _filter.hasActiveFilters
                  ? 'Нічого не знайдено'
                  : 'Немає контенту',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _filter.hasActiveFilters
                  ? 'Спробуйте змінити фільтри'
                  : 'Спробуйте пошукати щось',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_filter.hasActiveFilters) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => setState(() {
                  _filter = const ContentFilter();
                  _applyFilter();
                }),
                icon: const Icon(Icons.clear_all),
                label: const Text('Скинути фільтри'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadContent,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App bar
          SliverAppBar(
            floating: true,
            title: const Text('Oxide Film'),
            actions: [
              // Filter button
              FilterButton(filter: _filter, onTap: _showFilterSheet),
              // Sort button
              SortButton(
                currentSort: _filter.sortBy,
                direction: _filter.sortDirection,
                onSortChanged: (sort) => setState(() {
                  _filter = _filter.copyWith(sortBy: sort);
                  _applyFilter();
                }),
                onDirectionChanged: (dir) => setState(() {
                  _filter = _filter.copyWith(sortDirection: dir);
                  _applyFilter();
                }),
              ),
              // New episodes notification
              const NewEpisodesButton(),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => context.push('/search'),
                tooltip: 'Пошук',
              ),
              IconButton(
                icon: const Icon(Icons.favorite_border),
                onPressed: () => context.push('/favorites'),
                tooltip: 'Обране',
              ),
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () => context.push('/history'),
                tooltip: 'Історія',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => context.push('/settings'),
                tooltip: 'Налаштування',
              ),
            ],
          ),

          // Quick filter chips
          if (_filter.hasActiveFilters)
            SliverToBoxAdapter(
              child: QuickFilterChips(
                filter: _filter,
                onFilterChanged: (newFilter) => setState(() {
                  _filter = newFilter;
                  _applyFilter();
                }),
              ),
            ),

          // Categories section
          SliverToBoxAdapter(child: _buildCategoriesSection()),

          // Section title
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _filter.hasActiveFilters
                          ? 'Результати (${_filteredItems.length})'
                          : 'Популярне',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Media grid with Focus support for D-Pad
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: _ui.gridSpacing.padding),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _getMaxCrossAxisExtent(),
                childAspectRatio: _ui.posterSize.aspectRatio,
                crossAxisSpacing: _ui.gridSpacing.crossAxisSpacing,
                mainAxisSpacing: _ui.gridSpacing.mainAxisSpacing,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _filteredItems[index];
                return Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.select) {
                      _onItemTap(item);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MediaCard(
                    item: item,
                    onTap: () => _onItemTap(item),
                    isFocused: _focusedIndex == index,
                  ),
                );
              }, childCount: _filteredItems.length),
            ),
          ),

          // Bottom padding
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Головна',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.search_outlined),
          activeIcon: Icon(Icons.search),
          label: 'Пошук',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite_outline),
          activeIcon: Icon(Icons.favorite),
          label: 'Улюблене',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.history_outlined),
          activeIcon: Icon(Icons.history),
          label: 'Історія',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 1:
            context.push('/search');
            break;
          case 2:
            context.push('/favorites');
            break;
          case 3:
            context.push('/history');
            break;
        }
      },
    );
  }

  Widget _buildCategoriesSection() {
    final categories = [
      (ContentType.movie, Icons.movie, Colors.blue),
      (ContentType.series, Icons.tv, Colors.green),
      (ContentType.cartoon, Icons.animation, Colors.orange),
      (ContentType.anime, Icons.auto_awesome, Colors.pink),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Text(
                'Категорії',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/category'),
                child: const Text('Всі →'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final (type, icon, color) = categories[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CategoryCard(
                  type: type,
                  icon: icon,
                  color: color,
                  onTap: () => context.push('/category?type=${type.name}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _onItemTap(MediaItem item) {
    context.push('/details/${item.providerId}/${Uri.encodeComponent(item.id)}');
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

/// Category card widget
class _CategoryCard extends StatelessWidget {
  final ContentType type;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.type,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: Card(
        color: color.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(
                type.pluralName,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
