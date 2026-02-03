import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get_it/get_it.dart';

import '../../data/services/settings_service.dart';
import '../../domain/entities/entities.dart';
import '../theme/app_theme.dart';

/// Media item card for grids and lists
class MediaCard extends StatefulWidget {
  final MediaItem item;
  final VoidCallback? onTap;
  final bool isFocused;

  const MediaCard({
    super.key,
    required this.item,
    this.onTap,
    this.isFocused = false,
  });

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _isHovered = false;
  final _settings = GetIt.instance<SettingsService>();

  UISettings get _ui => _settings.uiSettings;
  Color get _accentColor => Color(_ui.accentColor.colorValue);

  @override
  Widget build(BuildContext context) {
    final isFocused = widget.isFocused || _isHovered;
    final animationsEnabled = _ui.animationsEnabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: animationsEnabled
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          transform: isFocused && animationsEnabled
              ? (Matrix4.identity()
                  ..setEntry(0, 0, 1.05)
                  ..setEntry(1, 1, 1.05))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_ui.posterSize.borderRadius),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: _accentColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_ui.posterSize.borderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster image
                _buildPoster(),

                // Gradient overlay (only for overlay style)
                if (_ui.cardInfoStyle == CardInfoStyle.overlay)
                  _buildGradientOverlay(),

                // Content info (only for overlay style)
                if (_ui.cardInfoStyle == CardInfoStyle.overlay)
                  _buildInfoOverlay(),

                // Provider badge (top-left)
                _buildProviderBadge(),

                // Rating badge (top-right)
                if (widget.item.rating != null && _ui.showRatings)
                  _buildRatingBadge(),

                // Focus border
                if (isFocused) _buildFocusBorder(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster() {
    if (widget.item.posterUrl != null) {
      return CachedNetworkImage(
        imageUrl: widget.item.posterUrl!,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: AppTheme.darkCard,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (context, url, error) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.darkCard,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getTypeIcon(), size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (widget.item.type) {
      case ContentType.movie:
        return Icons.movie_outlined;
      case ContentType.series:
        return Icons.tv_outlined;
      case ContentType.cartoon:
        return Icons.animation_outlined;
      case ContentType.anime:
        return Icons.animation;
      default:
        return Icons.video_library_outlined;
    }
  }

  Widget _buildGradientOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 80,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoOverlay() {
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (widget.item.year != null && _ui.showYears) ...[
            const SizedBox(height: 2),
            Text(
              '${widget.item.year}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingBadge() {
    final rating = widget.item.rating!;
    final color = rating >= 7.0
        ? AppTheme.successColor
        : rating >= 5.0
        ? Colors.orange
        : AppTheme.errorColor;

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildProviderBadge() {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.item.providerId.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFocusBorder() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_ui.posterSize.borderRadius),
          border: Border.all(color: _accentColor, width: 3),
        ),
      ),
    );
  }
}
