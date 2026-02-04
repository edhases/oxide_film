import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';
import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../mixins/resolved_url_mixin.dart';
import '../parsers/playerjs_parser.dart';

/// UAKino.best content provider
///
/// Ukrainian site using PlayerJS for streaming
class UakinoProvider with ResolvedUrlMixin implements ContentProvider {
  static const String _tag = 'UAKino';

  final ApiClient _client;
  bool _isEnabled = true;

  UakinoProvider(this._client);

  @override
  String get id => 'uakino';

  @override
  String get name => 'UAKino';

  @override
  String? get iconUrl => 'https://uakino.best/favicon.ico';

  String _mirror = 'https://uakino.best';

  @override
  String get baseUrl => _mirror;

  /// Set mirror URL
  void setMirror(String url) {
    _mirror = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

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
      final url = '$baseUrl/index.php?do=search';
      // UAKino uses POST for search
      final html = await _client.get(
        '$url&subaction=search&story=${Uri.encodeComponent(query)}&search_start=$page',
      );

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
    Logger.d('getStreams called with id: $id', tag: _tag);
    try {
      // 1. Fetch main page
      final url = '$baseUrl/$id.html';
      Logger.d('Fetching URL: $url', tag: _tag);
      final html = await _client.get(url);
      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      Logger.d('Parsing streams for: $id', tag: _tag);

      // 2. Identify news_id for AJAX
      String? newsId;
      // Pattern: hidden input
      final newsIdInput =
          soup.find('input', attrs: {'name': 'news_id'}) ??
          soup.find('input', attrs: {'id': 'news_id'});
      if (newsIdInput != null) {
        newsId = newsIdInput.attributes['value'];
        Logger.d('Found news_id from input: $newsId', tag: _tag);
      }
      // Pattern: data-news_id on container
      if (newsId == null) {
        final playerContainer =
            soup.find('div', attrs: {'data-news_id': true}) ??
            soup.find('div', class_: 'playlists-ajax') ??
            soup.find('div', class_: 'player-box');
        if (playerContainer != null) {
          newsId =
              playerContainer.attributes['data-news_id'] ??
              playerContainer.attributes['data-id'];
          Logger.d('Found news_id from container: $newsId', tag: _tag);
        }
      }
      // Pattern: ID from URL
      if (newsId == null) {
        final idMatch = RegExp(r'(\d+)-').firstMatch(id);
        if (idMatch != null) {
          newsId = idMatch.group(1);
          Logger.d('Extracted news_id from URL: $newsId', tag: _tag);
        }
      }

      // 3. Try AJAX Playlist (Prioritized for newer content like Harry Potter)
      if (newsId != null) {
        try {
          // UAKino requires xfield=playlist and POST request
          final ajaxUrl = '$baseUrl/engine/ajax/playlists.php';
          Logger.d(
            'Fetching AJAX playlist (POST): $ajaxUrl (news_id=$newsId)',
            tag: _tag,
          );

          final ajaxResp = await _client.dio.post<String>(
            ajaxUrl,
            data: {
              'news_id': newsId,
              'xfield': 'playlist',
              'time': DateTime.now().millisecondsSinceEpoch.toString(),
            },
            options: Options(
              headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': url},
              contentType: Headers.formUrlEncodedContentType,
              responseType: ResponseType.plain,
            ),
          );

          final responseBody = ajaxResp.data ?? '';
          Logger.d('AJAX response length: ${responseBody.length}', tag: _tag);

          if (responseBody.contains('file:') ||
              responseBody.contains('iframe') ||
              responseBody.contains('data-file')) {
            Logger.d('AJAX response allows parsing', tag: _tag);
            final ajaxSoup = BeautifulSoup(responseBody);

            // 3.1 Check for Playlists (data-file)
            final playlistsDiv = ajaxSoup.find(
              'div',
              class_: 'playlists-videos',
            );
            if (playlistsDiv != null) {
              final items = playlistsDiv.findAll('li');
              Logger.d(
                'Found ${items.length} playlist items in AJAX',
                tag: _tag,
              );

              // Group items by voiceover to track episode index per voiceover
              final voiceoverEpisodeIndex = <String, int>{};

              for (final item in items) {
                var dataFile = item.attributes['data-file'];
                var voiceover =
                    item.attributes['data-voice'] ?? item.text.trim();
                final dataId = item.attributes['data-id'] ?? '';
                // Clean the text to handle unicode escapes like \u0422 (which creates false positive 422)
                final episodeText = _cleanVoiceoverName(item.text.trim());

                // Clean voiceover name
                voiceover = _cleanVoiceoverName(voiceover);

                // Track episode index per voiceover
                voiceoverEpisodeIndex[voiceover] =
                    (voiceoverEpisodeIndex[voiceover] ?? 0) + 1;

                // Extract episode number from text like "Серія 1", "Episode 2", etc.
                // If text is just a number (like "421"), use the index instead
                int? episodeNum;
                final parsedNum = _parseEpisodeNumber(episodeText);

                // If parsed number is unreasonably high (>1000 for typical series)
                // and text looks like just a number, use the voiceover-specific index
                if (parsedNum != null &&
                    parsedNum > 500 &&
                    RegExp(r'^\d+$').hasMatch(episodeText)) {
                  episodeNum = voiceoverEpisodeIndex[voiceover];
                  Logger.d(
                    'Using index $episodeNum instead of parsed $parsedNum for "$episodeText"',
                    tag: _tag,
                  );
                } else {
                  episodeNum = parsedNum ?? voiceoverEpisodeIndex[voiceover];
                }

                // Extract season from data-id (format: "season_voiceIndex")
                int? seasonNum;
                if (dataId.contains('_')) {
                  seasonNum = int.tryParse(dataId.split('_').first);
                  if (seasonNum != null) {
                    seasonNum += 1; // 0-indexed to 1-indexed
                  }
                }

                if (dataFile != null) {
                  // Clean URL using helper method
                  dataFile = _cleanPlayerUrl(dataFile);
                  if (dataFile.isNotEmpty) {
                    // Parse quality from URL
                    final quality = _parseQualityFromUrl(dataFile);

                    // If it's a direct file (m3u8/mp4), add it directly
                    if (dataFile.contains('.m3u8') ||
                        dataFile.contains('.mp4')) {
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
                    } else {
                      // Otherwise it's likely an embed/player URL (e.g. ashdi)
                      // verifying it is an url
                      if (dataFile.startsWith('http')) {
                        await _parseDataFile(
                          dataFile,
                          voiceover,
                          sources,
                          season: seasonNum,
                          episode: episodeNum,
                          episodeTitle: episodeText,
                        );
                      }
                    }
                  }
                }
              }
            }

            // 3.2 Check for direct iframes in AJAX
            final ajaxIframes = ajaxSoup.findAll('iframe');
            Logger.d('Found ${ajaxIframes.length} iframes in AJAX', tag: _tag);
            for (final iframe in ajaxIframes) {
              await _parseIframe(iframe, sources);
            }

            // 3.3 Fallback to PlayerJs general parsing
            if (sources.isEmpty) {
              final fallbackSources = PlayerJsParser.parseFromHtml(
                responseBody,
              );
              sources.addAll(fallbackSources);
            }
          }
        } catch (e) {
          Logger.w('AJAX playlist failed: $e', tag: _tag);
        }
      }

      // Safety check: if we found streams via AJAX, we usually don't need to check static iframes
      // unless AJAX failed or returned nothing.
      if (sources.isNotEmpty) {
        return sources;
      }

      // 4. Pattern 1: Static Iframes (e.g. older movies)
      final iframes = soup.findAll('iframe');
      Logger.d('Found ${iframes.length} static iframes', tag: _tag);
      for (final iframe in iframes) {
        await _parseIframe(iframe, sources);
      }

      // 5. Pattern 2: Static Tabs (data-id)
      // Logic handled via AJAX above if data-id maps to news_id?
      // But sometimes tabs have specific data-id for different players.
      final tabs = soup.findAll('li', attrs: {'data-id': true});
      for (final tab in tabs) {
        // Skip if this looks like the main news_id we already processed
        if (tab.attributes['data-id'] == newsId) continue;

        // This part is complex and often redundant with AJAX call above.
        // Skipping for now unless verified specific case needs it.
      }

      // 6. Pattern 3: Static Playlists Div (redundant check for non-AJAX pages)
      final staticPlaylists = soup.find('div', class_: 'playlists-videos');
      if (staticPlaylists != null) {
        final items = staticPlaylists.findAll('li');
        for (final item in items) {
          var dataFile = item.attributes['data-file'];
          var voiceover = item.attributes['data-voice'] ?? item.text.trim();
          if (dataFile != null) {
            // Clean URL and voiceover
            dataFile = _cleanPlayerUrl(dataFile);
            voiceover = _cleanVoiceoverName(voiceover);
            if (dataFile.isNotEmpty) {
              await _parseDataFile(dataFile, voiceover, sources);
            }
          }
        }
      }

      // 7. Fallback: Direct PlayerJS in main HTML
      if (sources.isEmpty) {
        Logger.d('Trying direct HTML PlayerJS parse', tag: _tag);
        sources.addAll(PlayerJsParser.parseFromHtml(html));
      }

      // Deduplicate
      final uniqueSources = <String, StreamSource>{};
      for (final source in sources) {
        uniqueSources[source.url] = source;
      }

      Logger.d(
        'Total unique streams found: ${uniqueSources.length}',
        tag: _tag,
      );

      final result = uniqueSources.values.toList();

      // Refine quality based on URL checks if quality is low/unknown
      for (var i = 0; i < result.length; i++) {
        final stream = result[i];
        // If quality is low or unknown, double check URL
        // Ashdi/PlayerJS often defaults to 480p even for HD content
        if (stream.quality == StreamQuality.unknown ||
            stream.quality == StreamQuality.q360p ||
            stream.quality == StreamQuality.q480p) {
          final urlQuality = _parseQualityFromUrl(stream.url);
          // Upgrade if URL quality is better than current
          if (_getQualityValue(urlQuality) > _getQualityValue(stream.quality)) {
            Logger.d(
              'Upgrading quality for ${stream.url} from ${stream.quality} to $urlQuality',
              tag: _tag,
            );
            result[i] = stream.copyWith(quality: urlQuality);
          }
        }
      }

      // Sort: 1080p > 720p > 480p > 360p
      // This fixes the issue where 480p is picked over 1080p if they appear in wrong order
      result.sort((a, b) {
        // Compare resolution numbers (larger is better)
        final qA = _getQualityValue(a.quality);
        final qB = _getQualityValue(b.quality);
        return qB.compareTo(qA); // Descending
      });

      return result;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  /// Parse episode number from text like "Серія 1", "Episode 2", "Ep. 3"
  ///
  /// Uses multiple patterns to find the correct episode number,
  /// avoiding false positives like IDs embedded in the text.
  int? _parseEpisodeNumber(String text) {
    if (text.isEmpty) return null;

    // Patterns ordered by specificity (most specific first)
    final patterns = [
      RegExp(r'[Сс]ер[іi][яй]\s*(\d+)', caseSensitive: false), // Серія 1
      RegExp(r'[Ее]п[іi]зод\s*(\d+)', caseSensitive: false), // Епізод 1
      RegExp(r'[Ee]pisode\s*(\d+)', caseSensitive: false), // Episode 1
      RegExp(r'[Ee]p\.?\s*(\d+)', caseSensitive: false), // Ep. 1, Ep 1
      RegExp(r'[Сс]\.?\s*(\d+)'), // С. 1, С 1
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final num = int.tryParse(match.group(1) ?? '');
        if (num != null) {
          Logger.d('Parsed episode $num from "$text" using pattern', tag: _tag);
          return num;
        }
      }
    }

    // If text is purely a number or whitespace + number, use it
    final pureNumberMatch = RegExp(r'^\s*(\d+)\s*$').firstMatch(text);
    if (pureNumberMatch != null) {
      return int.tryParse(pureNumberMatch.group(1) ?? '');
    }

    // Fallback: find all numbers and use the last one
    // (assuming the last number is more likely to be the episode number)
    final allNumbers = RegExp(r'(\d+)').allMatches(text).toList();
    if (allNumbers.isNotEmpty) {
      // If there's only one number and it's reasonable (< 10000), use it
      if (allNumbers.length == 1) {
        final num = int.tryParse(allNumbers.first.group(1) ?? '');
        if (num != null && num < 10000) {
          Logger.d(
            'Parsed episode $num from "$text" (single number)',
            tag: _tag,
          );
          return num;
        }
      }
      // If there are multiple numbers, prefer the last (smaller) one
      // which is more likely to be the episode number
      final lastNum = int.tryParse(allNumbers.last.group(1) ?? '');
      if (lastNum != null && lastNum < 10000) {
        Logger.d(
          'Parsed episode $lastNum from "$text" (last number)',
          tag: _tag,
        );
        return lastNum;
      }
    }

    Logger.d('Could not parse episode number from: "$text"', tag: _tag);
    return null;
  }

  /// Parse quality from URL patterns
  ///
  /// Many HLS/streaming URLs contain quality info like:
  /// - /video_720p.m3u8
  /// - /hls/1080/master.m3u8
  /// - /stream_480p/playlist.m3u8
  StreamQuality _parseQualityFromUrl(String url) {
    final lowerUrl = url.toLowerCase();

    // Explicit quality patterns
    final qualityPatterns = [
      RegExp(r'[_\-/](\d{3,4})p[_\-/\.]'), // _720p_ or -1080p.
      RegExp(r'/(\d{3,4})p?/'), // /720/ or /720p/
      RegExp(r'_(\d{3,4})p\.'), // _720p.
      RegExp(r'\[(\d{3,4})p?\]'), // [720p] or [720]
    ];

    for (final pattern in qualityPatterns) {
      final match = pattern.firstMatch(lowerUrl);
      if (match != null) {
        final quality = _parseQuality(match.group(1));
        if (quality != StreamQuality.unknown) {
          Logger.d(
            'Parsed quality ${quality.displayName} from URL pattern',
            tag: _tag,
          );
          return quality;
        }
      }
    }

    // Check for explicit quality markers anywhere in URL
    if (lowerUrl.contains('4k') || lowerUrl.contains('2160')) {
      return StreamQuality.q4k;
    }
    if (lowerUrl.contains('1440') || lowerUrl.contains('2k')) {
      return StreamQuality.q1440p;
    }
    if (lowerUrl.contains('1080')) return StreamQuality.q1080p;
    if (lowerUrl.contains('720')) return StreamQuality.q720p;
    if (lowerUrl.contains('480')) return StreamQuality.q480p;
    if (lowerUrl.contains('360')) return StreamQuality.q360p;

    return StreamQuality.unknown;
  }

  /// Parse quality string to enum
  int _getQualityValue(StreamQuality quality) {
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

  /// Parse quality string to enum
  StreamQuality _parseQuality(String? quality) {
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

  /// Clean player URL from escaped characters
  String _cleanPlayerUrl(String url) {
    var cleaned = url
        .replaceAll(r'\/', '/')
        .replaceAll(r'\', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    // Ensure proper URL format
    if (cleaned.isNotEmpty && !cleaned.startsWith('http')) {
      if (cleaned.startsWith('//')) {
        cleaned = 'https:$cleaned';
      } else if (cleaned.startsWith('/')) {
        cleaned = '$baseUrl$cleaned';
      }
    }

    return cleaned;
  }

  /// Clean voiceover name from escaped characters and decode Unicode
  String _cleanVoiceoverName(String name) {
    var cleaned = name
        .replaceAll(r'\"', '')
        .replaceAll(r"\'", '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .trim();

    // Decode Unicode escape sequences like \u041d\u043e\u0432\u0438\u0439
    final unicodePattern = RegExp(r'\\u([0-9a-fA-F]{4})');
    cleaned = cleaned.replaceAllMapped(unicodePattern, (match) {
      final codePoint = int.parse(match.group(1)!, radix: 16);
      return String.fromCharCode(codePoint);
    });

    return cleaned.trim();
  }

  // Helper to parse data-file (Ashdi player URL)
  Future<void> _parseDataFile(
    String url,
    String voiceover,
    List<StreamSource> sources, {
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    // Validate URL
    if (url.isEmpty || !url.startsWith('http')) {
      Logger.w('Invalid player URL: $url', tag: _tag);
      return;
    }

    try {
      // Clean voiceover name
      final cleanVoiceover = _cleanVoiceoverName(voiceover);
      Logger.d(
        'Fetching player URL: $url (voiceover: $cleanVoiceover)',
        tag: _tag,
      );
      final playerHtml = await _client.get(url);
      final playerSources = PlayerJsParser.parseFromHtml(playerHtml);

      Logger.d('Found ${playerSources.length} sources from player', tag: _tag);

      if (playerSources.isNotEmpty) {
        for (final src in playerSources) {
          sources.add(
            StreamSource(
              url: src.url,
              quality: src.quality,
              type: src.type,
              voiceover: cleanVoiceover.isNotEmpty
                  ? cleanVoiceover
                  : src.voiceover,
              season: season ?? src.season,
              episode: episode ?? src.episode,
              episodeTitle: episodeTitle,
            ),
          );
        }
      }
    } catch (e) {
      Logger.w('Failed to parse player from $url: $e', tag: _tag);
    }
  }

  // Helper to parse iframe
  Future<void> _parseIframe(dynamic iframe, List<StreamSource> sources) async {
    final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
    if (src != null &&
        src.isNotEmpty &&
        !src.contains('youtube') &&
        !src.contains('google')) {
      try {
        String iframeUrl = src;
        if (!iframeUrl.startsWith('http')) {
          iframeUrl = src.startsWith('//') ? 'https:$src' : '$baseUrl$src';
        }
        Logger.d('Fetching iframe: $iframeUrl', tag: _tag);
        final iframeHtml = await _client.get(iframeUrl);
        final iframeSources = PlayerJsParser.parseFromHtml(iframeHtml);
        sources.addAll(iframeSources);
      } catch (e) {
        Logger.w('Failed to parse iframe: $e', tag: _tag);
      }
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/page/$page/'
          : '$baseUrl/$section/page/$page/';
      Logger.d('getPopular: type=$type, page=$page, url=$url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('getPopular: HTML length=${html.length}', tag: _tag);
      final items = _parseCatalog(html);
      Logger.d('getPopular: parsed ${items.length} items', tag: _tag);
      return items;
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/page/$page/'
          : '$baseUrl/$section/page/$page/';
      Logger.d('getNew: type=$type, page=$page, url=$url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('getNew: HTML length=${html.length}', tag: _tag);
      final items = _parseCatalog(html);
      Logger.d('getNew: parsed ${items.length} items', tag: _tag);
      return items;
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<String>> getCategories() async {
    return [
      'Трилери',
      'Детективи',
      'Фантастика',
      'Бойовики',
      'Військові',
      'Комедії',
      'Драми',
      'Мелодрами',
      'Пригоди',
      'Жахи',
      'Фентезі',
      'Сімейні',
      'Історичні',
      'Містичні',
      'Документальні',
      'Спортивні',
      'Біографія',
      'Кримінал',
      'Вестерн',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final genreSlug = ProviderGenreMappings.getSlugForProvider(id, category);
      final encodedCategory = Uri.encodeComponent(genreSlug);
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/xfsearch/genre/$encodedCategory/page/$page/'
          : '$baseUrl/$section/xfsearch/genre/$encodedCategory/page/$page/';
      final html = await _client.get(url);
      return _parseCatalog(html);
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

  String _getSection(ContentType? type) {
    switch (type) {
      case ContentType.movie:
        return 'filmy';
      case ContentType.series:
        return 'seriesss';
      case ContentType.cartoon:
        return 'cartoon';
      case ContentType.anime:
        return 'animeukr';
      default:
        return '';
    }
  }

  List<MediaItem> _parseSearchResults(String html) {
    return _parseCatalog(html);
  }

  List<MediaItem> _parseCatalog(String html) {
    final items = <MediaItem>[];
    final soup = BeautifulSoup(html);

    Logger.d('Starting catalog parsing...', tag: _tag);
    Logger.d('HTML length: ${html.length}', tag: _tag);

    // Debug: check if movie-item exists in HTML
    if (html.contains('movie-item')) {
      Logger.d('HTML contains "movie-item" class', tag: _tag);
    } else {
      Logger.w('HTML does NOT contain "movie-item" class!', tag: _tag);
    }

    // UAKino structure: find all movie containers
    // Beautiful Soup in Dart may need exact class match, so try with CSS selector
    var cards = <Bs4Element>[];

    // Try CSS selector first (more reliable for multiple classes)
    try {
      cards = soup.findAll('div', class_: 'movie-item');
      Logger.d('Found ${cards.length} .movie-item cards (findAll)', tag: _tag);
    } catch (e) {
      Logger.w('findAll failed: $e', tag: _tag);
    }

    // If not found, try looking for elements that contain movie-item in class
    if (cards.isEmpty) {
      // Manual search through all divs
      final allDivs = soup.findAll('div');
      Logger.d('Total divs: ${allDivs.length}', tag: _tag);

      cards = allDivs.where((div) {
        final className = div.attributes['class'] ?? '';
        return className.contains('movie-item') ||
            className.contains('short-item');
      }).toList();
      Logger.d('Found ${cards.length} cards by class contains', tag: _tag);
    }

    // Try finding by movie container pattern (fallback to links)
    if (cards.isEmpty) {
      // Find all links that look like movie pages
      final allLinks = soup.findAll('a');
      Logger.d('Total links found: ${allLinks.length}', tag: _tag);

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

          // Check if it's a movie/series link (must have section in URL)
          final moviePattern = RegExp(
            r'/(filmy|seriesss|cartoon|animeukr)/[^/]+/\d+-',
          );
          final shortPattern = RegExp(r'/\d+-[^/]+\.html$');

          if (!moviePattern.hasMatch(href) && !shortPattern.hasMatch(href)) {
            continue;
          }

          // Get title from link text or from adjacent/child elements
          var title = link.text.trim();

          // If link is empty (just contains image), find title in sibling or parent
          if (title.isEmpty || title.length < 3) {
            // Check for adjacent link with title
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

          // Skip if still no title
          if (title.isEmpty || title.length < 3) continue;

          // Skip duplicate entries (same URL already added)
          final itemId = _extractItemId(href);

          if (items.any((i) => i.id == itemId)) continue;

          // Get poster from image inside link or nearby
          String? posterUrl;
          final img = link.find('img');
          if (img != null) {
            posterUrl =
                img.attributes['src'] ?? img.attributes['data-src'] ?? '';
          }

          // If no image in link, check parent
          if ((posterUrl == null || posterUrl.isEmpty) && link.parent != null) {
            final parentImg = link.parent!.find('img');
            if (parentImg != null) {
              posterUrl =
                  parentImg.attributes['src'] ??
                  parentImg.attributes['data-src'];
            }
          }

          // Try to extract year from parent container
          int? year;
          double? rating;
          List<String>? genres;
          String? country;
          if (link.parent != null) {
            final parent = link.parent!;
            // Year
            final yearEl =
                parent.find('div', class_: 'movie-year') ??
                parent.find('span', class_: 'year') ??
                parent.find('div', class_: 'year');
            if (yearEl != null) {
              year = int.tryParse(
                yearEl.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
              );
            }
            // Rating
            final ratingEl =
                parent.find('div', class_: 'movie-rating') ??
                parent.find('span', class_: 'rating') ??
                parent.find('div', class_: 'rating');
            if (ratingEl != null) {
              rating = double.tryParse(
                ratingEl.text
                    .trim()
                    .replaceAll(',', '.')
                    .replaceAll(RegExp(r'[^\d.]'), ''),
              );
            }
            // Fallback: search in text
            if (year == null) {
              final yearMatch = RegExp(
                r'\b(19\d{2}|20[0-3]\d)\b',
              ).firstMatch(parent.text);
              if (yearMatch != null) {
                year = int.tryParse(yearMatch.group(1) ?? '');
              }
            }

            // Parse genres if available
            final genreEl =
                parent.find('div', class_: 'movie-genre') ??
                parent.find('span', class_: 'genre') ??
                parent.find('div', class_: 'genres');
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

            // Parse country if available
            final countryEl =
                parent.find('div', class_: 'movie-country') ??
                parent.find('span', class_: 'country');
            if (countryEl != null) {
              country = countryEl.text.trim().split(',').first.trim();
            }
          }

          items.add(
            MediaItem(
              id: itemId,
              providerId: id,
              title: title,
              posterUrl: _normalizeImageUrl(posterUrl),
              year: year,
              rating: rating,
              type: _detectType(href),
              genres: genres,
              country: country,
            ),
          );
        } catch (e) {
          // Skip problematic links
        }
      }
    } else {
      // Old structure parsing
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
          Logger.d('Parsed itemId: $itemId from href: $href', tag: _tag);

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
              providerId: id,
              title: title,
              posterUrl: _normalizeImageUrl(posterUrl),
              year: year,
              rating: rating,
              type: _detectType(href),
              genres: genres,
              country: country,
            ),
          );
        } catch (e) {
          Logger.w('Failed to parse card', tag: _tag);
        }
      }
    }

    Logger.i('Parsed ${items.length} items from catalog', tag: _tag);

    // Deduplicate items by ID
    final uniqueItems = <String, MediaItem>{};
    for (final item in items) {
      if (!uniqueItems.containsKey(item.id)) {
        uniqueItems[item.id] = item;
      }
    }

    return uniqueItems.values.toList();
  }

  String _extractItemId(String href) {
    // Extract ID from URL - preserve full path for proper URL construction
    // URL format: /filmy/genre_adventure/213-movie-id.html or /213-movie-id.html
    if (href.startsWith('/')) {
      // Remove leading slash and .html extension
      return href.substring(1).replaceAll('.html', '');
    } else if (href.startsWith(baseUrl)) {
      // Remove base URL and .html extension
      return href.replaceFirst('$baseUrl/', '').replaceAll('.html', '');
    } else {
      // Fallback: just use the href without .html
      var id = href.replaceAll('.html', '');
      // If ID still contains slashes, take the last segment
      if (id.contains('/')) {
        id = id.split('/').last;
      }
      return id;
    }
  }

  MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Get main info
    final titleEl =
        soup.find('h1', class_: 'solototle') ??
        soup.find('h1', class_: 'short-title') ??
        soup.find('h1') ??
        soup.find('title');
    final title = titleEl?.text.trim() ?? mediaId;

    // Get poster - try multiple selectors
    String? posterUrl;

    // Try common UAKino poster selectors
    final posterSelectors = [
      () => soup.find('div', class_: 'fposter')?.find('img'),
      () => soup.find('div', class_: 'film-poster')?.find('img'),
      () => soup.find('div', class_: 'poster')?.find('img'),
      () => soup.find('img', class_: 'fimg'),
      () => soup.find('img', class_: 'film-img'),
      () => soup.find('img', attrs: {'itemprop': 'image'}),
      () => soup.find('a', class_: 'fancybox')?.find('img'),
      // Look in short-info or film-info sections
      () => soup.find('div', class_: 'short-img')?.find('img'),
      () => soup.find('div', class_: 'fimg-d')?.find('img'),
    ];

    for (final selector in posterSelectors) {
      final img = selector();
      if (img != null) {
        posterUrl = img.attributes['src'] ?? img.attributes['data-src'];
        if (posterUrl != null && posterUrl.isNotEmpty) {
          Logger.d('Found poster with selector, URL: $posterUrl', tag: _tag);
          break;
        }
      }
    }

    // Fallback: find any img with poster-like URL pattern
    if (posterUrl == null) {
      final allImages = soup.findAll('img');
      for (final img in allImages) {
        final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        if (src.contains('poster') ||
            src.contains('uploads') ||
            src.contains('image')) {
          posterUrl = src;
          Logger.d('Found poster via URL pattern: $posterUrl', tag: _tag);
          break;
        }
      }
    }

    // Get description - try multiple selectors
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
          Logger.d('Found description (${desc.length} chars)', tag: _tag);
          break;
        }
      }
    }

    // Get info table
    final infoTable = soup.find('div', class_: 'flist');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;

    if (infoTable != null) {
      final rows = infoTable.findAll('li');
      for (final row in rows) {
        final text = row.text.toLowerCase();
        if (text.contains('режисер')) {
          director =
              row.find('a')?.text.trim() ?? row.text.split(':').last.trim();
        } else if (text.contains('актор')) {
          actors = row.findAll('a').map((a) => a.text.trim()).toList();
          // Fallback: if no links, split by comma
          if (actors.isEmpty) {
            actors = row.text
                .split(':')
                .last
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        } else if (text.contains('жанр')) {
          genres = row.findAll('a').map((a) => a.text.trim()).toList();
        } else if (text.contains('країна')) {
          countries = row.findAll('a').map((a) => a.text.trim()).toList();
        } else if (text.contains('рік')) {
          final yearStr =
              row.find('a')?.text.trim() ??
              row.text.replaceAll(RegExp(r'\D'), '');
          year = int.tryParse(yearStr);
        }
      }
    } else {
      // Fallback: Parsing from description or generic text if table is missing
      final fullText = soup.text;

      // Year
      final yearMatch = RegExp(r'Рік:\s*(\d{4})').firstMatch(fullText);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }

      // Country
      final countryMatch = RegExp(
        r'Країна:\s*([^<\n\r]+)',
      ).firstMatch(fullText);
      if (countryMatch != null) {
        countries = countryMatch
            .group(1)!
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: id,
        title: title,
        posterUrl: _normalizeImageUrl(posterUrl),
        year: year,
        type: _detectType(mediaId),
        description: description,
        country: countries?.firstOrNull,
        genres: genres,
      ),
      fullDescription: description,
      director: director,
      actors: actors,
      genres: genres,
      countries: countries,
    );
  }

  String? _normalizeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '$baseUrl$url';
  }

  ContentType _detectType(String url) {
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
