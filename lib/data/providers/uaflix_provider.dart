import 'package:beautiful_soup_dart/beautiful_soup.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../parsers/playerjs_parser.dart';

/// UAFlix content provider
///
/// Ukrainian streaming site with Netflix content dubbed in Ukrainian
class UaflixProvider implements ContentProvider {
  static const String _tag = 'UAFlix';

  final ApiClient _client;
  bool _isEnabled = true;

  UaflixProvider(this._client);

  @override
  String get id => 'uaflix';

  @override
  String get name => 'UAFlix';

  @override
  String? get iconUrl => '$baseUrl/favicon.ico';

  @override
  String get baseUrl => 'https://uaflix.net';

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

      Logger.d('Search: $url', tag: _tag);
      final html = await _client.get(url);
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      String category;
      switch (type) {
        case ContentType.movie:
          category = 'film';
          break;
        case ContentType.series:
          category = 'serials';
          break;
        case ContentType.cartoon:
          category = 'cartoons';
          break;
        case ContentType.anime:
          category = 'anime';
          break;
        default:
          category = 'film';
      }

      final url = '$baseUrl/$category/page/$page/';
      Logger.d('Get popular: $url', tag: _tag);
      final html = await _client.get(url);
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      String category;
      switch (type) {
        case ContentType.movie:
          category = 'films/new_netflix_ua';
          break;
        case ContentType.series:
          category = 'serials/new_uaserial';
          break;
        default:
          category = 'films/new_netflix_ua';
      }

      final url = '$baseUrl/$category/page/$page/';
      Logger.d('Get new: $url', tag: _tag);
      final html = await _client.get(url);
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<String>> getCategories() async {
    return [
      'films/new_netflix_ua',
      'films/teen_films',
      'films/love_films',
      'films/documental_films',
      'films/films_horror',
      'films/action',
      'films/melodrama',
      'films/fantastics',
      'films/comedy',
      'serials/new_uaserial',
      'serials/detective',
      'serials/history_serials',
      'serials/comedy_serials',
      'serials/fantasy_serialy',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final url = '$baseUrl/$category/page/$page/';
      Logger.d('Get by category: $url', tag: _tag);
      final html = await _client.get(url);
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

  @override
  Future<MediaDetails> getDetails(String mediaId) async {
    try {
      // UAFlix URLs end with / not .html
      final url = '$baseUrl/$mediaId/';
      Logger.d('Get details: $url', tag: _tag);
      final html = await _client.get(url);
      return _parseDetails(html, mediaId);
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  @override
  Future<List<StreamSource>> getStreams(
    String mediaId, {
    int? season,
    int? episode,
  }) async {
    Logger.d('getStreams: id=$mediaId, s=$season, e=$episode', tag: _tag);
    print('[UAFlix] getStreams: id=$mediaId, s=$season, e=$episode');
    try {
      // UAFlix URLs end with / not .html
      final url = '$baseUrl/$mediaId/';
      print('[UAFlix] Fetching: $url');
      final html = await _client.get(url);
      print('[UAFlix] HTML length: ${html.length}');

      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // Try iframes first
      final iframes = soup.findAll('iframe');
      print('[UAFlix] Found ${iframes.length} iframes');
      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          await _parseIframeSource(src, sources);
        }
      }

      // Try PlayerJS parsing
      if (sources.isEmpty) {
        print('[UAFlix] Trying PlayerJS parsing...');
        final parsed = PlayerJsParser.parseFromHtml(html);
        print('[UAFlix] PlayerJS found ${parsed.length} sources');
        sources.addAll(parsed);
      }

      // Try video elements
      if (sources.isEmpty) {
        final videoEls = soup.findAll('video');
        for (final video in videoEls) {
          final src =
              video.attributes['src'] ??
              video.find('source')?.attributes['src'];
          if (src != null && src.isNotEmpty) {
            sources.add(
              StreamSource(
                url: _absoluteUrl(src) ?? src,
                quality: StreamQuality.unknown,
                sourceName: 'default',
              ),
            );
          }
        }
      }

      Logger.d('Total sources found: ${sources.length}', tag: _tag);
      print('[UAFlix] Total: ${sources.length} sources');
      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      print('[UAFlix] ERROR: $e');
      return [];
    }
  }

  Future<void> _parseIframeSource(
    String src,
    List<StreamSource> sources,
  ) async {
    try {
      final fullUrl = _absoluteUrl(src) ?? src;
      Logger.d('Parsing iframe: $fullUrl', tag: _tag);
      print('[UAFlix] Parsing iframe: $fullUrl');

      // UAFlix iframes require Referer from main site
      final html = await _client.get(
        fullUrl,
        headers: {'Referer': '$baseUrl/'},
      );
      final parsed = PlayerJsParser.parseFromHtml(html);
      print('[UAFlix] Iframe PlayerJS found ${parsed.length} sources');
      sources.addAll(parsed);
    } catch (e) {
      Logger.w('Failed to parse iframe: $src', tag: _tag);
    }
  }

  List<MediaItem> _parseSearchResults(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // UAFlix uses div.video-item for cards
    final cards = soup.findAll('div', class_: 'video-item');

    print('[UAFlix] Found ${cards.length} cards');

    for (final card in cards) {
      final item = _parseCard(card);
      if (item != null) items.add(item);
    }

    return items;
  }

  MediaItem? _parseCard(dynamic card) {
    try {
      // UAFlix: link is a.vi-img
      final link = card.find('a', class_: 'vi-img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      // UAFlix: title is in div.vi-title
      final titleEl =
          card.find('div', class_: 'vi-title') ??
          card.find('h3') ??
          card.find('h4');
      var title = titleEl?.text.trim() ?? link.attributes['alt'] ?? '';

      // Often title contains " / English Name", take first part
      if (title.contains(' / ')) {
        title = title.split(' / ').first.trim();
      }

      int? year;
      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(card.text);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }

      double? rating;
      final ratingEl =
          card.find('span', class_: 'rating') ??
          card.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim().replaceAll(',', '.'));
      }

      final type = _detectContentType(href);

      return MediaItem(
        id: mediaId,
        providerId: id,
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: type,
      );
    } catch (e) {
      return null;
    }
  }

  String _extractIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.isNotEmpty) {
      var path = uri.path;
      // Remove .html extension if present
      if (path.endsWith('.html')) {
        path = path.substring(0, path.length - 5);
      }
      // Remove trailing slash
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      return path;
    }
    return '';
  }

  ContentType _detectContentType(String url) {
    if (url.contains('/film/') || url.contains('/films/'))
      return ContentType.movie;
    if (url.contains('/serial/') || url.contains('/serials/'))
      return ContentType.series;
    if (url.contains('/cartoon/') || url.contains('/cartoons/'))
      return ContentType.cartoon;
    if (url.contains('/anime/')) return ContentType.anime;
    if (url.contains('/dorama/')) return ContentType.series;
    return ContentType.unknown;
  }

  MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    // Poster
    String? posterUrl;

    // 1. Try specific classes first
    final posterEl =
        soup.find('div', class_: 'fposter') ??
        soup.find('div', class_: 'full-poster') ??
        soup.find('div', class_: 'poster');

    if (posterEl != null) {
      final img = posterEl.find('img');
      posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];
    }

    // 2. Fallback: Robust finder but exclude logos
    if (posterUrl == null) {
      final images = soup.findAll('img');
      for (final img in images) {
        final src = img.attributes['src'] ?? img.attributes['data-src'];

        if (src != null &&
            (src.contains('/uploads/posts/') || src.contains('/posters/'))) {
          // Skip logos
          if (src.toLowerCase().contains('logo') ||
              src.toLowerCase().contains('netflix')) {
            continue;
          }
          posterUrl = src;
          break;
        }
      }
    }

    // Description
    final descEl =
        soup.find('div', class_: 'fdesc') ??
        soup.find('div', class_: 'full-desc') ??
        soup.find('div', class_: 'description');
    final description = descEl?.text.trim();

    // Info extraction
    int? year;
    List<String>? genres;
    List<String>? countries;
    String? director;
    List<String>? actors;
    Duration? duration;

    final infoBlocks =
        soup.findAll('li', class_: 'full-info__item') +
        soup.findAll('div', class_: 'finfo-item');

    for (final block in infoBlocks) {
      final label = block.find('span')?.text.toLowerCase() ?? '';
      final value = block.findAll('a').map((a) => a.text.trim()).toList();
      final textValue = block.text.replaceFirst(label, '').trim();

      if (label.contains('рік')) {
        year = int.tryParse(textValue);
      } else if (label.contains('жанр')) {
        genres = value.isNotEmpty ? value : [textValue];
      } else if (label.contains('країн')) {
        countries = value.isNotEmpty ? value : [textValue];
      } else if (label.contains('режис')) {
        director = value.isNotEmpty ? value.first : textValue;
      } else if (label.contains('актор')) {
        actors = value.isNotEmpty
            ? value
            : textValue.split(',').map((s) => s.trim()).toList();
      } else if (label.contains('трива')) {
        final durMatch = RegExp(r'(\d+)').firstMatch(textValue);
        if (durMatch != null) {
          duration = Duration(minutes: int.parse(durMatch.group(1)!));
        }
      }
    }

    final type = _detectContentType('/$mediaId');

    // Create MediaItem first
    final item = MediaItem(
      id: mediaId,
      providerId: id,
      title: title,
      posterUrl: _absoluteUrl(posterUrl),
      year: year,
      type: type,
    );

    return MediaDetails(
      item: item,
      fullDescription: description,
      genres: genres,
      countries: countries,
      director: director,
      actors: actors,
      duration: duration,
    );
  }

  String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }
}
