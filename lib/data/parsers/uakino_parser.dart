import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';

/// Pure Dart parser for UAKino.best
class UakinoParser {
  static const String _tag = 'UakinoParser';
  static const String baseUrl = 'https://uakino.best';

  /// Parse catalog page (Popular, New, Category, Search Results)
  static List<MediaItem> parseCatalog(String html) {
    final items = <MediaItem>[];
    final soup = BeautifulSoup(html);

    // Try CSS selector first
    var cards = soup.findAll('div', class_: 'movie-item');

    // If empty, try manual search
    if (cards.isEmpty) {
      cards = soup.findAll('div').where((div) {
        final className = div.attributes['class'] ?? '';
        return className.contains('movie-item') ||
            className.contains('short-item');
      }).toList();
    }

    if (cards.isNotEmpty) {
      for (final card in cards) {
        try {
          // Get link and title
          final link =
              card.find('a', class_: 'movie-title') ??
              card.find('a', class_: 'short-title') ??
              card
                  .findAll('a')
                  .where((a) => a.text.trim().isNotEmpty)
                  .firstOrNull;
          if (link == null) continue;

          final href = link.attributes['href'] ?? '';
          var title = link.text.trim();

          if (title.isEmpty) {
            title = card.find('div', class_: 'movie-title')?.text.trim() ?? '';
          }

          if (title.isEmpty) continue;

          final itemId = _extractItemId(href);

          // Get poster
          final img = card.find('img');
          final posterUrl =
              img?.attributes['src'] ?? img?.attributes['data-src'];

          // Get year if available
          final yearEl =
              card.find('div', class_: 'movie-year') ??
              card.find('span', class_: 'year');
          var year = yearEl != null ? int.tryParse(yearEl.text.trim()) : null;

          // Fallback: search in text if year is null
          if (year == null) {
            final yearMatch = RegExp(
              r'\b(19\d{2}|20[0-3]\d)\b',
            ).firstMatch(card.text);
            if (yearMatch != null) {
              year = int.tryParse(yearMatch.group(1) ?? '');
            }
          }

          // Get rating if available
          final ratingEl =
              card.find('div', class_: 'movie-rating') ??
              card.find('span', class_: 'rating');
          final rating = ratingEl != null
              ? double.tryParse(ratingEl.text.trim().replaceAll(',', '.'))
              : null;
          final ratingSource = rating != null ? 'Site' : null;

          // Get genres if available
          List<String>? genres;
          final genreEl =
              card.find('div', class_: 'movie-genre') ??
              card.find('span', class_: 'genre');
          if (genreEl != null) {
            final genreLinks = genreEl.findAll('a');
            if (genreLinks.isNotEmpty) {
              genres = genreLinks
                  .map((a) => a.text.trim())
                  .where((g) => g.isNotEmpty)
                  .toList();
            }
          }

          // Get country if available
          String? country;
          final countryEl = card.find('div', class_: 'movie-country');
          if (countryEl != null) {
            country = countryEl.text.trim().split(',').first.trim();
          }

          items.add(
            MediaItem(
              id: itemId,
              providerId: 'uakino',
              title: title,
              posterUrl: _normalizeImageUrl(posterUrl),
              year: year,
              rating: rating,
              ratingSource: ratingSource,
              type: _detectType(href),
              genres: genres,
              country: country,
              originalTitle: card
                  .find('div', class_: 'movie-title-orig')
                  ?.text
                  .trim(),
            ),
          );
        } catch (e) {
          Logger.w('Failed to parse card', tag: _tag);
        }
      }
    } else {
      // Fallback to link parsing if no cards found
      final allLinks = soup.findAll('a');
      for (final link in allLinks) {
        try {
          final href = link.attributes['href'] ?? '';

          // Skip non-movie links
          if (!href.contains('.html') ||
              href.contains('page/') ||
              href.contains('abuse') ||
              href.contains('news/') && !href.contains('news_id') ||
              href.contains('soundtracks') ||
              href.contains('search-torrents') ||
              href.contains('user/') ||
              href.contains('/colections/') ||
              href.contains('favorites') ||
              href.contains('emoticon') ||
              href.contains('telegram') ||
              href.contains('twitter')) {
            continue;
          }

          final moviePattern = RegExp(
            r'/(filmy|seriesss|cartoon|animeukr)/[^/]+/\d+-',
          );
          final shortPattern = RegExp(r'/\d+-[^/]+\.html$');

          if (!moviePattern.hasMatch(href) && !shortPattern.hasMatch(href)) {
            continue;
          }

          var title = link.text.trim();
          if (title.isEmpty || title.length < 3) {
            final parent = link.parent;
            if (parent != null) {
              final titleLink = parent
                  .findAll('a')
                  .where(
                    (a) => a.text.trim().isNotEmpty && a.text.trim().length > 3,
                  );
              if (titleLink.isNotEmpty) {
                title = titleLink.first.text.trim();
              }
            }
          }

          if (title.isEmpty || title.length < 3) continue;

          final itemId = _extractItemId(href);

          if (items.any((i) => i.id == itemId)) continue;

          String? posterUrl;
          final img = link.find('img');
          if (img != null) {
            posterUrl =
                img.attributes['src'] ?? img.attributes['data-src'] ?? '';
          }
          if ((posterUrl == null || posterUrl.isEmpty) && link.parent != null) {
            final parentImg = link.parent!.find('img');
            if (parentImg != null) {
              posterUrl =
                  parentImg.attributes['src'] ??
                  parentImg.attributes['data-src'];
            }
          }

          items.add(
            MediaItem(
              id: itemId,
              providerId: 'uakino',
              title: title,
              posterUrl: _normalizeImageUrl(posterUrl),
              year: null, // Harder to get from link
              rating: null,
              type: _detectType(href),
            ),
          );
        } catch (e) {
          // skip
        }
      }
    }

    // Deduplicate
    final uniqueItems = <String, MediaItem>{};
    for (final item in items) {
      if (!uniqueItems.containsKey(item.id)) {
        uniqueItems[item.id] = item;
      }
    }

    return uniqueItems.values.toList();
  }

  /// Parse details page
  static MediaDetails parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl =
        soup.find('h1', class_: 'solototle') ??
        soup.find('h1', class_: 'short-title') ??
        soup.find('h1') ??
        soup.find('title');
    final title = titleEl?.text.trim() ?? mediaId;

    // Poster
    String? posterUrl;
    final posterSelectors = [
      () => soup.find('div', class_: 'fposter')?.find('img'),
      () => soup.find('div', class_: 'film-poster')?.find('img'),
      () => soup.find('div', class_: 'poster')?.find('img'),
      () => soup.find('img', class_: 'fimg'),
      () => soup.find('img', class_: 'film-img'),
      () => soup.find('img', attrs: {'itemprop': 'image'}),
      () => soup.find('a', class_: 'fancybox')?.find('img'),
      () => soup.find('div', class_: 'short-img')?.find('img'),
      () => soup.find('div', class_: 'fimg-d')?.find('img'),
    ];

    for (final selector in posterSelectors) {
      final img = selector();
      if (img != null) {
        posterUrl = img.attributes['src'] ?? img.attributes['data-src'];
        if (posterUrl != null && posterUrl.isNotEmpty) break;
      }
    }

    // Description
    String? description;
    final descSelectors = [
      () => soup.find('div', class_: 'fdesc'),
      () => soup.find('div', class_: 'full-text'),
      () => soup.find('div', class_: 'full_content'),
      () => soup.find('div', class_: 'ftext'),
      () => soup.find('div', class_: 'fcontent'),
      () => soup.find('div', attrs: {'itemprop': 'description'}),
      () => soup.find('p', class_: 'story'),
      () => soup.find('div', class_: 'short-story'),
    ];

    for (final selector in descSelectors) {
      final el = selector();
      if (el != null) {
        final desc = el.text.trim();
        if (desc.isNotEmpty && desc.length > 20) {
          description = desc;
          break;
        }
      }
    }

    // Info Table - Revised for new structure
    final infoTable =
        soup.find('div', class_: 'film-info') ??
        soup.find('div', class_: 'flist');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    String? originalTitle;
    double? imdbRating;
    double? siteRating;

    // Try Schema.org first (accurate and structured)
    final directorMeta = soup.find('meta', attrs: {'itemprop': 'director'});
    if (directorMeta != null) director = directorMeta.attributes['content'];

    final genreMeta = soup.find('meta', attrs: {'itemprop': 'genre'});
    if (genreMeta != null) {
      genres = genreMeta.attributes['content']
          ?.split(',')
          .map((e) => e.trim())
          .toList();
    }

    final dateMeta = soup.find('meta', attrs: {'itemprop': 'dateCreated'});
    if (dateMeta != null) {
      final dateStr = dateMeta.attributes['content'];
      if (dateStr != null && dateStr.length >= 4) {
        year = int.tryParse(dateStr.substring(0, 4));
      }
    }

    final actorsMeta = soup.find('meta', attrs: {'itemprop': 'actors'});
    if (actorsMeta != null) {
      actors = actorsMeta.attributes['content']
          ?.split(',')
          .map((e) => e.trim())
          .toList();
    }

    // Original Title
    final originTitleEl =
        soup.find('span', class_: 'origintitle') ??
        soup.find('meta', attrs: {'itemprop': 'alternateName'});
    originalTitle =
        originTitleEl?.text.trim() ??
        originTitleEl?.attributes['content']?.trim();
    if (originalTitle != null) {
      originalTitle = originalTitle
          .replaceFirst(RegExp(r'\d+\s+season.*$', caseSensitive: false), '')
          .trim();
    }

    if (infoTable != null) {
      final rows =
          infoTable.findAll('div', class_: 'fi-item-s') +
          infoTable.findAll('li') +
          infoTable.findAll('div', class_: 'fi-item');
      for (final row in rows) {
        final label =
            row.find('div', class_: 'fi-label')?.text.toLowerCase() ??
            row.text.toLowerCase().split(':').first;
        final desc = row.find('div', class_: 'fi-desc') ?? row;

        if (label.contains('режисер')) {
          director ??=
              desc.find('a')?.text.trim() ?? desc.text.split(':').last.trim();
        } else if (label.contains('актор')) {
          if (actors == null || actors.isEmpty) {
            actors = desc.findAll('a').map((a) => a.text.trim()).toList();
            if (actors.isEmpty) {
              actors = desc.text
                  .split(':')
                  .last
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          }
        } else if (label.contains('жанр')) {
          if (genres == null || genres.isEmpty) {
            genres = desc.findAll('a').map((a) => a.text.trim()).toList();
          }
        } else if (label.contains('країна')) {
          countries = desc.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік')) {
          year ??= int.tryParse(
            desc.find('a')?.text.trim() ??
                desc.text.replaceAll(RegExp(r'\D'), ''),
          );
        } else if (row.find('img[src*="imdb"]') != null) {
          final imdbText = desc.text.trim();
          final match = RegExp(r'(\d+\.?\d*)').firstMatch(imdbText);
          if (match != null) {
            imdbRating = double.tryParse(match.group(1)!);
          }
        }
      }
    }

    // Site Rating
    final siteRatingEl = soup.find('span', attrs: {'data-likes-id': true});
    if (siteRatingEl != null) {
      final likes = int.tryParse(siteRatingEl.text.trim()) ?? 0;
      final dislikesEl = soup.find('span', attrs: {'data-dislikes-id': true});
      final dislikes = int.tryParse(dislikesEl?.text.trim() ?? '0') ?? 0;
      if (likes + dislikes > 0) {
        siteRating = (likes / (likes + dislikes)) * 10;
      }
    }

    // Actors fallback via regex (from Python analyzer findings)
    if (actors == null || actors.isEmpty) {
      final bodyText = soup.text;
      final actorsMatch = RegExp(
        r'(?:Актор[иы]|Актёр[иы]|В ролях|Actors?)[:\s]+([^\n]+)',
        caseSensitive: false,
      ).firstMatch(bodyText);
      if (actorsMatch != null) {
        final actorsText = actorsMatch.group(1)!.trim();
        actors = actorsText
            .split(RegExp(r'[,]'))
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty && a.length < 50)
            .take(10)
            .toList();
      }
    }

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: 'uakino',
        title: title,
        posterUrl: _normalizeImageUrl(posterUrl),
        year: year,
        type: _detectType(mediaId),
        description: description,
        country: countries?.firstOrNull,
        genres: genres,
        rating: siteRating ?? imdbRating,
        ratingSource: siteRating != null
            ? 'Сайт' // Shorter label for cleaner UI
            : (imdbRating != null ? 'IMDb' : null),
        originalTitle: originalTitle,
      ),
      fullDescription: description,
      director: director,
      actors: actors,
      genres: genres,
      countries: countries,
      imdbRating: imdbRating,
    );
  }

  static String _extractItemId(String href) {
    if (href.startsWith('/')) {
      return href.substring(1).replaceAll('.html', '');
    } else if (href.startsWith(baseUrl)) {
      return href.replaceFirst('$baseUrl/', '').replaceAll('.html', '');
    } else {
      var id = href.replaceAll('.html', '');
      if (id.contains('/')) {
        id = id.split('/').last;
      }
      return id;
    }
  }

  static String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$baseUrl$url';
  }

  /// Parse AJAX playlist response
  static List<StreamSource> parseAjaxPlaylist(String html) {
    final sources = <StreamSource>[];
    final soup = BeautifulSoup(html);

    // 1. Check for Playlists (data-file)
    final playlistsDiv = soup.find('div', class_: 'playlists-videos');
    if (playlistsDiv != null) {
      final items = playlistsDiv.findAll('li');
      final voiceoverEpisodeIndex = <String, int>{};

      for (final item in items) {
        var dataFile = item.attributes['data-file'];
        var voiceover = item.attributes['data-voice'] ?? item.text.trim();
        final dataId = item.attributes['data-id'] ?? '';
        final episodeText = _cleanVoiceoverName(item.text.trim());

        voiceover = _cleanVoiceoverName(voiceover);

        // Track episode index per voiceover
        voiceoverEpisodeIndex[voiceover] =
            (voiceoverEpisodeIndex[voiceover] ?? 0) + 1;

        int? episodeNum;
        final parsedNum = _parseEpisodeNumber(episodeText);

        if (parsedNum != null &&
            parsedNum > 500 &&
            RegExp(r'^\d+$').hasMatch(episodeText)) {
          episodeNum = voiceoverEpisodeIndex[voiceover];
        } else {
          episodeNum = parsedNum ?? voiceoverEpisodeIndex[voiceover];
        }

        int? seasonNum;
        if (dataId.contains('_')) {
          seasonNum = int.tryParse(dataId.split('_').first);
          if (seasonNum != null) {
            seasonNum += 1; // 0-indexed to 1-indexed
          }
        }

        if (dataFile != null) {
          dataFile = _cleanPlayerUrl(dataFile);
          if (dataFile.isNotEmpty) {
            final quality = _parseQualityFromUrl(dataFile);

            if (dataFile.contains('.m3u8') || dataFile.contains('.mp4')) {
              sources.add(
                StreamSource(
                  url: dataFile,
                  quality: quality,
                  type: dataFile.contains('.m3u8')
                      ? StreamType.hls
                      : StreamType.direct,
                  voiceover: voiceover,
                  season: seasonNum,
                  episode: episodeNum,
                  episodeTitle: episodeText,
                ),
              );
            } else if (dataFile.startsWith('http')) {
              // Return as direct source to be resolved by Repository
              sources.add(
                StreamSource(
                  url: dataFile,
                  quality: quality,
                  type: StreamType.direct, // Needs resolution
                  voiceover: voiceover,
                  season: seasonNum,
                  episode: episodeNum,
                  episodeTitle: episodeText,
                ),
              );
            }
          }
        }
      }
    }

    // Check for iframes in AJAX response
    final iframes = soup.findAll('iframe');
    for (final iframe in iframes) {
      final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
      if (src != null &&
          src.isNotEmpty &&
          !src.contains('youtube') &&
          !src.contains('google')) {
        String iframeUrl = src;
        if (!iframeUrl.startsWith('http')) {
          iframeUrl = src.startsWith('//') ? 'https:$src' : '$baseUrl$src';
        }
        // Return as direct source to be resolved
        sources.add(
          StreamSource(
            url: iframeUrl,
            quality: StreamQuality.unknown,
            type: StreamType.direct, // Needs resolution
          ),
        );
      }
    }

    return sources;
  }

  static List<String> parseIframeSrcs(String html) {
    final soup = BeautifulSoup(html);
    final sources = <String>[];
    final iframes = soup.findAll('iframe');
    for (final iframe in iframes) {
      final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
      if (src != null &&
          src.isNotEmpty &&
          !src.contains('youtube') &&
          !src.contains('google')) {
        String iframeUrl = src;
        if (!iframeUrl.startsWith('http')) {
          iframeUrl = src.startsWith('//') ? 'https:$src' : '$baseUrl$src';
        }
        sources.add(iframeUrl);
      }
    }
    return sources;
  }

  static String? extractNewsId(String html, String idFromUrl) {
    final soup = BeautifulSoup(html);
    String? newsId;

    final newsIdInput =
        soup.find('input', attrs: {'name': 'news_id'}) ??
        soup.find('input', attrs: {'id': 'news_id'});
    if (newsIdInput != null) {
      newsId = newsIdInput.attributes['value'];
    }

    if (newsId == null) {
      final playerContainer =
          soup.find('div', attrs: {'data-news_id': true}) ??
          soup.find('div', class_: 'playlists-ajax') ??
          soup.find('div', class_: 'player-box');
      if (playerContainer != null) {
        newsId =
            playerContainer.attributes['data-news_id'] ??
            playerContainer.attributes['data-id'];
      }
    }

    if (newsId == null) {
      final idMatch = RegExp(r'(\d+)-').firstMatch(idFromUrl);
      if (idMatch != null) {
        newsId = idMatch.group(1);
      }
    }
    return newsId;
  }

  static int? _parseEpisodeNumber(String text) {
    if (text.isEmpty) return null;

    final patterns = [
      RegExp(r'[Сс]ер[іi][яй]\s*(\d+)', caseSensitive: false),
      RegExp(r'[Ее]п[іi]зод\s*(\d+)', caseSensitive: false),
      RegExp(r'[Ee]pisode\s*(\d+)', caseSensitive: false),
      RegExp(r'[Ee]p\.?\s*(\d+)', caseSensitive: false),
      RegExp(r'[Сс]\.?\s*(\d+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return int.tryParse(match.group(1) ?? '');
      }
    }

    final pureNumberMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(text);
    if (pureNumberMatch != null) {
      return int.tryParse(pureNumberMatch.group(1) ?? '');
    }

    final allNumbers = RegExp(r'(\d+)').allMatches(text).toList();
    if (allNumbers.isNotEmpty) {
      if (allNumbers.length == 1) {
        final num = int.tryParse(allNumbers.first.group(1) ?? '');
        if (num != null && num < 10000) return num;
      }
      final lastNum = int.tryParse(allNumbers.last.group(1) ?? '');
      if (lastNum != null && lastNum < 10000) return lastNum;
    }

    return null;
  }

  static StreamQuality _parseQualityFromUrl(String url) {
    final lowerUrl = url.toLowerCase();
    final qualityPatterns = [
      RegExp(r'[_\-/](\d{3,4})p[_\-/\.]'),
      RegExp(r'/(\d{3,4})p?/'),
      RegExp(r'_(\d{3,4})p\.'),
      RegExp(r'\[(\d{3,4})p?\]'),
    ];

    for (final pattern in qualityPatterns) {
      final match = pattern.firstMatch(lowerUrl);
      if (match != null) {
        final quality = _parseQuality(match.group(1));
        if (quality != StreamQuality.unknown) return quality;
      }
    }

    // Check specific high qualities first
    if (lowerUrl.contains('4k') || lowerUrl.contains('2160')) {
      return StreamQuality.q4k;
    }
    if (lowerUrl.contains('1440') || lowerUrl.contains('2k')) {
      return StreamQuality.q1440p;
    }
    if (lowerUrl.contains('1080')) return StreamQuality.q1080p;
    if (lowerUrl.contains('720')) return StreamQuality.q720p;

    // For HLS (.m3u8), if we haven't found HD+, assume Auto/Unknown
    // even if we see 480/360, as it's likely an adaptive stream
    // and the URL might just point to a distinct path.
    if (lowerUrl.contains('.m3u8')) {
      return StreamQuality.unknown;
    }

    if (lowerUrl.contains('480')) return StreamQuality.q480p;
    if (lowerUrl.contains('360')) return StreamQuality.q360p;

    return StreamQuality.unknown;
  }

  static StreamQuality _parseQuality(String? quality) {
    if (quality == null) return StreamQuality.unknown;
    final normalized = quality.replaceAll('p', '').trim();
    switch (normalized) {
      case '360':
        return StreamQuality.q360p;
      case '480':
        return StreamQuality.q480p;
      case '720':
        return StreamQuality.q720p;
      case '1080':
        return StreamQuality.q1080p;
      case '1440':
        return StreamQuality.q1440p;
      case '2160':
        return StreamQuality.q4k;
      default:
        return StreamQuality.unknown;
    }
  }

  static int getQualityValue(StreamQuality quality) {
    switch (quality) {
      case StreamQuality.q4k:
        return 2160;
      case StreamQuality.q1440p:
        return 1440;
      case StreamQuality.q1080p:
        return 1080;
      case StreamQuality.q720p:
        return 720;
      case StreamQuality.q480p:
        return 480;
      case StreamQuality.q360p:
        return 360;
      default:
        return 0;
    }
  }

  static String _cleanPlayerUrl(String url) {
    var cleaned = url
        .replaceAll(r'\/', '/')
        .replaceAll(r'\', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    if (cleaned.isNotEmpty && !cleaned.startsWith('http')) {
      if (cleaned.startsWith('//')) {
        cleaned = 'https:$cleaned';
      } else if (cleaned.startsWith('/')) {
        cleaned = '$baseUrl$cleaned';
      }
    }
    return cleaned;
  }

  static String _cleanVoiceoverName(String name) {
    var cleaned = name
        .replaceAll(r'\"', '')
        .replaceAll(r"\'", '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    final unicodePattern = RegExp(r'\\u([0-9a-fA-F]{4})');
    cleaned = cleaned.replaceAllMapped(unicodePattern, (match) {
      final codePoint = int.parse(match.group(1)!, radix: 16);
      return String.fromCharCode(codePoint);
    });

    return cleaned.trim();
  }

  static ContentType _detectType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('anime')) return ContentType.anime;
    if (lower.contains('cartoon') || lower.contains('mult')) {
      return ContentType.cartoon;
    }
    if (lower.contains('serial') || lower.contains('series')) {
      return ContentType.series;
    }
    if (lower.contains('film')) return ContentType.movie;
    return ContentType.unknown;
  }
}
