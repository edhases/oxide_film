import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/database/app_database.dart';
import '../../../data/services/favorites_service.dart';
import '../../../data/services/settings_service.dart';
import '../../../domain/entities/entities.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_titlebar.dart';

/// Favorites page - displays saved media items
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  final _favoritesService = GetIt.instance<FavoritesService>();
  final _settings = GetIt.instance<SettingsService>();
  late TabController _tabController;

  final _tabs = const [
    Tab(text: 'Все'),
    Tab(text: 'Фільми'),
    Tab(text: 'Серіали'),
    Tab(text: 'Мультфільми'),
    Tab(text: 'Аніме'),
  ];

  UISettings get _ui => _settings.uiSettings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _favoritesService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _favoritesService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isDesktop) const CustomTitleBar(),
          _buildAppBar(),
          TabBar(
            controller: _tabController,
            tabs: _tabs,
            isScrollable: true,
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textMuted,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildFavoritesList(null),
                _buildFavoritesList('movie'),
                _buildFavoritesList('series'),
                _buildFavoritesList('cartoon'),
                _buildFavoritesList('anime'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
            tooltip: 'Назад',
          ),
          const SizedBox(width: 8),
          const Icon(Icons.favorite, color: Colors.red),
          const SizedBox(width: 8),
          const Text(
            'Обране',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (_favoritesService.favorites.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _showClearDialog,
              tooltip: 'Очистити все',
            ),
        ],
      ),
    );
  }

  Widget _buildFavoritesList(String? typeFilter) {
    final items = typeFilter == null
        ? _favoritesService.favorites
        : _favoritesService.favorites
              .where((f) => f.mediaType == typeFilter)
              .toList();

    if (items.isEmpty) {
      return _EmptyState(
        icon: Icons.favorite_border,
        title: 'Тут поки порожньо',
        subtitle: typeFilter == null
            ? 'Додайте фільми та серіали в обране'
            : 'Немає елементів у цій категорії',
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
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _FavoriteCard(
          favorite: item,
          onTap: () => _openDetails(item),
          onRemove: () => _removeFavorite(item),
        );
      },
    );
  }

  double _getMaxCrossAxisExtent() {
    switch (_ui.posterSize) {
      case PosterSize.small:
        return _isDesktop ? 130 : 100;
      case PosterSize.medium:
        return _isDesktop ? 180 : 140;
      case PosterSize.large:
        return _isDesktop ? 250 : 180;
    }
  }

  void _openDetails(Favorite item) {
    final encodedId = Uri.encodeComponent(item.mediaId);
    context.push('/details/${item.providerId}/$encodedId');
  }

  void _removeFavorite(Favorite item) {
    _favoritesService.remove(item.mediaId, item.providerId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} видалено з обраного'),
        action: SnackBarAction(
          label: 'Відновити',
          onPressed: () {
            _favoritesService.add(
              MediaItem(
                id: item.mediaId,
                providerId: item.providerId,
                title: item.title,
                posterUrl: item.posterUrl,
                year: item.year,
                type: ContentType.values.firstWhere(
                  (t) => t.name == item.mediaType,
                  orElse: () => ContentType.movie,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Очистити обране?'),
        content: const Text(
          'Ви впевнені, що хочете видалити всі елементи з обраного? '
          'Цю дію неможливо відмінити.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _favoritesService.clearAll();
            },
            child: Text(
              'Очистити',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// WIDGETS
// =============================================================================

class _FavoriteCard extends StatelessWidget {
  final Favorite favorite;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FavoriteCard({
    required this.favorite,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster
            if (favorite.posterUrl != null)
              CachedNetworkImage(
                imageUrl: favorite.posterUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AppTheme.surfaceColor,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => _PosterPlaceholder(),
              )
            else
              _PosterPlaceholder(),

            // Gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      favorite.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (favorite.year != null)
                      Text(
                        '${favorite.year}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Remove button
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceColor,
      child: Center(
        child: Icon(Icons.movie, size: 48, color: AppTheme.textMuted),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
