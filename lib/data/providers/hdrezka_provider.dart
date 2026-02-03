import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';

import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';

/// HDRezka content provider
///
/// Popular Russian/Ukrainian streaming site with multiple mirrors
class HdrezkaProvider implements ContentProvider {
  static const String _tag = 'HDRezka';

  final ApiClient _client;
  // Disabled by default - streams don't work properly, keep for metadata only
  bool _isEnabled = false;

  /// Current mirror URL (can be changed if blocked)
  String _mirror = 'https://rezka.ag';

  /// List of known working mirrors
  static const List<String> _mirrors = [
    'https://rezka.ag',
    'https://hdrezka.ag',
    'https://hdrezka.me',
    'https://hdrezka.co',
    'https://hdrezka.sh',
  ];

  /// Get available mirrors
  List<String> get availableMirrors => _mirrors;

  HdrezkaProvider(this._client);

  @override
  String get id => 'hdrezka';

  @override
  String get name => 'HDRezka';

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
    try {
      final url =
          '$baseUrl/search/?do=search&subaction=search'
          '&q=${Uri.encodeComponent(query)}'
          '&page=$page';

      final html = await _client.get(url);
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<MediaDetails> getDetails(String id) async {
    try {
      final html = await _client.get('$baseUrl/$id.html');
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
    Logger.i('getStreams called: id=$id, s=$season, e=$episode', tag: _tag);
    try {
      final url = '$baseUrl/$id.html';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('HTML length: ${html.length}', tag: _tag);
      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // Extract data-id for AJAX requests
      // Try multiple selectors
      final playerDiv =
          soup.find('div', attrs: {'id': 'cdnplayer'}) ??
          soup.find('div', class_: 'b-player') ??
          soup.find('div', class_: 'b-content__inline_item') ??
          soup.find('div', attrs: {'id': 'player'});

      var dataId = playerDiv?.attributes['data-id'];
      var translatorId = playerDiv?.attributes['data-translator_id'] ?? '0';
      Logger.d('Initial dataId=$dataId, translatorId=$translatorId', tag: _tag);

      // Fallback 1: Find any element with data-id
      if (dataId == null) {
        Logger.d('Trying fallback: searching for any data-id', tag: _tag);
        final fallback = soup.find('*', attrs: {'data-id': true});
        if (fallback != null) {
          dataId = fallback.attributes['data-id'];
          translatorId =
              fallback.attributes['data-translator_id'] ?? translatorId;
          Logger.i('Fallback 1 found data-id: $dataId', tag: _tag);
        }
      }

      // Fallback 2: Extract numeric ID from URL
      if (dataId == null) {
        Logger.d('Trying fallback: extracting from URL', tag: _tag);
        final urlMatch = RegExp(r'/(\d+)-').firstMatch(id);
        if (urlMatch != null) {
          dataId = urlMatch.group(1);
          Logger.i('Fallback 2 found data-id from URL: $dataId', tag: _tag);
        }
      }

      // Fallback 3: Search in scripts for data-id pattern
      if (dataId == null) {
        Logger.d('Trying fallback: searching in scripts', tag: _tag);
        for (final script in soup.findAll('script')) {
          final content = script.text;
          final match = RegExp(r'data-id="?(\d+)"?').firstMatch(content);
          if (match != null) {
            dataId = match.group(1);
            Logger.i('Fallback 3 found data-id in script: $dataId', tag: _tag);
            break;
          }
        }
      }

      if (dataId == null) {
        Logger.e('ERROR: data-id is null after all fallbacks!', tag: _tag);
        return sources;
      }

      // Get available translators (voiceovers)
      final translators = <String, String>{}; // id -> name
      final translatorsList = soup.find('ul', id: 'translators-list');

      if (translatorsList != null) {
        for (final li in translatorsList.findAll('li')) {
          final tid = li.attributes['data-translator_id'];
          final tname = li.text.trim();
          if (tid != null) {
            translators[tid] = tname;
            Logger.d('Found translator: $tid -> $tname', tag: _tag);
          }
        }
      }

      if (translators.isEmpty) {
        translators[translatorId] = 'Оригінал';
        Logger.d('No translators found, using default', tag: _tag);
      }

      Logger.d('Total translators: ${translators.length}', tag: _tag);

      // For series, get seasons/episodes structure first
      if (season != null && episode != null) {
        Logger.d('Getting episode streams...', tag: _tag);
        await _getEpisodeStreams(
          dataId,
          translatorId,
          season,
          episode,
          translators[translatorId] ?? 'Оригінал',
          sources,
        );
      } else {
        // For movies, get streams directly
        Logger.d(
          'Getting movie streams for ${translators.length} translators...',
          tag: _tag,
        );
        for (final entry in translators.entries) {
          await _getMovieStreams(dataId, entry.key, entry.value, sources);
        }
      }

      Logger.i('Total streams found: ${sources.length}', tag: _tag);
      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> _getMovieStreams(
    String dataId,
    String translatorId,
    String voiceover,
    List<StreamSource> sources,
  ) async {
    try {
      Logger.d(
        '_getMovieStreams: dataId=$dataId, translatorId=$translatorId',
        tag: _tag,
      );
      final response = await _client.dio.post<String>(
        '$baseUrl/ajax/get_cdn_series/',
        data: {
          'id': dataId,
          'translator_id': translatorId,
          'action': 'get_movie',
        },
        options: Options(
          headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': baseUrl},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      Logger.d('AJAX response status: ${response.statusCode}', tag: _tag);
      Logger.d(
        'AJAX response length: ${response.data?.length ?? 0}',
        tag: _tag,
      );

      final json = jsonDecode(response.data ?? '{}');
      Logger.d(
        'AJAX success: ${json['success']}, has url: ${json['url'] != null}',
        tag: _tag,
      );

      if (json['success'] == true && json['url'] != null) {
        final urlData = json['url'] as String;
        Logger.d(
          'URL data (first 100): ${urlData.substring(0, urlData.length.clamp(0, 100))}',
          tag: _tag,
        );
        _parseStreamUrls(urlData, voiceover, sources);
      } else {
        Logger.w('AJAX returned success=false or no url', tag: _tag);
        if (json['message'] != null) {
          Logger.w('AJAX message: ${json['message']}', tag: _tag);
        }
      }
    } catch (e, stack) {
      Logger.e(
        'Failed to get movie streams for $voiceover',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _getEpisodeStreams(
    String dataId,
    String translatorId,
    int season,
    int episode,
    String voiceover,
    List<StreamSource> sources,
  ) async {
    try {
      final response = await _client.dio.post<String>(
        '$baseUrl/ajax/get_cdn_series/',
        data: {
          'id': dataId,
          'translator_id': translatorId,
          'season': season.toString(),
          'episode': episode.toString(),
          'action': 'get_stream',
        },
        options: Options(
          headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': baseUrl},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final json = jsonDecode(response.data ?? '{}');
      if (json['success'] == true && json['url'] != null) {
        _parseStreamUrls(json['url'], voiceover, sources);
      }
    } catch (e) {
      Logger.w('Failed to get episode streams', tag: _tag);
    }
  }

  void _parseStreamUrls(
    String urlData,
    String voiceover,
    List<StreamSource> sources,
  ) {
    // HDRezka returns URLs in format: [720p]url,[1080p]url,...
    // URLs are often encoded, need to decode
    final decoded = _decodeStreamUrl(urlData);
    Logger.d(
      'Decoded stream data: ${decoded.substring(0, decoded.length.clamp(0, 200))}...',
      tag: _tag,
    );

    final pattern = RegExp(r'\[(\d+)p?\]([^\[,]+)');
    for (final match in pattern.allMatches(decoded)) {
      final quality = match.group(1);
      var url = match.group(2)?.trim() ?? '';

      // Remove "or" alternatives (take first URL)
      if (url.contains(' or ')) {
        url = url.split(' or ').first;
      }

      // Clean up the URL - remove everything after .mp4 if it's a segment URL
      url = _cleanStreamUrl(url);

      if (url.isNotEmpty &&
          !url.contains('undefined') &&
          _isValidStreamUrl(url)) {
        sources.add(
          StreamSource(
            url: url,
            quality: _parseQuality(quality),
            voiceover: voiceover,
            type: url.contains('.m3u8') ? StreamType.hls : StreamType.direct,
          ),
        );
        Logger.d('Added stream: $quality - $voiceover', tag: _tag);
      }
    }
  }

  /// Clean stream URL - remove segment suffixes for direct playback
  String _cleanStreamUrl(String url) {
    // If URL contains segment patterns, extract base video URL
    // Example: https://stream.voidboost.cc/.../video.mp4:hls:manifest.m3u8
    // Should become: https://stream.voidboost.cc/.../video.mp4

    if (url.contains('.mp4:') || url.contains('.mp4/')) {
      final mp4Index = url.indexOf('.mp4');
      if (mp4Index > 0) {
        return url.substring(0, mp4Index + 4);
      }
    }

    // Remove trailing garbage
    url = url.replaceAll(RegExp(r'[\s\r\n]+$'), '');

    return url;
  }

  /// Validate stream URL
  bool _isValidStreamUrl(String url) {
    if (!url.startsWith('http')) return false;
    if (url.contains('undefined')) return false;
    if (url.length < 20) return false;
    return true;
  }

  String _decodeStreamUrl(String encoded) {
    // HDRezka uses a specific encoding
    try {
      if (encoded.isEmpty) return encoded;

      // Try direct trash removal first (common pattern)
      var decoded = encoded;

      // HDRezka encoding: #0 + base64 with custom alphabet or substitutions
      if (encoded.startsWith('#')) {
        // Remove # prefix and version marker
        var base64Part = encoded;
        if (encoded.startsWith('#0')) {
          base64Part = encoded.substring(2);
        } else if (encoded.startsWith('#')) {
          base64Part = encoded.substring(1);
        }

        // Remove trash strings that HDRezka appends
        final trashStrings = [
          '//_//JCQhIUAkXiY=',
          '//QEBAQEAhIyM=',
          '//Xl5eIyo=',
          '//_//JCQkISE=',
          '//IyMhQEBA',
          '//QCMjQEA=',
        ];

        for (final trash in trashStrings) {
          base64Part = base64Part.replaceAll(trash, '');
        }

        // Standard base64 decode
        try {
          // Pad if needed
          while (base64Part.length % 4 != 0) {
            base64Part += '=';
          }
          decoded = utf8.decode(base64.decode(base64Part));
        } catch (e) {
          // Try URL-safe base64
          try {
            base64Part = base64Part.replaceAll('-', '+').replaceAll('_', '/');
            while (base64Part.length % 4 != 0) {
              base64Part += '=';
            }
            decoded = utf8.decode(base64.decode(base64Part));
          } catch (_) {
            Logger.w('Base64 decode failed', tag: _tag);
          }
        }
      }

      return decoded;
    } catch (e) {
      Logger.w('Stream URL decode failed: $e', tag: _tag);
      return encoded;
    }
  }

  StreamQuality _parseQuality(String? quality) {
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

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      String section = '';
      switch (type) {
        case ContentType.movie:
          section = 'films';
          break;
        case ContentType.series:
          section = 'series';
          break;
        case ContentType.cartoon:
          section = 'cartoons';
          break;
        case ContentType.anime:
          section = 'animation';
          break;
        default:
          section = 'films';
      }

      final html = await _client.get(
        '$baseUrl/$section/page/$page/?filter=popular',
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
          section = 'films';
          break;
        case ContentType.series:
          section = 'series';
          break;
        case ContentType.cartoon:
          section = 'cartoons';
          break;
        case ContentType.anime:
          section = 'animation';
          break;
        default:
          section = 'new';
      }

      final html = await _client.get('$baseUrl/$section/page/$page/');
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<String>> getCategories() async {
    // Return subset of genres that HDRezka supports
    return ContentGenres.all.take(10).toList();
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final genreSlug = ProviderGenreMappings.getSlugForProvider(id, category);
      final html = await _client.get(
        '$baseUrl/films/genre/$genreSlug/page/$page/',
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

  List<MediaItem> _parseSearchResults(String html) {
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
        final mediaId = _extractIdFromUrl(href);
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
          r'([А-ЯЁA-Z][а-яёa-z]+)\s*,?\s*\d{4}',
        ).firstMatch(infoText);
        if (countryMatch != null) {
          country = countryMatch.group(1);
        }

        final type = _detectContentType(href);

        items.add(
          MediaItem(
            id: mediaId,
            providerId: id,
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

  String _extractIdFromUrl(String url) {
    // Format: https://hdrezka.ag/films/action/12345-movie-name.html
    final match = RegExp(r'/([^/]+/[^/]+/\d+-[^/]+)\.html').firstMatch(url);
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

  ContentType _detectContentType(String url) {
    if (url.contains('/films/')) return ContentType.movie;
    if (url.contains('/series/')) return ContentType.series;
    if (url.contains('/cartoons/')) return ContentType.cartoon;
    if (url.contains('/animation/')) return ContentType.anime;
    return ContentType.unknown;
  }

  MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);
    Logger.d('Parsing details for: $mediaId', tag: _tag);
    Logger.d('HTML length: ${html.length}', tag: _tag);

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

    final type = _detectContentType('/$mediaId.html');

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
}
