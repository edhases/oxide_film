import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'; // Added for compute

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../mixins/resolved_url_mixin.dart';
import '../parsers/playerjs_parser.dart';

/// Eneyida content provider
///
/// Ukrainian streaming site with PlayerJS player
class EneyidaProvider with ResolvedUrlMixin implements ContentProvider {
  static const String _tag = 'Eneyida';

  final ApiClient _client;
  bool _isEnabled = true;

  EneyidaProvider(this._client);

  @override
  String get id => 'eneyida';

  @override
  String get name => 'Eneyida';

  @override
  String? get iconUrl => '$effectiveBaseUrl/favicon.ico';

  String _mirror = 'https://eneyida.tv';

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
      final url =
          '$baseUrl/index.php?do=search&subaction=search'
          '&story=${Uri.encodeComponent(query)}'
          '&search_start=$page';

      final html = await _client.get(url);
      return compute(_parseSearchResultsStatic, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<MediaDetails> getDetails(String id) async {
    try {
      // Sanitize ID - remove domain if present
      var cleanId = id;
      if (cleanId.contains('eneyida.tv/')) {
        cleanId = cleanId.replaceAll('eneyida.tv/', '');
      }
      if (cleanId.startsWith('/')) {
        cleanId = cleanId.substring(1);
      }

      final html = await _client.get('$baseUrl/$cleanId.html');
      return compute(_parseDetailsStatic, ParseDetailsArgs(html, cleanId));
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
      // Sanitize ID - remove domain if present
      var cleanId = id;
      if (cleanId.contains('eneyida.tv/')) {
        cleanId = cleanId.replaceAll('eneyida.tv/', '');
      }
      if (cleanId.startsWith('/')) {
        cleanId = cleanId.substring(1);
      }

      final url = '$baseUrl/$cleanId.html';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('HTML length: ${html.length}', tag: _tag);
      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // 1. Try AJAX playlist first (most common method)
      final newsId = _extractNewsId(soup, id);
      Logger.d('Extracted news_id: $newsId', tag: _tag);

      if (newsId != null) {
        await _loadAjaxPlaylist(newsId, sources, season, episode);
        Logger.d('AJAX playlist returned ${sources.length} sources', tag: _tag);
      }

      // 2. Try to find player iframe if AJAX didn't work
      if (sources.isEmpty) {
        final iframes = soup.findAll('iframe');
        Logger.d('Found ${iframes.length} iframes', tag: _tag);
        for (final iframe in iframes) {
          final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
          if (src != null && src.isNotEmpty) {
            Logger.d('Parsing iframe: $src', tag: _tag);
            await _parseIframeSource(src, sources);
          }
        }
      }

      // 3. Try direct script parsing for PlayerJS
      if (sources.isEmpty) {
        Logger.d('Trying script parsing...', tag: _tag);
        final scripts = soup.findAll('script');
        for (final script in scripts) {
          final content = script.text;
          if (content.contains('new Playerjs') || content.contains('file:')) {
            final parsed = await PlayerJsParser.parseFromHtmlCompute(content);
            Logger.d(
              'Script parsing found ${parsed.length} sources',
              tag: _tag,
            );
            sources.addAll(parsed);
          }
        }
      }

      // 4. Fallback to full HTML PlayerJS parsing
      if (sources.isEmpty) {
        Logger.d('Fallback to PlayerJS parse', tag: _tag);
        final parsed = await PlayerJsParser.parseFromHtmlCompute(html);
        Logger.d('PlayerJS found ${parsed.length} sources', tag: _tag);
        sources.addAll(parsed);
      }

      Logger.d('Total sources found: ${sources.length}', tag: _tag);
      return _deduplicateSources(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  List<StreamSource> _deduplicateSources(List<StreamSource> sources) {
    final unique = <String, StreamSource>{};
    for (final source in sources) {
      if (!unique.containsKey(source.url)) {
        unique[source.url] = source;
      }
    }
    return unique.values.toList();
  }

  String? _extractNewsId(BeautifulSoup soup, String id) {
    // Try hidden input (news_id or post_id)
    final input =
        soup.find('input', attrs: {'name': 'news_id'}) ??
        soup.find('input', attrs: {'name': 'post_id'});
    if (input != null) {
      final value = input.attributes['value'];
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    // Try from article id
    final article = soup.find('article', attrs: {'id': true});
    if (article != null) {
      final artId = article.attributes['id'];
      final match = RegExp(r'(\d+)').firstMatch(artId ?? '');
      if (match != null) return match.group(1);
    }

    // Try from media ID (format: "section/123-name")
    final match = RegExp(r'(\d+)-').firstMatch(id);
    if (match != null) return match.group(1);

    // Try from any data-news_id attribute
    final newsIdEl = soup.find('*', attrs: {'data-news_id': true});
    if (newsIdEl != null) {
      return newsIdEl.attributes['data-news_id'];
    }

    return null;
  }

  Future<void> _loadAjaxPlaylist(
    String newsId,
    List<StreamSource> sources,
    int? season,
    int? episode,
  ) async {
    try {
      final url = '$baseUrl/engine/ajax/playlists.php';
      Logger.d('AJAX playlist request: $url, news_id=$newsId', tag: _tag);

      final response = await _client.dio.post<String>(
        url,
        data: {'news_id': newsId, 'xfield': 'playlist'},
        options: Options(
          headers: {'X-Requested-With': 'XMLHttpRequest'},
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      Logger.d('AJAX response status: ${response.statusCode}', tag: _tag);
      final responseBody = response.data ?? '';
      Logger.d('AJAX response length: ${responseBody.length}', tag: _tag);

      if (responseBody.isEmpty) {
        Logger.w('AJAX response is empty', tag: _tag);
        return;
      }

      Logger.d(
        'AJAX response preview: ${responseBody.substring(0, responseBody.length.clamp(0, 500))}',
        tag: _tag,
      );

      final soup = BeautifulSoup(responseBody);

      // Parse playlist items
      final items = soup.findAll('li');
      Logger.d('Found ${items.length} playlist items', tag: _tag);

      for (final item in items) {
        final dataFile = item.attributes['data-file'];
        final voiceover = item.attributes['data-voice'] ?? item.text.trim();

        if (dataFile != null) {
          Logger.d(
            'Playlist item: data-file=${dataFile.substring(0, dataFile.length.clamp(0, 100))}, voice=$voiceover',
            tag: _tag,
          );
        } else {
          Logger.d(
            'Playlist item: data-file=null, voice=$voiceover',
            tag: _tag,
          );
        }

        if (dataFile != null && dataFile.isNotEmpty) {
          // Check if this is for specific episode
          final itemSeason = int.tryParse(item.attributes['data-season'] ?? '');
          final itemEpisode = int.tryParse(
            item.attributes['data-episode'] ?? '',
          );

          Logger.d(
            '  Item season=$itemSeason, episode=$itemEpisode (looking for s=$season, e=$episode)',
            tag: _tag,
          );

          if (season != null && episode != null) {
            if (itemSeason == season && itemEpisode == episode) {
              Logger.d('  Matched episode - parsing', tag: _tag);
              await _parseDataFile(dataFile, voiceover, sources);
            }
          } else if (itemSeason == null && itemEpisode == null) {
            // Movie
            Logger.d('  Movie item - parsing', tag: _tag);
            await _parseDataFile(dataFile, voiceover, sources);
          }
        }
      }
    } catch (e, stack) {
      Logger.w('AJAX playlist failed: $e', tag: _tag);
      Logger.w('Stack: $stack', tag: _tag);
    }
  }

  // Static parsing methods for Compute (Isolate)

  static List<MediaItem> _parseSearchResultsStatic(String html) {
    // Moved logic from _parseSearchResults
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // Main content cards
    final cards = soup.findAll('article', class_: 'short');
    if (cards.isEmpty) {
      // Try alternative
      final altCards = soup.findAll('div', class_: 'short-item');
      for (final card in altCards) {
        final item = _parseCardStatic(card);
        if (item != null) items.add(item);
      }
    }

    for (final card in cards) {
      final item = _parseCardStatic(card);
      if (item != null) items.add(item);
    }

    return items;
  }

  static MediaItem? _parseCardStatic(dynamic card) {
    try {
      final link = card.find('a', class_: 'short_img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrlStatic(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      final titleEl =
          card.find('a', class_: 'short_title') ??
          card.find('div', class_: 'short_title');
      final title = titleEl?.text.trim() ?? link.attributes['title'] ?? '';

      int? year;
      final infoEl = card.find('div', class_: 'short_info');
      if (infoEl != null) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
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

      double? rating;
      final ratingEl = card.find('span', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
      }

      // Parse genres from card
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'short_genre') ??
          card.find('span', class_: 'genre');
      if (genreEl != null) {
        final genreLinks = genreEl.findAll('a');
        if (genreLinks.isNotEmpty) {
          genres = genreLinks
              .map((a) => a.text.trim())
              .where((g) => g.isNotEmpty)
              .toList();
        } else {
          // Try parsing comma-separated text
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
      String? country;
      final countryEl =
          card.find('span', class_: 'country') ??
          card.find('div', class_: 'short_country');
      if (countryEl != null) {
        country = countryEl.text.trim();
      }

      final type = _detectContentTypeStatic(href);

      return MediaItem(
        id: mediaId,
        providerId: 'eneyida', // Cannot use id getter in static context
        title: title,
        posterUrl: _absoluteUrlStatic(posterUrl),
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

  static String? _absoluteUrlStatic(String? url) {
    const baseUrl =
        'https://eneyida.tv'; // Hardcoded for static context or pass as arg if needed
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }

  static String _extractIdFromUrlStatic(String url) {
    // Format: https://eneyida.tv/films/12345-movie-name.html
    final match = RegExp(r'/([^/]+)/(\d+-[^/]+)\.html').firstMatch(url);
    if (match != null) {
      return '${match.group(1)}/${match.group(2)}';
    }
    // Fallback
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.isNotEmpty) {
      var path = uri.path;
      // Fix for double domain in path issue
      if (path.contains('eneyida.tv/')) {
        path = path.replaceAll('eneyida.tv/', '');
      }
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

  static ContentType _detectContentTypeStatic(String url) {
    if (url.contains('/films/') || url.contains('films/')) {
      return ContentType.movie;
    }
    if (url.contains('/series/') || url.contains('series/')) {
      return ContentType.series;
    }
    if (url.contains('/cartoon/') || url.contains('cartoon/')) {
      return ContentType.cartoon;
    }
    if (url.contains('/anime/') || url.contains('anime/')) {
      return ContentType.anime;
    }
    return ContentType.unknown;
  }

  /// Detect content type from HTML page structure (breadcrumbs, links, etc.)
  static ContentType _detectContentTypeFromHtml(
    BeautifulSoup soup,
    String mediaId,
  ) {
    // First try from mediaId/URL
    final urlType = _detectContentTypeStatic(mediaId);
    if (urlType != ContentType.unknown) return urlType;

    // Try breadcrumbs
    final breadcrumbs =
        soup.find('ul', class_: 'bread-crumbs') ??
        soup.find('div', class_: 'breadcrumb');
    if (breadcrumbs != null) {
      final links = breadcrumbs.findAll('a');
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        final text = link.text.toLowerCase();
        if (href.contains('/films/') || text.contains('фільм')) {
          return ContentType.movie;
        }
        if (href.contains('/series/') || text.contains('серіал')) {
          return ContentType.series;
        }
        if (href.contains('/cartoon/') || text.contains('мультфільм')) {
          return ContentType.cartoon;
        }
        if (href.contains('/anime/') || text.contains('аніме')) {
          return ContentType.anime;
        }
      }
    }

    // Try category info block
    final categoryEl =
        soup.find('span', class_: 'category') ??
        soup.find('div', class_: 'full_category');
    if (categoryEl != null) {
      final text = categoryEl.text.toLowerCase();
      if (text.contains('фільм')) return ContentType.movie;
      if (text.contains('серіал')) return ContentType.series;
      if (text.contains('мультфільм')) return ContentType.cartoon;
      if (text.contains('аніме')) return ContentType.anime;
    }

    // Check if it has seasons (series indicator)
    final hasSeasonsBlock = soup.find('div', class_: 'playlists-ajax') != null;
    if (hasSeasonsBlock) return ContentType.series;

    return ContentType.unknown;
  }

  static MediaDetails _parseDetailsStatic(ParseDetailsArgs args) {
    return _parseDetails(args.html, args.mediaId);
  }

  Future<void> _parseIframeSource(
    String src,
    List<StreamSource> sources,
  ) async {
    try {
      var url = src;
      if (url.startsWith('//')) {
        url = 'https:$url';
      }

      final html = await _client.get(url);
      final parsed = await PlayerJsParser.parseFromHtmlCompute(html);
      sources.addAll(parsed);
    } catch (e) {
      Logger.w('Failed to parse iframe: $e', tag: _tag);
    }
  }

  Future<void> _parseDataFile(
    String dataFile,
    String voiceover,
    List<StreamSource> sources,
  ) async {
    Logger.d('_parseDataFile: url=$dataFile, voiceover=$voiceover', tag: _tag);
    try {
      var url = dataFile.trim();
      if (url.startsWith('//')) {
        url = 'https:$url';
      }
      // Fix: Eneyida sometimes returns urls like "eneyida.tv/https://..." or double domains
      // Regex to remove prefix if it contains the domain again
      if (url.contains('eneyida.tv/eneyida.tv/')) {
        url = url.replaceAll('eneyida.tv/eneyida.tv/', 'eneyida.tv/');
      }
      if (!url.startsWith('http')) {
        // Only prepend if it's not already a full url (some are relative)
        if (url.startsWith('/')) {
          url = '$baseUrl$url';
        } else {
          // check if it's "domain.com/..." without http
          if (url.contains('eneyida.tv')) {
            url = 'https://$url';
          }
        }
      }

      // If it's a direct stream URL
      if (url.contains('.m3u8') || url.contains('.mp4')) {
        Logger.d('  Direct stream URL detected: $url', tag: _tag);
        sources.add(
          StreamSource(
            url: url,
            quality: _detectQuality(url),
            voiceover: voiceover.isNotEmpty ? voiceover : null,
            type: url.contains('.m3u8') ? StreamType.hls : StreamType.direct,
          ),
        );
        return;
      }

      // If it's a player page, parse it
      if (url.startsWith('http')) {
        Logger.d('  Fetching player page: $url', tag: _tag);
        final html = await _client.get(url);
        Logger.d('  Player page length: ${html.length}', tag: _tag);
        final parsed = await PlayerJsParser.parseFromHtmlCompute(html);
        Logger.d('  PlayerJS parsed ${parsed.length} streams', tag: _tag);
        for (final stream in parsed) {
          Logger.d(
            '  Adding stream: ${stream.url.substring(0, stream.url.length.clamp(0, 100))}',
            tag: _tag,
          );
          sources.add(
            StreamSource(
              url: stream.url,
              quality: stream.quality,
              voiceover: voiceover.isNotEmpty ? voiceover : stream.voiceover,
              type: stream.type,
            ),
          );
        }
      } else {
        Logger.w('  Unknown URL format: $url', tag: _tag);
      }
    } catch (e, stack) {
      Logger.w('Failed to parse data-file: $e', tag: _tag);
      Logger.w('Stack: $stack', tag: _tag);
    }
  }

  StreamQuality _detectQuality(String url) {
    if (url.contains('1080')) return StreamQuality.q1080p;
    if (url.contains('720')) return StreamQuality.q720p;
    if (url.contains('480')) return StreamQuality.q480p;
    if (url.contains('360')) return StreamQuality.q360p;
    return StreamQuality.unknown;
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
          section = 'cartoon';
          break;
        case ContentType.anime:
          section = 'anime';
          break;
        default:
          section = 'films';
      }

      final html = await _client.get('$baseUrl/$section/page/$page/');
      return compute(_parseSearchResultsStatic, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      final html = await _client.get('$baseUrl/page/$page/');
      return compute(_parseSearchResultsStatic, html);
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
      'Історичний',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final genreSlug = _categoryToSlug(category);
      final html = await _client.get('$baseUrl/genre/$genreSlug/page/$page/');
      return compute(_parseSearchResultsStatic, html);
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

  String _categoryToSlug(String category) {
    final map = {
      'Бойовик': 'boyovik',
      'Детектив': 'detektyv',
      'Драма': 'drama',
      'Комедія': 'komediya',
      'Мелодрама': 'melodrama',
      'Пригоди': 'pryhody',
      'Трилер': 'tryler',
      'Фантастика': 'fantastyka',
      'Фентезі': 'fentezi',
      'Жахи': 'zhakhy',
      'Історичний': 'istorychnyy',
    };
    return map[category] ?? category.toLowerCase();
  }

  // Method _parseDetails made static for compute
  static MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1', class_: 'full_title');
    final title = titleEl?.text.trim() ?? '';

    String? originalTitle;
    final origEl = soup.find('div', class_: 'full_orig-title');
    if (origEl != null) {
      originalTitle = origEl.text.trim();
    }

    // Fast robust poster finder: look for img with /uploads/posts/ in src or data-src
    String? posterUrl;
    final images = soup.findAll('img');
    for (final img in images) {
      final src = img.attributes['src'];
      final dataSrc = img.attributes['data-src'];
      final dataOrig = img.attributes['data-original'];

      if (src != null && src.contains('/uploads/posts/')) {
        posterUrl = src;
        break;
      }
      if (dataSrc != null && dataSrc.contains('/uploads/posts/')) {
        posterUrl = dataSrc;
        break;
      }
      if (dataOrig != null && dataOrig.contains('/uploads/posts/')) {
        posterUrl = dataOrig;
        break;
      }
    }

    // Fallback to old logic if not found
    if (posterUrl == null) {
      final posterEl = soup.find('div', class_: 'full_poster');
      final posterImg = posterEl?.find('img');
      posterUrl =
          posterImg?.attributes['src'] ?? posterImg?.attributes['data-src'];
      posterUrl ??= posterImg?.attributes['data-original'];
    }

    // Info
    final infoBlock = soup.find('div', class_: 'full_info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    Duration? duration;

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('div', class_: 'full_info-item')) {
        final label =
            row.find('span', class_: 'fi-label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'fi-value');

        if (label.contains('режис')) {
          director = value?.text.trim();
        } else if (label.contains('актор')) {
          actors = value?.findAll('a').map((a) => a.text.trim()).toList();
          if (actors?.isEmpty ?? true) {
            actors = value?.text.split(',').map((s) => s.trim()).toList();
          }
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('країн')) {
          countries = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік')) {
          year = int.tryParse(value?.text.trim() ?? '');
        } else if (label.contains('трива')) {
          final durMatch = RegExp(r'(\d+)').firstMatch(value?.text ?? '');
          if (durMatch != null) {
            duration = Duration(minutes: int.parse(durMatch.group(1)!));
          }
        }
      }
    }

    // Fallback: search in description or full text if year/countries/director missing
    if (year == null) {
      final yearMatch = RegExp(r'Рік:\s*(\d{4})').firstMatch(soup.text);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'full_text');
    final description = descEl?.text.trim();

    // Rating
    double? rating;
    final ratingEl = soup.find('span', class_: 'full_rating');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    // Seasons for series
    List<Season>? seasons;
    final playlistBlock = soup.find('div', class_: 'playlists-ajax');
    if (playlistBlock != null) {
      seasons = _parseSeasons(soup);
    }

    // Use enhanced type detection from HTML
    final type = _detectContentTypeFromHtml(soup, mediaId);

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: 'eneyida', // Hardcoded for static parsing
        title: title,
        originalTitle: originalTitle,
        posterUrl: _absoluteUrlStatic(posterUrl),
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

    final seasonTabs = soup.findAll('li', class_: 'season-tab');

    for (final tab in seasonTabs) {
      final seasonNum =
          int.tryParse(tab.attributes['data-season'] ?? '') ??
          seasons.length + 1;

      final episodes = <Episode>[];
      final episodeItems = soup.findAll(
        'li',
        attrs: {'data-season': seasonNum.toString()},
      );

      for (final epItem in episodeItems) {
        if (epItem.attributes['data-episode'] != null) {
          final epNum =
              int.tryParse(epItem.attributes['data-episode'] ?? '') ??
              episodes.length + 1;
          final epTitle = epItem.text.trim();

          episodes.add(Episode(number: epNum, title: epTitle));
        }
      }

      if (episodes.isNotEmpty) {
        seasons.add(Season(number: seasonNum, episodes: episodes));
      }
    }

    return seasons;
  }
}

/// Arguments wrapper for parseDetails
class ParseDetailsArgs {
  final String html;
  final String mediaId;

  ParseDetailsArgs(this.html, this.mediaId);
}
