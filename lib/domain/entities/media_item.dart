import 'package:equatable/equatable.dart';

/// Type of media content
enum ContentType { movie, series, cartoon, anime, unknown }

/// Extension to get display name for content type
extension ContentTypeExtension on ContentType {
  String get displayName {
    switch (this) {
      case ContentType.movie:
        return 'Фільм';
      case ContentType.series:
        return 'Серіал';
      case ContentType.cartoon:
        return 'Мультфільм';
      case ContentType.anime:
        return 'Аніме';
      case ContentType.unknown:
        return 'Невідомо';
    }
  }

  String get pluralName {
    switch (this) {
      case ContentType.movie:
        return 'Фільми';
      case ContentType.series:
        return 'Серіали';
      case ContentType.cartoon:
        return 'Мультфільми';
      case ContentType.anime:
        return 'Аніме';
      case ContentType.unknown:
        return 'Контент';
    }
  }

  /// Short name for badges (2-4 chars)
  String get shortName {
    switch (this) {
      case ContentType.movie:
        return 'ФМ';
      case ContentType.series:
        return 'СР';
      case ContentType.cartoon:
        return 'МФ';
      case ContentType.anime:
        return 'АН';
      case ContentType.unknown:
        return '?';
    }
  }
}

/// Basic media item representation (search results, catalog items)
class MediaItem extends Equatable {
  final String id;
  final String providerId;
  final String title;
  final String? originalTitle;
  final String? posterUrl;
  final int? year;
  final double? rating;
  final ContentType type;
  final String? description;
  final List<String>? genres;
  final String? country;

  const MediaItem({
    required this.id,
    required this.providerId,
    required this.title,
    this.originalTitle,
    this.posterUrl,
    this.year,
    this.rating,
    this.type = ContentType.unknown,
    this.description,
    this.genres,
    this.country,
  });

  @override
  List<Object?> get props => [
    id,
    providerId,
    title,
    originalTitle,
    posterUrl,
    year,
    rating,
    type,
    description,
    genres,
    country,
  ];

  /// Unique identifier combining provider and media ID
  String get uniqueId => '$providerId:$id';
}
