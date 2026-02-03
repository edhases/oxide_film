import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';

/// Filmix content provider
///
/// Ukrainian/Russian streaming site with API-based stream extraction
class FilmixProvider implements ContentProvider {
  static const String _tag = 'Filmix';

  final ApiClient _client;
  // Disabled by default - mirror returns 503, needs working URL
  bool _isEnabled = false;

  /// Current mirror URL
  String _mirror = 'https://filmix.ac';

  /// User token for API access (optional, for better quality)
  String? _userToken;

  FilmixProvider(this._client);

  @override
  String get id => 'filmix';

  @override
  String get name => 'Filmix';

  @override
  String? get iconUrl => '$_mirror/favicon.ico';

  @override
  String get baseUrl => _mirror;

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  /// Set mirror URL
  void setMirror(String url) {
    _mirror = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  /// Set user token for PRO features
  void setUserToken(String? token) {
    _userToken = token;
  }

  @override
  List<ContentType> get supportedTypes => [
    ContentType.movie,
    ContentType.series,
    ContentType.cartoon,
    ContentType.anime,
  ];

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) async {
    Logger.d('search: query="$query", page=$page', tag: _tag);
    try {
      final url = '$baseUrl/search/${Uri.encodeComponent(query)}';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('Response length: ${html.length}', tag: _tag);
      final items = _parseSearchResults(html);
      Logger.d('Found ${items.length} items', tag: _tag);
      return items;
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<MediaDetails> getDetails(String id) async {
    Logger.d('getDetails: id=$id', tag: _tag);
    try {
      final url = '$baseUrl/play/$id';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('HTML length: ${html.length}', tag: _tag);
      return _parseDetails(html, id);
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) async {
    Logger.d('getStreams: id=$id, s=$season, e=$episode', tag: _tag);
    try {
      final sources = <StreamSource>[];

      // Try API method first
      final apiStreams = await _getStreamsFromApi(id, season, episode);
      if (apiStreams.isNotEmpty) {
        return apiStreams;
      }

      // Fallback to page parsing
      final html = await _client.get('$baseUrl/play/$id');
      final soup = BeautifulSoup(html);

      // Look for player data
      final scripts = soup.findAll('script');
      Logger.d('Found ${scripts.length} scripts to check', tag: _tag);
      for (final script in scripts) {
        final content = script.text;
        if (content.contains('playerParams') ||
            content.contains('player_data')) {
          Logger.d('Found player script', tag: _tag);
          _parsePlayerScript(content, sources, season, episode);
        }
      }

      Logger.i('Total streams: ${sources.length}', tag: _tag);
      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<StreamSource>> _getStreamsFromApi(
    String mediaId,
    int? season,
    int? episode,
  ) async {
    final sources = <StreamSource>[];

    try {
      // Extract numeric ID from slug
      final numericId = RegExp(r'(\d+)').firstMatch(mediaId)?.group(1);
      if (numericId == null) return sources;

      final headers = <String, String>{
        'X-Requested-With': 'XMLHttpRequest',
        'Referer': '$baseUrl/play/$mediaId',
      };

      if (_userToken != null) {
        headers['X-FX-Token'] = _userToken!;
      }

      final response = await _client.dio.get<String>(
        '$baseUrl/api/v2/post/$numericId',
        options: Options(headers: headers),
      );

      Logger.d(
        'Filmix API response length: ${response.data?.length}',
        tag: _tag,
      );

      final json = jsonDecode(response.data ?? '{}');

      if (json['player_links'] != null) {
        final links = json['player_links'] as Map<String, dynamic>;

        // Movie links
        if (links['movie'] != null) {
          final movieLinks = links['movie'] as Map<String, dynamic>;
          for (final entry in movieLinks.entries) {
            final quality = entry.key;
            final url = entry.value.toString();
            if (url.isNotEmpty) {
              sources.add(
                StreamSource(
                  url: url,
                  quality: _parseQuality(quality),
                  type: url.contains('.m3u8')
                      ? StreamType.hls
                      : StreamType.direct,
                ),
              );
            }
          }
        }

        // Series links
        if (links['playlist'] != null && season != null && episode != null) {
          final playlist = links['playlist'] as List;
          for (final seasonData in playlist) {
            if (seasonData['season'] == season) {
              Logger.d('Found season $season in API data', tag: _tag);
              final episodes = seasonData['episodes'] as List?;
              if (episodes != null) {
                for (final ep in episodes) {
                  if (ep['episode'] == episode) {
                    final epLinks = ep['links'] as Map<String, dynamic>?;
                    if (epLinks != null) {
                      for (final entry in epLinks.entries) {
                        sources.add(
                          StreamSource(
                            url: entry.value.toString(),
                            quality: _parseQuality(entry.key),
                            type: StreamType.hls,
                          ),
                        );
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      Logger.w('API method failed: $e', tag: _tag);
    }

    return sources;
  }

  void _parsePlayerScript(
    String script,
    List<StreamSource> sources,
    int? season,
    int? episode,
  ) {
    try {
      // Extract JSON data from script
      final jsonMatch = RegExp(
        r'playerParams\s*=\s*(\{.+?\});',
        dotAll: true,
      ).firstMatch(script);

      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(1);
        final data = jsonDecode(jsonStr!);

        if (data['src'] != null) {
          final src = data['src'].toString();
          Logger.d('Found m3u8 in script: $src', tag: _tag);
          _parseM3u8Playlist(src, sources);
        }
      }
    } catch (e) {
      Logger.w('Failed to parse player script', tag: _tag);
    }
  }

  void _parseM3u8Playlist(String url, List<StreamSource> sources) {
    // Add as HLS stream
    sources.add(
      StreamSource(
        url: url,
        quality: StreamQuality.unknown,
        type: StreamType.hls,
      ),
    );
  }

  StreamQuality _parseQuality(String quality) {
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

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      String section = '';
      switch (type) {
        case ContentType.movie:
          section = 'filmy';
          break;
        case ContentType.series:
          section = 'serialy';
          break;
        case ContentType.cartoon:
          section = 'multserialy';
          break;
        case ContentType.anime:
          section = 'anime';
          break;
        default:
          section = 'top';
      }

      final html = await _client.get(
        '$baseUrl/$section?filter=popular&page=$page',
      );
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      String section = '';
      switch (type) {
        case ContentType.movie:
          section = 'filmy';
          break;
        case ContentType.series:
          section = 'serialy';
          break;
        case ContentType.cartoon:
          section = 'multserialy';
          break;
        case ContentType.anime:
          section = 'anime';
          break;
        default:
          section = 'lastnews';
      }

      final html = await _client.get('$baseUrl/$section?page=$page');
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<String>> getCategories() async {
    return [
      'Бойовик',
      'Детектив',
      'Драма',
      'Комедія',
      'Мелодрама',
      'Пригоди',
      'Трилер',
      'Фантастика',
      'Фентезі',
      'Жахи',
      'Документальний',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final genreId = _categoryToId(category);
      final html = await _client.get(
        '$baseUrl/filmy?genre=$genreId&page=$page',
      );
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e(
        'Get by category failed',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  int _categoryToId(String category) {
    final map = {
      'Бойовик': 1,
      'Детектив': 2,
      'Драма': 3,
      'Комедія': 4,
      'Мелодрама': 5,
      'Пригоди': 6,
      'Трилер': 7,
      'Фантастика': 8,
      'Фентезі': 9,
      'Жахи': 10,
      'Документальний': 11,
    };
    return map[category] ?? 1;
  }

  List<MediaItem> _parseSearchResults(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    final cards = soup.findAll('article', class_: 'shortstory');
    if (cards.isEmpty) {
      // Try alternative selector
      final altCards = soup.findAll('div', class_: 'short-item');
      for (final card in altCards) {
        final item = _parseCard(card);
        if (item != null) items.add(item);
      }
    } else {
      for (final card in cards) {
        final item = _parseCard(card);
        if (item != null) items.add(item);
      }
    }

    return items;
  }

  MediaItem? _parseCard(dynamic card) {
    try {
      final link = card.find('a', class_: 'short-img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      final titleEl =
          card.find('a', class_: 'short-title') ??
          card.find('div', class_: 'short-title');
      final title = titleEl?.text.trim() ?? link.attributes['title'] ?? '';

      int? year;
      final infoEl = card.find('div', class_: 'short-info');
      if (infoEl != null) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl = card.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
      }

      // Parse genres
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'short-genre') ??
          card.find('span', class_: 'genre');
      if (genreEl != null) {
        final genreLinks = genreEl.findAll('a');
        if (genreLinks.isNotEmpty) {
          genres = genreLinks
              .map((a) => a.text.trim())
              .where((g) => g.isNotEmpty)
              .toList();
        } else {
          final genreText = genreEl.text.trim();
          if (genreText.isNotEmpty) {
            genres = genreText
                .split(RegExp(r'[,/]'))
                .map((g) => g.trim())
                .where((g) => g.isNotEmpty)
                .toList();
          }
        }
      }

      // Parse country
      String? country;
      final countryEl =
          card.find('div', class_: 'short-country') ??
          card.find('span', class_: 'country');
      if (countryEl != null) {
        country = countryEl.text.trim().split(',').first.trim();
      }

      final type = _detectContentType(href);

      return MediaItem(
        id: mediaId,
        providerId: id,
        title: title,
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        type: type,
        genres: genres,
        country: country,
      );
    } catch (e) {
      return null;
    }
  }

  String _extractIdFromUrl(String url) {
    // Format: https://filmix.ac/play/12345-movie-name
    final match = RegExp(r'/play/(.+?)(?:\?|$)').firstMatch(url);
    if (match != null) {
      return match.group(1) ?? '';
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return '';
  }

  ContentType _detectContentType(String url) {
    if (url.contains('/serialy/') || url.contains('seria')) {
      return ContentType.series;
    }
    if (url.contains('/multserialy/') || url.contains('mult')) {
      return ContentType.cartoon;
    }
    if (url.contains('/anime/')) return ContentType.anime;
    return ContentType.movie;
  }

  MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1', class_: 'name');
    final title = titleEl?.text.trim() ?? '';

    String? originalTitle;
    final origEl = soup.find('div', class_: 'origin-name');
    if (origEl != null) {
      originalTitle = origEl.text.trim();
    }

    // Poster
    final posterEl = soup.find('div', class_: 'poster-box');
    final posterUrl = posterEl?.find('img')?.attributes['src'];

    // Info
    final infoBlock = soup.find('div', class_: 'info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    Duration? duration;

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('li')) {
        final label =
            row.find('span', class_: 'item-label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'item-value');

        if (label.contains('режис')) {
          director = value?.text.trim();
        } else if (label.contains('актор') || label.contains('актер')) {
          actors = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('країн') || label.contains('стран')) {
          countries = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік') || label.contains('год')) {
          year = int.tryParse(value?.text.trim() ?? '');
        } else if (label.contains('трива') || label.contains('врем')) {
          final durMatch = RegExp(r'(\d+)').firstMatch(value?.text ?? '');
          if (durMatch != null) {
            duration = Duration(minutes: int.parse(durMatch.group(1)!));
          }
        }
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'full-story');
    final description = descEl?.text.trim();

    // Rating
    double? rating;
    final ratingEl = soup.find('div', class_: 'rating-box');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    // Seasons
    List<Season>? seasons;
    final seasonsBlock = soup.find('div', class_: 'playlists-ajax');
    if (seasonsBlock != null) {
      seasons = _parseSeasons(soup);
    }

    final type = _detectContentType(mediaId);

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: id,
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

  List<Season> _parseSeasons(BeautifulSoup soup) {
    final seasons = <Season>[];

    final playlistItems = soup.findAll('li', class_: 'playlists-item');

    for (final item in playlistItems) {
      final seasonNum =
          int.tryParse(item.attributes['data-season'] ?? '') ??
          seasons.length + 1;

      final episodes = <Episode>[];
      final episodeList = soup.find(
        'ul',
        attrs: {'data-season': seasonNum.toString()},
      );

      if (episodeList != null) {
        for (final epItem in episodeList.findAll('li')) {
          final epNum =
              int.tryParse(epItem.attributes['data-episode'] ?? '') ??
              episodes.length + 1;
          final epTitle = epItem.text.trim();

          episodes.add(Episode(number: epNum, title: epTitle));
        }
      }

      seasons.add(Season(number: seasonNum, episodes: episodes));
    }

    return seasons;
  }
}
