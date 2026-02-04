import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../domain/entities/entities.dart';

class YummyAnimeParser {
  static const String baseUrl = 'https://yummyanime.tv';

  static List<MediaItem> parseSearchJson(dynamic json) {
    final items = <MediaItem>[];
    if (json is! List) return items;

    for (final item in json) {
      try {
        final id = item['slug']?.toString() ?? item['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        // Poster usually needs base URL if relative
        var poster = item['poster']?.toString();

        items.add(
          MediaItem(
            id: id,
            providerId: 'yummyanime',
            title: item['title']?.toString() ?? '',
            originalTitle: item['title_orig']?.toString(),
            posterUrl: _absoluteUrl(poster),
            year: int.tryParse(item['year']?.toString() ?? ''),
            rating: double.tryParse(item['rating']?.toString() ?? ''),
            type: ContentType.anime,
          ),
        );
      } catch (e) {
        // skip bad item
      }
    }
    return items;
  }

  static List<MediaItem> parseSearchResults(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // New structure: div.movie-item
    final cards = soup.findAll('div', class_: 'movie-item');
    if (cards.isNotEmpty) {
      for (final card in cards) {
        final item = _parseMovieItem(card);
        if (item != null) items.add(item);
      }
      return items;
    }

    // Legacy fallback
    final oldCards = soup.findAll('div', class_: 'anime-card');
    for (final card in oldCards) {
      final item = _parseCard(card);
      if (item != null) items.add(item);
    }

    // Legacy fallback 2
    final altCards = soup.findAll('article', class_: 'anime-item');
    for (final card in altCards) {
      final item = _parseCard(card);
      if (item != null) items.add(item);
    }

    return items;
  }

  static MediaItem? _parseMovieItem(dynamic card) {
    try {
      final link = card.find('a', class_: 'movie-item__link');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final titleEl = card.find('div', class_: 'movie-item__title');
      final title = titleEl?.text.trim() ?? link.attributes['title'] ?? '';

      String? posterUrl;
      final img = card.find('img');
      posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      int? year;
      final metaEl = card.find('div', class_: 'movie-item__meta');
      if (metaEl != null) {
        final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(metaEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl = card.find('div', class_: 'movie-item__rating');
      if (ratingEl != null) {
        rating = double.tryParse(
          ratingEl.text.trim().replaceAll(RegExp(r'[^\d.]'), ''),
        );
      }

      return MediaItem(
        id: mediaId,
        providerId: 'yummyanime',
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: ContentType.anime,
      );
    } catch (e) {
      return null;
    }
  }

  static MediaItem? _parseCard(dynamic card) {
    try {
      final link = card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      final titleEl =
          card.find('div', class_: 'anime-title') ??
          card.find('div', class_: 'title') ?? // Fallback
          card.find('h3') ??
          card.find('span', class_: 'title');
      final title = titleEl?.text.trim() ?? '';

      int? year;
      final infoEl = card.find('div', class_: 'anime-info');
      if (infoEl != null) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl = card.find('span', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
      }

      return MediaItem(
        id: mediaId,
        providerId: 'yummyanime',
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: ContentType.anime,
      );
    } catch (e) {
      return null;
    }
  }

  static MediaDetails parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    String? originalTitle;
    final origEl = soup.find('div', class_: 'original-title');
    if (origEl != null) {
      originalTitle = origEl.text.trim();
    }

    // Poster
    final posterEl =
        soup.find('div', class_: 'anime-poster') ??
        soup.find('div', class_: 'poster');
    final posterUrl = posterEl?.find('img')?.attributes['src'];

    String? director;
    List<String>? genres;
    int? year;
    String? status;

    final infoBlock =
        soup.find('div', class_: 'anime-info') ??
        soup.find('div', class_: 'full-info');

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('div', class_: 'info-item')) {
        final label =
            row.find('span', class_: 'label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'value');

        if (label.contains('студ')) {
          director = value?.text.trim();
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік')) {
          year = int.tryParse(value?.text.trim() ?? '');
        } else if (label.contains('стату')) {
          status = value?.text.trim();
        }
      }
    }

    // Description
    final descEl =
        soup.find('div', class_: 'anime-description') ??
        soup.find('div', class_: 'full-text') ??
        soup.find('div', class_: 'description');
    final description = descEl?.text.trim();

    double? rating;
    final ratingEl = soup.find('div', class_: 'anime-rating');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: 'yummyanime',
        title: title,
        originalTitle: originalTitle,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: ContentType.anime,
        description: status,
      ),
      fullDescription: description,
      genres: genres,
      director: director,
      seasons: _parseSeasons(soup),
    );
  }

  static List<Season> _parseSeasons(BeautifulSoup soup) {
    final seasons = <Season>[];
    final episodes = <Episode>[];
    final episodeItems = soup.findAll('li', class_: 'episode-item');

    for (final item in episodeItems) {
      final epNum =
          int.tryParse(item.attributes['data-episode'] ?? '') ??
          episodes.length + 1;

      final epTitle =
          item.find('span', class_: 'episode-title')?.text.trim() ??
          'Серія $epNum';

      episodes.add(Episode(number: epNum, title: epTitle));
    }

    if (episodes.isNotEmpty) {
      // YummyAnime usually treats series as one season
      seasons.add(Season(number: 1, episodes: episodes));
    }

    return seasons;
  }

  /// Extracts metadata about episode (data-id, data-episode) to fetch sources
  static List<Map<String, String>> extractEpisodeItems(String html) {
    final soup = BeautifulSoup(html);
    final items = <Map<String, String>>[];
    final episodeItems = soup.findAll('li', class_: 'episode-item');

    for (final item in episodeItems) {
      items.add({
        'episode': item.attributes['data-episode'] ?? '',
        'id': item.attributes['data-id'] ?? '',
      });
    }
    return items;
  }

  /// Parses the JSON response from /api/episode/{id}
  static List<StreamSource> parseEpisodeSources(dynamic json) {
    final sources = <StreamSource>[];
    if (json is! Map<String, dynamic>) return sources;

    final players = json['players'];
    if (players is List) {
      for (final player in players) {
        final url = player['url']?.toString();
        final voiceover =
            player['name']?.toString() ?? player['voice']?.toString();
        final quality = player['quality']?.toString();

        if (url != null && url.isNotEmpty) {
          // Return the URL as a potential source.
          // Repository will handle if it's an embed (needs fetching) or direct.
          // We tag it based on naive check.
          var type = StreamType.direct;
          if (url.contains('.m3u8'))
            type = StreamType.hls;
          else if (url.contains('ashdi') ||
              url.contains('kodik') ||
              url.contains('aniboom')) {
            // These are players, let's treat them as direct but repository will inspect content
            // ACTUALLY: we should mark them so repo knows to fetch content?
            // Let's just return them. Repo logic usually checks URL patterns.
            type = StreamType.direct;
          }

          sources.add(
            StreamSource(
              url: url,
              quality: _parseQuality(quality),
              voiceover: voiceover,
              type: type,
              // We use sourceName to pass hints if needed, or just leave empty
            ),
          );
        }
      }
    }

    // Direct video file
    final videoUrl = json['video']?.toString() ?? json['file']?.toString();
    if (videoUrl != null && videoUrl.isNotEmpty) {
      sources.add(
        StreamSource(
          url: videoUrl,
          quality: StreamQuality.unknown,
          type: videoUrl.contains('.m3u8') ? StreamType.hls : StreamType.direct,
        ),
      );
    }

    return sources;
  }

  /// Parse text content of an embed player to find sources (e.g. Ashdi, generic patterns)
  static List<StreamSource> parseEmbedContent(
    String html, {
    String? voiceover,
  }) {
    final sources = <StreamSource>[];

    // Ashdi pattern
    final ashdiMatch = RegExp(
      r'file\s*:\s*["\x27](https?://[^"\x27]+)["\x27]',
    ).firstMatch(html);
    if (ashdiMatch != null) {
      sources.add(
        StreamSource(
          url: ashdiMatch.group(1)!,
          quality: StreamQuality.unknown,
          voiceover: voiceover,
          type: StreamType.hls,
        ),
      );
    }

    // Generic patterns
    final patterns = [
      RegExp(
        r'src["\s]*:["\s]*["\x27](https?://[^"\x27]+\.m3u8[^"\x27]*)["\x27]',
      ),
      RegExp(r'"hls"["\s]*:["\s]*["\x27](https?://[^"\x27]+)["\x27]'),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final url = match.group(1);
        if (url != null && _isValidStreamUrl(url)) {
          sources.add(
            StreamSource(
              url: url,
              quality: StreamQuality.unknown,
              voiceover: voiceover,
              type: StreamType.hls,
            ),
          );
        }
      }
    }

    return sources;
  }

  static bool _isValidStreamUrl(String url) {
    return url.contains('.m3u8') || url.contains('.mp4');
  }

  static String extractIdFromUrl(String url) {
    if (url.isEmpty) return '';
    final match = RegExp(r'/anime/([^/?#]+)').firstMatch(url);
    if (match != null) {
      return match.group(1) ?? '';
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      // cleanup
      var last = uri.pathSegments.last;
      if (last.isEmpty && uri.pathSegments.length > 1) {
        last = uri.pathSegments[uri.pathSegments.length - 2];
      }
      return last;
    }
    return '';
  }

  static String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }

  static StreamQuality _parseQuality(String? quality) {
    if (quality == null) return StreamQuality.unknown;
    final q = quality.toLowerCase().replaceAll('p', '');
    switch (q) {
      case '360':
        return StreamQuality.q360p;
      case '480':
        return StreamQuality.q480p;
      case '720':
        return StreamQuality.q720p;
      case '1080':
        return StreamQuality.q1080p;
      default:
        return StreamQuality.unknown;
    }
  }
}
