import 'package:equatable/equatable.dart';
import 'media_item.dart';

/// Detailed media information including seasons/episodes
class MediaDetails extends Equatable {
  final MediaItem item;
  final String? fullDescription;
  final List<String>? genres;
  final List<String>? countries;
  final String? director;
  final List<String>? actors;
  final Duration? duration;
  final String? trailerUrl;
  final List<Season>? seasons; // For series/anime

  const MediaDetails({
    required this.item,
    this.fullDescription,
    this.genres,
    this.countries,
    this.director,
    this.actors,
    this.duration,
    this.trailerUrl,
    this.seasons,
  });

  bool get isSeries => seasons != null && seasons!.isNotEmpty;

  @override
  List<Object?> get props => [
    item,
    fullDescription,
    genres,
    countries,
    director,
    actors,
    duration,
    trailerUrl,
    seasons,
  ];
}

/// Season of a series
class Season extends Equatable {
  final int number;
  final String? title;
  final List<Episode> episodes;

  const Season({required this.number, this.title, required this.episodes});

  @override
  List<Object?> get props => [number, title, episodes];
}

/// Episode of a season
class Episode extends Equatable {
  final int number;
  final String? title;
  final String? thumbnailUrl;
  final Duration? duration;

  const Episode({
    required this.number,
    this.title,
    this.thumbnailUrl,
    this.duration,
  });

  @override
  List<Object?> get props => [number, title, thumbnailUrl, duration];
}
