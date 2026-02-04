import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';

class HDRezkaParser {
  static const String _tag = 'HDRezkaParser';

  static List<MediaItem> parseSearchResults(String html, String providerId) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];
    final addedIds = <String>{};

    final cards = soup.findAll('div', class_: 'b-content__inline_item');
    Logger.d('Parsing ${cards.length} cards', tag: _tag);

    for (final card in cards) {
      try {
        final link = card.find('a');
        if (link == null) continue;

        final href = link.attributes['href'] ?? '';
        final mediaId = extractIdFromUrl(href);
        if (mediaId.isEmpty) continue;

        // Deduplicate
        if (addedIds.contains(mediaId)) continue;

        final img = card.find('img');
        final posterUrl = img?.attributes['src'];

        // Try multiple ways to get title
        var title = '';
        final titleEl = card.find('div', class_: 'b-content__inline_item-link');
        if (titleEl != null) {
          title = titleEl.find('a')?.text.trim() ?? titleEl.text.trim();
        }
        // Fallback: try img alt
        if (title.isEmpty && img != null) {
          title =
              img.attributes['alt']
                  ?.replaceFirst('Смотреть ', '')
                  .replaceFirst(' онлайн в HD качестве 720p', '')
                  .trim() ??
              '';
        }

        // Skip invalid items
        if (title.isEmpty) continue;

        final infoEl = card.find('div', class_: 'misc');
        final infoText = infoEl?.text ?? '';

        int? year;
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoText);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }

        // Fallback: search in card text
        if (year == null) {
          final yearMatch = RegExp(
            r'\b(19\d{2}|20\d{2})\b',
          ).firstMatch(card.text);
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(1) ?? '');
          }
        }

        // Try to extract genres
        List<String>? genres;
        final genreEl = card.find(
          'div',
          class_: 'b-content__inline_item-genre',
        );
        if (genreEl != null) {
          final genreLinks = genreEl.findAll('a');
          if (genreLinks.isNotEmpty) {
            genres = genreLinks
                .map((a) => a.text.trim())
                .where((g) => g.isNotEmpty)
                .toList();
          }
        }
        // Fallback: parse from misc text
        if ((genres == null || genres.isEmpty) && infoText.contains(',')) {
          final parts = infoText.split(',');
          if (parts.length > 1) {
            // First part usually contains year, rest may be country/genre
            final possibleGenre = parts
                .skip(1)
                .map((p) => p.trim())
                .where((p) => !RegExp(r'^\d{4}$').hasMatch(p) && p.isNotEmpty)
                .toList();
            if (possibleGenre.isNotEmpty) {
              genres = possibleGenre;
            }
          }
        }

        // Try to extract country
        String? country;
        final countryMatch = RegExp(
          r'(?:^|,|\d{4},?)\s*([A-ZА-ЯЁ]{2,}|[A-Z][a-z]+|[А-ЯЁ][а-яё]+)',
        ).firstMatch(infoText);
        if (countryMatch != null) {
          country = countryMatch.group(1);
        }

        final type = detectContentType(href);

        items.add(
          MediaItem(
            id: mediaId,
            providerId: providerId,
            title: title,
            posterUrl: posterUrl,
            year: year,
            type: type,
            genres: genres,
            country: country,
          ),
        );
        addedIds.add(mediaId);
      } catch (e) {
        Logger.w('Failed to parse card', tag: _tag);
      }
    }

    return items;
  }

  static MediaDetails parseDetails(
    String html,
    String mediaId,
    String providerId,
  ) {
    final soup = BeautifulSoup(html);
    Logger.d('Parsing details for: $mediaId', tag: _tag);

    // Title
    final titleEl = soup.find('div', class_: 'b-post__title');
    var title = titleEl?.find('h1')?.text.trim() ?? '';
    final originalTitle = titleEl?.find('span')?.text.trim();

    // Fallback: try page title
    if (title.isEmpty) {
      final pageTitle = soup.find('title');
      if (pageTitle != null) {
        title = pageTitle.text
            .replaceAll('смотреть онлайн', '')
            .replaceAll('HDRezka', '')
            .trim();
      }
    }
    Logger.d('Title: $title', tag: _tag);

    // Poster
    final posterEl = soup.find('div', class_: 'b-sidecover');
    final posterUrl = posterEl?.find('img')?.attributes['src'];

    // Info table
    final infoTable = soup.find('table', class_: 'b-post__info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    Duration? duration;

    if (infoTable != null) {
      for (final row in infoTable.findAll('tr')) {
        final label = row.find('td', class_: 'l')?.text.toLowerCase() ?? '';
        final value = row.find('td', class_: 'r');

        if (label.contains('режисер') || label.contains('режисс')) {
          director = value?.text.trim();
        } else if (label.contains('актор') || label.contains('актер')) {
          actors = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('країн') || label.contains('стран')) {
          countries = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік') || label.contains('год')) {
          final yearMatch = RegExp(r'(\d{4})').firstMatch(value?.text ?? '');
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(1) ?? '');
          }
        } else if (label.contains('час') || label.contains('врем')) {
          final durMatch = RegExp(r'(\d+)\s*хв').firstMatch(value?.text ?? '');
          if (durMatch != null) {
            duration = Duration(minutes: int.parse(durMatch.group(1)!));
          }
        }
      }
    }

    // Fallback: search in text if table parsing failed
    if (year == null) {
      final yearMatch = RegExp(
        r'(?:Рік|Год|Year):\s*(\d{4})',
        caseSensitive: false,
      ).firstMatch(soup.text);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'b-post__description_text');
    final description = descEl?.text.trim();

    // Rating
    double? rating;
    final ratingEl = soup.find('span', class_: 'b-post__info-rates');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    // Seasons for series
    List<Season>? seasons;
    final seasonsNav = soup.find('ul', id: 'simple-seasons-tabs');
    if (seasonsNav != null) {
      seasons = _parseSeasons(soup);
    }

    final type = detectContentType('/$mediaId.html');

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: providerId,
        title: title,
        originalTitle: originalTitle,
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        type: type,
      ),
      fullDescription: description,
      genres: genres,
      countries: countries,
      director: director,
      actors: actors,
      duration: duration,
      seasons: seasons,
    );
  }

  static List<Season> _parseSeasons(BeautifulSoup soup) {
    final seasons = <Season>[];

    final seasonTabs = soup.findAll('li', class_: 'b-simple_season__item');
    final episodeLists = soup.findAll('ul', class_: 'b-simple_episodes__list');

    for (int i = 0; i < seasonTabs.length; i++) {
      final seasonNum =
          int.tryParse(seasonTabs[i].attributes['data-tab_id'] ?? '') ?? i + 1;

      final episodes = <Episode>[];
      if (i < episodeLists.length) {
        for (final epItem in episodeLists[i].findAll('li')) {
          final epNum =
              int.tryParse(epItem.attributes['data-episode_id'] ?? '') ?? 0;
          final epTitle = epItem.text.trim();

          episodes.add(Episode(number: epNum, title: epTitle));
        }
      }

      seasons.add(Season(number: seasonNum, episodes: episodes));
    }

    return seasons;
  }

  static String extractIdFromUrl(String url) {
    // Format: https://hdrezka.ag/film
    if (url.startsWith('/')) {
      final path = url.substring(1).replaceAll('.html', '');
      return path;
    }
    final match = RegExp(
      r'/([^/]+(?:/[^/]+)?)/(\d+-[^/]+)\.html',
    ).firstMatch(url);
    if (match != null) {
      return match.group(1) ?? '';
    }
    // Fallback: just extract path
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.isNotEmpty) {
      var path = uri.path;
      if (path.endsWith('.html')) {
        path = path.substring(0, path.length - 5);
      }
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      return path;
    }
    return '';
  }

  static ContentType detectContentType(String url) {
    if (url.contains('/films/')) return ContentType.movie;
    if (url.contains('/series/')) return ContentType.series;
    if (url.contains('/cartoons/')) return ContentType.cartoon;
    if (url.contains('/animation/')) return ContentType.anime;
    return ContentType.unknown;
  }

  static String decodeStreamUrl(String encoded) {
    // HDRezka uses a specific encoding with trash strings inserted
    try {
      if (encoded.isEmpty) return encoded;

      var decoded = encoded;

      // HDRezka encoding: #X + base64 where X is version marker (h, 0, etc)
      if (encoded.startsWith('#')) {
        // Remove # prefix and version marker (2 chars total: # + version)
        var base64Part = encoded;
        if (encoded.length > 2 &&
            (encoded.startsWith('#h') ||
                encoded.startsWith('#0') ||
                encoded.startsWith('#1') ||
                encoded.startsWith('#2'))) {
          base64Part = encoded.substring(2);
        } else {
          base64Part = encoded.substring(1);
        }

        // HDRezka inserts specific trash strings that decode to garbage like $$!!@$^&
        final knownTrash = [
          '//_//JCQhIUAkXiY=', // $$!!@$^&
          '//_//QEBAQEAhIyM=', // @@@@@!##
          '//_//Xl5eIyo=', // ^^^#*
          '//_//JCQkISE=', // $$$!!
          '//IyMhQEBA', // ##!@@@
          '//QCMjQEA=', // @##@@
          '//_//JCQhIUAkJEBeIUAjJCRA', // longer variant
          '//_//QEBAQEAhIyMhXl5e', // another variant
          '//_//Xl5eIUAjIyEhIyM=', // another variant
        ];

        for (final trash in knownTrash) {
          base64Part = base64Part.replaceAll(trash, '');
        }

        // Also remove any remaining // markers followed by short base64 ending with =
        base64Part = base64Part.replaceAll(
          RegExp(r'//[A-Za-z0-9+/]{1,25}='),
          '',
        );

        // Clean any remaining //
        base64Part = base64Part.replaceAll('//', '');

        // Remove underscore that might remain
        base64Part = base64Part.replaceAll('_', '');

        // Standard base64 decode
        try {
          while (base64Part.length % 4 != 0) {
            base64Part += '=';
          }
          decoded = utf8.decode(base64.decode(base64Part));
        } catch (e) {
          try {
            decoded = latin1.decode(base64.decode(base64Part));
            decoded = decoded.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
          } catch (e2) {
            decoded = encoded;
          }
        }
      }

      return decoded;
    } catch (e) {
      Logger.w('Stream URL decode failed: $e', tag: _tag);
      return encoded;
    }
  }

  static String normalizeStreamUrl(String url) {
    if (url.contains(' or ')) {
      url = url.split(' or ').first;
    }

    final hlsPattern = RegExp(r':hls:.*$');
    if (hlsPattern.hasMatch(url)) {
      url = url.replaceAll(hlsPattern, '');
    }

    final mp4EndPattern = RegExp(r'(\.mp4).*$');
    if (mp4EndPattern.hasMatch(url) && !url.endsWith('.mp4')) {
      url = url.replaceAllMapped(mp4EndPattern, (m) => m.group(1)!);
    }

    url = url.replaceAll(RegExp(r'[\s\r\n,]+$'), '');
    url = url.replaceAll(RegExp(r'[<>{}|\\^`\x00-\x1F\x7F-\xFF]'), '');

    return url.trim();
  }

  static bool isValidStreamUrl(String url) {
    if (!url.startsWith('http')) return false;
    if (url.contains('undefined')) return false;
    if (url.length < 20) return false;
    // Must end with video extension
    if (!url.endsWith('.mp4') &&
        !url.endsWith('.m3u8') &&
        !url.endsWith('.ts')) {
      return false;
    }
    // Check for garbage characters that indicate decoding issues
    if (url.contains('##') ||
        url.contains('@@') ||
        url.contains('^^') ||
        url.contains('!!') ||
        url.contains('<') ||
        url.contains('>')) {
      return false;
    }
    return true;
  }

  static StreamQuality parseQuality(String? quality) {
    switch (quality) {
      case '360':
        return StreamQuality.q360p;
      case '480':
        return StreamQuality.q480p;
      case '720':
        return StreamQuality.q720p;
      case '1080':
        return StreamQuality.q1080p;
      case '1440':
      case '2k':
        return StreamQuality.q1440p;
      case '2160':
      case '4k':
        return StreamQuality.q4k;
      default:
        return StreamQuality.unknown;
    }
  }
}
