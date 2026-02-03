import 'package:beautiful_soup_dart/beautiful_soup.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../parsers/playerjs_parser.dart';

class UaserialsProvider implements ContentProvider {
  static const String _tag = 'UaSerials';

  final ApiClient _client;
  bool _isEnabled = true;

  UaserialsProvider(this._client);

  @override
  String get id => 'uaserials';

  @override
  String get name => 'UaSerials';

  @override
  String get baseUrl => 'https://uaserials.pro';

  @override
  String? get iconUrl => '$baseUrl/templates/uaserials2020/images/favicon.png';

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  @override
  List<ContentType> get supportedTypes => [
    ContentType.series,
    ContentType.anime,
    ContentType.cartoon,
    ContentType.movie, // They have films section too
  ];

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      // DLE standard search
      final url =
          '$baseUrl/index.php?do=search&subaction=search&story=${Uri.encodeComponent(query)}&search_start=$page';
      Logger.d('Search: $url', tag: _tag);
      final html = await _client.get(url);
      return _parseList(html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final url = page == 1 ? baseUrl : '$baseUrl/page/$page/';
      final html = await _client.get(url);
      return _parseList(html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    return getPopular(type: type, page: page);
  }

  @override
  Future<List<String>> getCategories() async {
    return ['seriess', 'filmss', 'cartoons', 'anime'];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      final url = '$baseUrl/$category/page/$page/';
      final html = await _client.get(url);
      return _parseList(html);
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
  Future<MediaDetails> getDetails(String id) async {
    try {
      final url = '$baseUrl/$id.html';
      Logger.d('Get details: $url', tag: _tag);
      final html = await _client.get(url);
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
    try {
      final url = '$baseUrl/$id.html';
      final html = await _client.get(url);

      final sources = <StreamSource>[];
      final soup = BeautifulSoup(html);

      // Look for iframes
      final iframes = soup.findAll('iframe');
      Logger.d('Found ${iframes.length} iframes for $id', tag: _tag);

      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
        if (src != null) {
          // Skip YouTube/Vimeo trailers
          if (src.contains('youtube.com') ||
              src.contains('youtu.be') ||
              src.contains('vimeo.com')) {
            Logger.d('Skipping trailer iframe: $src', tag: _tag);
            continue;
          }

          // If relative, make absolute
          final absSrc = src.startsWith('//')
              ? 'https:$src'
              : (src.startsWith('/') ? '$baseUrl$src' : src);

          Logger.d('Processing iframe: $absSrc', tag: _tag);

          // Try parsing the iframe content for PlayerJS
          try {
            final frameHtml = await _client.get(
              absSrc,
              headers: {'Referer': baseUrl},
            );
            final parsed = PlayerJsParser.parseFromHtml(frameHtml);
            if (parsed.isNotEmpty) {
              Logger.d('Found ${parsed.length} sources in iframe', tag: _tag);
              sources.addAll(parsed);
            } else {
              Logger.d('No PlayerJS sources in iframe', tag: _tag);
            }
          } catch (e) {
            Logger.w('Failed to parse iframe: $absSrc');
          }
        }
      }

      // Also check main page for PlayerJS
      final pageSources = PlayerJsParser.parseFromHtml(html);
      Logger.d('Found ${pageSources.length} sources on main page', tag: _tag);
      sources.addAll(pageSources);

      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  List<MediaItem> _parseList(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // Try multiple selectors for cards
    // 1. a.short-img (standard)
    var links = soup.findAll('a', class_: 'short-img');

    // 2. div.short-item a (fallback)
    if (links.isEmpty) {
      Logger.d('No a.short-img found, checking div.short-item', tag: _tag);
      final divs = soup.findAll('div', class_: 'short-item');
      for (final div in divs) {
        final link = div.find('a');
        if (link != null) links.add(link);
      }
    }

    Logger.d('Found ${links.length} potential cards', tag: _tag);

    for (final link in links) {
      final item = _parseCard(link);
      if (item != null) items.add(item);
    }

    if (items.isEmpty) {
      // Debug: print first 500 chars of HTML body to see what's wrong
      final body =
          soup.body?.text.substring(0, 500).replaceAll('\n', ' ') ?? 'No body';
      Logger.d('Parsed 0 items. HTML preview: $body', tag: _tag);
    }

    return items;
  }

  MediaItem? _parseCard(Bs4Element link) {
    try {
      final href = link.attributes['href'];
      if (href == null) return null;

      final id = _extractId(href);
      if (id.isEmpty) return null;

      // Robust poster finder
      String? posterUrl;
      final images = link.findAll('img');
      for (final img in images) {
        final src = img.attributes['src'];
        final dataSrc = img.attributes['data-src'];

        if (src != null &&
            (src.contains('/posters/') || src.contains('/uploads/'))) {
          posterUrl = src;
          break;
        }
        if (dataSrc != null &&
            (dataSrc.contains('/posters/') || dataSrc.contains('/uploads/'))) {
          posterUrl = dataSrc;
          break;
        }
      }
      // Fallback to first image
      if (posterUrl == null && images.isNotEmpty) {
        posterUrl =
            images.first.attributes['src'] ??
            images.first.attributes['data-src'];
      }

      final title = images.isNotEmpty
          ? (images.first.attributes['alt']?.trim() ??
                link.attributes['title']?.trim() ??
                '')
          : link.text.trim();

      // Determine type
      ContentType type = ContentType.series; // Default
      if (href.contains('/filmss/') || href.contains('movies'))
        type = ContentType.movie;
      if (href.contains('cartoons')) type = ContentType.cartoon;

      return MediaItem(
        id: id,
        providerId: this.id,
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        type: type,
      );
    } catch (e) {
      return null;
    }
  }

  MediaDetails _parseDetails(String html, String id) {
    final soup = BeautifulSoup(html);

    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    String? description;
    final descEl =
        soup.find('div', class_: 'full-desc') ??
        soup.find('div', class_: 'fdesc');
    description = descEl?.text.trim();

    // Poster extraction
    // Using robust finding: /posters/ or /uploads/
    String? posterUrl;
    final images = soup.findAll('img');
    for (final img in images) {
      final src = img.attributes['src'];
      final dataSrc = img.attributes['data-src'];

      if (src != null &&
          (src.contains('/posters/') || src.contains('/uploads/'))) {
        posterUrl = src;
        break;
      }
      if (dataSrc != null &&
          (dataSrc.contains('/posters/') || dataSrc.contains('/uploads/'))) {
        posterUrl = dataSrc;
        break;
      }
    }

    // Fallback: first image in .full-img
    if (posterUrl == null) {
      final posterDiv = soup.find('div', class_: 'full-img');
      posterUrl = posterDiv?.find('img')?.attributes['src'];
    }

    // Info parsing
    int? year;
    List<String>? genres;
    double? rating;

    final infoList = soup.findAll('ul', class_: 'full-list');
    for (final list in infoList) {
      for (final li in list.findAll('li')) {
        final text = li.text.toLowerCase();
        if (text.contains('рік')) {
          final match = RegExp(r'\d{4}').firstMatch(text);
          if (match != null) year = int.tryParse(match.group(0)!);
        }
      }
    }

    final item = MediaItem(
      id: id,
      providerId: this.id,
      title: title,
      posterUrl: _absoluteUrl(posterUrl),
      year: year,
      rating: rating,
      type: ContentType.series, // Refine later if needed
    );

    return MediaDetails(
      item: item,
      fullDescription: description,
      genres: genres,
    );
  }

  String _extractId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';

    var path = uri.path;
    if (path.endsWith('.html')) {
      path = path.substring(0, path.length - 5);
    }
    if (path.startsWith('/')) path = path.substring(1);

    return path;
  }

  String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }
}
