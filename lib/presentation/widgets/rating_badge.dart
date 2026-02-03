import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Rating badge showing ratings from multiple sources
///
/// Displays provider rating, TMDb rating, and MAL rating side-by-side
class RatingBadge extends StatelessWidget {
  final double? providerRating;
  final double? tmdbRating;
  final double? malRating;
  final bool compact;

  const RatingBadge({
    super.key,
    this.providerRating,
    this.tmdbRating,
    this.malRating,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final ratings = <Widget>[];

    // Provider rating
    if (providerRating != null) {
      ratings.add(
        _RatingChip(
          value: providerRating!,
          icon: Icons.star,
          color: AppTheme.primaryColor,
          label: compact ? null : 'Провайдер',
        ),
      );
    }

    // TMDb rating
    if (tmdbRating != null) {
      ratings.add(
        _RatingChip(
          value: tmdbRating!,
          icon: Icons.movie,
          color: const Color(0xFF01D277), // TMDb green
          label: compact ? null : 'TMDb',
        ),
      );
    }

    // MAL rating
    if (malRating != null) {
      ratings.add(
        _RatingChip(
          value: malRating!,
          icon: Icons.auto_awesome,
          color: const Color(0xFF2E51A2), // MAL blue
          label: compact ? null : 'MAL',
        ),
      );
    }

    if (ratings.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 8, runSpacing: 4, children: ratings);
  }
}

class _RatingChip extends StatelessWidget {
  final double value;
  final IconData icon;
  final Color color;
  final String? label;

  const _RatingChip({
    required this.value,
    required this.icon,
    required this.color,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label!,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Single rating display (for cards)
class RatingStar extends StatelessWidget {
  final double? rating;
  final Color? color;
  final bool showValue;

  const RatingStar({super.key, this.rating, this.color, this.showValue = true});

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();

    final displayColor = color ?? Colors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 12, color: displayColor),
          if (showValue) ...[
            const SizedBox(width: 2),
            Text(
              rating!.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trailer button for playing YouTube trailers
class TrailerButton extends StatelessWidget {
  final String? trailerUrl;
  final VoidCallback? onTap;

  const TrailerButton({super.key, this.trailerUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (trailerUrl == null) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_circle_outline),
      label: const Text('Трейлер'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
      ),
    );
  }
}
