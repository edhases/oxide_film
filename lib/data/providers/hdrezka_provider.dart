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
/// Popular Russian/Ukrainian streaming site with multiple mirrors.
/// This provider is shown in a separate category, not on the home page.
/// Streams are "fixed" - quality and voiceover cannot be changed after playback starts.
class HdrezkaProvider implements ContentProvider {
  static const String _tag = 'HDRezka';

  final ApiClient _client;
  // Disabled by default - streams don't work properly, keep for metadata only
  bool _isEnabled = false;

  /// Whether to show this provider on the home page (false for HDRezka)
  static const bool showOnHome = false;

  /// Whether streams from this provider are "fixed" (can't change quality/voiceover after start)
  static const bool hasFixedStreams = true;

  /// Current mirror URL (can be changed if blocked)
  String _mirror = 'https://hdrezka-home.tv';

  /// List of known working mirrors
  static const List<String> _mirrors = [
    'https://hdrezka-home.tv',
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
  String get effectiveBaseUrl => _mirror;

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
    Logger.d(' getStreams called: id=$id, s=$season, e=$episode');
    try {
      final url = '$baseUrl/$id.html';
      Logger.d(' Fetching: $url');
      final html = await _client.get(url);
      Logger.d(' HTML length: ${html.length}');
      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // Extract CSRF token for AJAX requests (session protection)
      String? csrfToken;
      // Try to find in meta tag
      final metaCsrf = soup.find('meta', attrs: {'name': 'csrf-token'});
      csrfToken = metaCsrf?.attributes['content'];

      // Try to find in scripts (HDRezka often embeds it)
      if (csrfToken == null) {
        for (final script in soup.findAll('script')) {
          final content = script.text;
          // Look for patterns like: b_token = "...", csrf_token = "..."
          final tokenMatch = RegExp(
            r'''(?:b_token|csrf_token|_token)\s*[:=]\s*["']([^"']+)["']''',
          ).firstMatch(content);
          if (tokenMatch != null) {
            csrfToken = tokenMatch.group(1);
            break;
          }
        }
      }
      Logger.d(' CSRF token: ${csrfToken ?? "not found"}');

      // Extract data-id and translator_id for AJAX requests
      var dataId = '';
      var translatorId = '';

      // Method 1: Look for sof.tv.initCDNMoviesEvents or similar init calls in scripts
      for (final script in soup.findAll('script')) {
        final content = script.text;

        // Pattern: initCDNMoviesEvents(12345, 238, ...)
        final initMatch = RegExp(
          r'initCDN(?:Movies|Series)Events\s*\(\s*(\d+)\s*,\s*(\d+)',
        ).firstMatch(content);
        if (initMatch != null) {
          dataId = initMatch.group(1) ?? '';
          translatorId = initMatch.group(2) ?? '';
          Logger.d(
            '[HDRezka] Found in initCDN: dataId=$dataId, translatorId=$translatorId',
          );
          break;
        }

        // Pattern: sof.tv.initCDNSeriesEvents(...)
        final sofMatch = RegExp(
          r'sof\.tv\.initCDN\w+Events\s*\(\s*(\d+)\s*,\s*(\d+)',
        ).firstMatch(content);
        if (sofMatch != null) {
          dataId = sofMatch.group(1) ?? '';
          translatorId = sofMatch.group(2) ?? '';
          Logger.d(
            '[HDRezka] Found in sof.tv: dataId=$dataId, translatorId=$translatorId',
          );
          break;
        }
      }

      // Method 2: Try div selectors if not found in scripts
      if (dataId.isEmpty) {
        final playerDiv =
            soup.find('div', attrs: {'id': 'cdnplayer'}) ??
            soup.find('div', class_: 'b-player') ??
            soup.find('div', class_: 'b-content__inline_item') ??
            soup.find('div', attrs: {'id': 'player'});

        dataId = playerDiv?.attributes['data-id'] ?? '';
        translatorId =
            playerDiv?.attributes['data-translator_id'] ?? translatorId;
        Logger.d(
          '[HDRezka] From playerDiv: dataId=$dataId, translatorId=$translatorId',
        );
      }

      // Method 3: Find first translator from list
      if (translatorId.isEmpty || translatorId == '0') {
        final firstTranslator = soup.find('li', class_: 'b-translator__item');
        if (firstTranslator != null) {
          translatorId = firstTranslator.attributes['data-translator_id'] ?? '';
          Logger.d(' Found first translator: $translatorId');
        }
      }

      // Method 4: Find any element with data-id
      if (dataId.isEmpty) {
        Logger.d(' Trying fallback: searching for any data-id');
        final fallback = soup.find('*', attrs: {'data-id': true});
        if (fallback != null) {
          dataId = fallback.attributes['data-id'] ?? '';
          if (translatorId.isEmpty) {
            translatorId = fallback.attributes['data-translator_id'] ?? '';
          }
          Logger.d(' Fallback found data-id: $dataId');
        }
      }

      // Method 5: Extract numeric ID from URL
      if (dataId.isEmpty) {
        Logger.d(' Trying fallback: extracting from URL');
        final urlMatch = RegExp(r'/(\d+)-').firstMatch(id);
        if (urlMatch != null) {
          dataId = urlMatch.group(1) ?? '';
          Logger.d(' Fallback from URL: $dataId');
        }
      }

      // Default translator_id if still empty
      if (translatorId.isEmpty) {
        translatorId = '238'; // Common default for Russian voiceover
        Logger.d(' Using default translatorId: $translatorId');
      }

      Logger.d(' Final: dataId=$dataId, translatorId=$translatorId');

      if (dataId.isEmpty) {
        Logger.d(' ERROR: data-id is empty after all fallbacks!');
        return sources;
      }

      // Get available translators (voiceovers)
      final translators = <String, String>{}; // id -> name
      final translatorsList = soup.find('ul', id: 'translators-list');

      if (translatorsList != null) {
        Logger.d(' Found translators-list');
        for (final li in translatorsList.findAll('li')) {
          final tid = li.attributes['data-translator_id'];
          final tname = li.text.trim();
          if (tid != null) {
            translators[tid] = tname;
            Logger.d(' Found translator: $tid -> $tname');
          }
        }
      } else {
        Logger.d(' No translators-list found in HTML');
      }

      if (translators.isEmpty) {
        translators[translatorId] = 'Оригінал';
        Logger.d(
          '[HDRezka] No translators found, using default with id=$translatorId',
        );
      }

      Logger.d(' Total translators: ${translators.length}');

      // For series, get seasons/episodes structure first
      if (season != null && episode != null) {
        Logger.d(' Getting episode streams...');
        await _getEpisodeStreams(
          dataId,
          translatorId,
          season,
          episode,
          translators[translatorId] ?? 'Оригінал',
          sources,
          csrfToken: csrfToken,
        );
      } else {
        // For movies, get streams directly
        Logger.d(
          '[HDRezka] Getting movie streams for ${translators.length} translators...',
        );
        for (final entry in translators.entries) {
          await _getMovieStreams(
            dataId,
            entry.key,
            entry.value,
            sources,
            csrfToken: csrfToken,
          );
        }
      }

      Logger.d(' Total streams found: ${sources.length}');
      return sources;
    } catch (e, stack) {
      Logger.d(' Get streams failed: $e');
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> _getMovieStreams(
    String dataId,
    String translatorId,
    String voiceover,
    List<StreamSource> sources, {
    String? csrfToken,
  }) async {
    try {
      Logger.d(
        '[HDRezka] _getMovieStreams: dataId=$dataId, translatorId=$translatorId, csrf=${csrfToken != null}',
      );

      // Build request data
      final requestData = <String, dynamic>{
        'id': dataId,
        'translator_id': translatorId,
        'action': 'get_movie',
      };

      // Add CSRF token if available (different field names used by HDRezka)
      if (csrfToken != null) {
        requestData['_token'] = csrfToken;
      }

      final response = await _client.dio.post<String>(
        '$baseUrl/ajax/get_cdn_series/',
        data: requestData,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/',
            'Origin': baseUrl,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            if (csrfToken != null) 'X-CSRF-TOKEN': csrfToken,
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      Logger.d(' AJAX response status: ${response.statusCode}');
      final responseData = response.data ?? '{}';
      Logger.d(
        '[HDRezka] AJAX response (first 500): ${responseData.substring(0, responseData.length.clamp(0, 500))}',
      );

      final json = jsonDecode(response.data ?? '{}');
      Logger.d(
        '[HDRezka] AJAX success: ${json['success']}, has url: ${json['url'] != null}',
      );

      if (json['success'] == true && json['url'] != null) {
        final urlData = json['url'] as String;
        Logger.d(
          '[HDRezka] URL data (first 100): ${urlData.substring(0, urlData.length.clamp(0, 100))}',
        );
        _parseStreamUrls(urlData, voiceover, sources);
      } else {
        Logger.d(' AJAX returned success=false or no url');
        if (json['message'] != null) {
          Logger.d(' AJAX message: ${json['message']}');
        }
      }
    } catch (e, stack) {
      Logger.d(' Failed to get movie streams for $voiceover: $e');
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
    List<StreamSource> sources, {
    String? csrfToken,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'id': dataId,
        'translator_id': translatorId,
        'season': season.toString(),
        'episode': episode.toString(),
        'action': 'get_stream',
      };

      if (csrfToken != null) {
        requestData['_token'] = csrfToken;
      }

      final response = await _client.dio.post<String>(
        '$baseUrl/ajax/get_cdn_series/',
        data: requestData,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$baseUrl/',
            'Origin': baseUrl,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            if (csrfToken != null) 'X-CSRF-TOKEN': csrfToken,
          },
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

    final pattern = RegExp(r'\[(\d+)p?\s*[^\]]*\]([^\[]+)');
    final matches = pattern.allMatches(decoded).toList();

    for (final match in matches) {
      final quality = match.group(1);
      var url = match.group(2)?.trim() ?? '';

      // Remove "or" alternatives (take first URL)
      if (url.contains(' or ')) {
        url = url.split(' or ').first;
      }

      // Clean up the URL - remove everything after .mp4 if it's a segment URL
      url = _cleanStreamUrl(url);

      // Skip URLs with invalid characters (decoding errors)
      if (url.contains('<') || url.contains('>')) {
        continue;
      }

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
      }
    }
  }

  /// Clean stream URL - remove segment suffixes for direct playback
  String _cleanStreamUrl(String url) {
    return normalizeStreamUrl(url);
  }

  /// Normalize HDRezka stream URL for direct playback.
  ///
  /// HDRezka returns segmented HLS URLs like:
  /// `https://cdn.../video.mp4:hls:seg-33-v1-a1.ts`
  /// or
  /// `https://cdn.../hash:timestamp:token/8/0/5/2/3/3/bc8qh.mp4`
  ///
  /// This method extracts a clean playable URL.
  static String normalizeStreamUrl(String url) {
    // Remove everything after " or " first
    if (url.contains(' or ')) {
      url = url.split(' or ').first;
    }

    // Handle :hls:manifest.m3u8 or :hls:seg-X patterns
    // Example: ...bc8qh.mp4:hls:manifest.m3u8 -> ...bc8qh.mp4
    final hlsPattern = RegExp(r':hls:.*$');
    if (hlsPattern.hasMatch(url)) {
      url = url.replaceAll(hlsPattern, '');
    }

    // Clean the segment path pattern /8/0/5/2/3/3/filename.mp4
    // This appears in CDN URLs - we want to keep it as it's part of the valid URL
    // But we need to make sure .mp4 is the end

    // If URL ends with .mp4 followed by anything, truncate at .mp4
    final mp4EndPattern = RegExp(r'(\.mp4).*$');
    if (mp4EndPattern.hasMatch(url) && !url.endsWith('.mp4')) {
      url = url.replaceAllMapped(mp4EndPattern, (m) => m.group(1)!);
    }

    // Remove trailing garbage characters
    url = url.replaceAll(RegExp(r'[\s\r\n,]+$'), '');

    // Remove any non-URL-safe characters that might have slipped through decoding
    // Valid URL characters: alphanumeric, - _ . ~ : / ? # [ ] @ ! $ & ' ( ) * + , ; = %
    // CDN URLs often have : in path for timestamps/tokens which is valid
    url = url.replaceAll(RegExp(r'[<>{}|\\^`\x00-\x1F\x7F-\xFF]'), '');

    return url.trim();
  }

  /// Validate stream URL
  bool _isValidStreamUrl(String url) {
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

  String _decodeStreamUrl(String encoded) {
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
        // These trash strings are known base64 values inserted at //_// or // markers
        // We need to remove ONLY the trash strings, not real data

        // Known trash strings (these are constant and decode to garbage symbols)
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
        // But ONLY if the base64 part is short (less than 30 chars) - these are trash
        base64Part = base64Part.replaceAll(
          RegExp(r'//[A-Za-z0-9+/]{1,25}='),
          '',
        );

        // Clean any remaining //
        base64Part = base64Part.replaceAll('//', '');

        // Remove underscore that might remain
        base64Part = base64Part.replaceAll('_', '');

        Logger.d(' After trash removal length: ${base64Part.length}');

        // Standard base64 decode
        try {
          // Pad if needed
          while (base64Part.length % 4 != 0) {
            base64Part += '=';
          }
          decoded = utf8.decode(base64.decode(base64Part));
          Logger.d(' Decoded successfully! Length: ${decoded.length}');
          Logger.d(
            '[HDRezka] Decoded first 200: ${decoded.substring(0, decoded.length.clamp(0, 200))}',
          );
        } catch (e) {
          Logger.d(' Base64 decode error: $e');
          // Try latin1 decoding instead of utf8 - but this may produce garbage chars
          try {
            decoded = latin1.decode(base64.decode(base64Part));
            // Remove non-printable and non-URL-safe characters that latin1 might produce
            decoded = decoded.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
            Logger.d(' Latin1 decode success! Length: ${decoded.length}');
          } catch (e2) {
            Logger.d(' Latin1 decode also failed: $e2');
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
