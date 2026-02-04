import 'package:beautiful_soup_dart/beautiful_soup.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../mixins/resolved_url_mixin.dart';
import '../parsers/playerjs_parser.dart';

class UaserialsProvider with ResolvedUrlMixin implements ContentProvider {
  static const String _tag = 'UaSerials';

  final ApiClient _client;
  bool _isEnabled = true;

  UaserialsProvider(this._client);

  @override
  String get id => 'uaserials';

  @override
  String get name => 'UaSerials';

  @override
  String get baseUrl => 'https://uaserials.my';

  @override
  String? get iconUrl =>
      '$effectiveBaseUrl/templates/uaserials2020/images/favicon.png';

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
    Logger.d('search: query="$query", page=$page', tag: _tag);
    try {
      // DLE standard search
      final url =
          '$effectiveBaseUrl/index.php?do=search&subaction=search&story=${Uri.encodeComponent(query)}&search_start=$page';
      Logger.d('Search URL: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('Search response length: ${html.length}', tag: _tag);
      final items = _parseList(html);
      Logger.d('Search found ${items.length} items', tag: _tag);
      return items;
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    Logger.d('getPopular: page=$page', tag: _tag);
    try {
      final url = page == 1
          ? effectiveBaseUrl
          : '$effectiveBaseUrl/page/$page/';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('Response length: ${html.length}', tag: _tag);
      final items = _parseList(html);
      Logger.d('Parsed ${items.length} items', tag: _tag);
      return items;
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
      final url = '$effectiveBaseUrl/$category/page/$page/';
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
      final url = '$effectiveBaseUrl/$id.html';
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
    Logger.d('getStreams: id=$id, season=$season, episode=$episode', tag: _tag);
    try {
      final url = '$effectiveBaseUrl/$id.html';
      Logger.d('Fetching page: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('HTML length: ${html.length}', tag: _tag);

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
              : (src.startsWith('/') ? '$effectiveBaseUrl$src' : src);

          Logger.d('Processing iframe: $absSrc', tag: _tag);

          // Try parsing the iframe content for PlayerJS
          try {
            final frameHtml = await _client.get(
              absSrc,
              headers: {'Referer': effectiveBaseUrl},
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

      Logger.i('Total streams: ${sources.length}', tag: _tag);
      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  List<MediaItem> _parseList(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // UaSerials uses div.short-item for cards
    final cardDivs = soup.findAll('div', class_: 'short-item');

    if (cardDivs.isNotEmpty) {
      Logger.d('Found ${cardDivs.length} short-item cards', tag: _tag);
      for (final cardDiv in cardDivs) {
        final item = _parseCardDiv(cardDiv);
        if (item != null) items.add(item);
      }
    } else {
      // Fallback: try a.short-img directly
      Logger.d('No div.short-item found, checking a.short-img', tag: _tag);
      final links = soup.findAll('a', class_: 'short-img');
      for (final link in links) {
        final item = _parseCard(link);
        if (item != null) items.add(item);
      }
    }

    Logger.d('Parsed ${items.length} items', tag: _tag);

    if (items.isEmpty) {
      // Debug: print first 500 chars of HTML body to see what's wrong
      final body =
          soup.body?.text.substring(0, 500).replaceAll('\n', ' ') ?? 'No body';
      Logger.d('Parsed 0 items. HTML preview: $body', tag: _tag);
    }

    return items;
  }

  /// Parse a card from div.short-item structure
  MediaItem? _parseCardDiv(Bs4Element cardDiv) {
    try {
      final link = cardDiv.find('a', class_: 'short-img');
      if (link == null) return null;

      final href = link.attributes['href'];
      if (href == null) return null;

      final id = _extractId(href);
      if (id.isEmpty) return null;

      // Get poster from img - check data-src first for lazy loading
      final img = link.find('img');
      final rawPosterUrl =
          img?.attributes['data-src'] ?? img?.attributes['src'];
      // Convert relative URL to absolute
      final posterUrl = _absoluteUrl(rawPosterUrl);

      // Get title from div.th-title
      final titleEl = cardDiv.find('div', class_: 'th-title');
      final title =
          titleEl?.text.trim() ?? img?.attributes['alt']?.trim() ?? '';

      if (title.isEmpty) return null;

      // Get original title from div.th-title-oname
      final oTitleEl = cardDiv.find('div', class_: 'th-title-oname');
      final originalTitle = oTitleEl?.text.trim();

      // UaSerials doesn't show year in list view - only on details page
      // We can't get year from list, so it remains null
      int? year;

      // Try to extract rating
      double? rating;
      final ratingEl =
          cardDiv.find('span', class_: 'rating') ??
          cardDiv.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(
          ratingEl.text
              .trim()
              .replaceAll(',', '.')
              .replaceAll(RegExp(r'[^\d.]'), ''),
        );
      }

      // Determine type from URL
      ContentType type = ContentType.series; // Default
      if (href.contains('/filmss/') || href.contains('/fcartoon/')) {
        type = ContentType.movie;
      }
      if (href.contains('/cartoons/')) type = ContentType.cartoon;
      if (href.contains('/anime/')) type = ContentType.anime;

      return MediaItem(
        id: id,
        title: title,
        originalTitle: originalTitle,
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        type: type,
        providerId: 'uaserials',
      );
    } catch (e, stack) {
      Logger.w('Failed to parse card div', tag: _tag);
      Logger.d('Error: $e\n$stack', tag: _tag);
      return null;
    }
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

      // Try to extract year from title or nearby elements
      int? year;
      final parent = link.parent;
      if (parent != null) {
        // Look for year in parent container
        final yearEl =
            parent.find('span', class_: 'year') ??
            parent.find('div', class_: 'year') ??
            parent.find('span', class_: 'serial-year');
        if (yearEl != null) {
          year = int.tryParse(
            yearEl.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
          );
        }
        // Try to find year in text like (2024) or 2024
        if (year == null) {
          final yearMatch = RegExp(
            r'\b(19\d{2}|20\d{2})\b',
          ).firstMatch(parent.text);
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(1) ?? '');
          }
        }
      }

      // Fallback: extract year from URL (common in UaSerials)
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})\.html').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      // Try to extract rating
      double? rating;
      if (parent != null) {
        final ratingEl =
            parent.find('span', class_: 'rating') ??
            parent.find('div', class_: 'rating') ??
            parent.find('span', class_: 'imdb') ??
            parent.find('span', class_: 'serial-rating');
        if (ratingEl != null) {
          rating = double.tryParse(
            ratingEl.text
                .trim()
                .replaceAll(',', '.')
                .replaceAll(RegExp(r'[^\d.]'), ''),
          );
        }
      }

      // Determine type
      ContentType type = ContentType.series; // Default
      if (href.contains('/filmss/') || href.contains('movies')) {
        type = ContentType.movie;
      }
      if (href.contains('cartoons')) type = ContentType.cartoon;

      // Try to extract genres
      List<String>? genres;
      if (parent != null) {
        final genreEl =
            parent.find('div', class_: 'serial-genre') ??
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
      }

      // Try to extract country
      String? country;
      if (parent != null) {
        final countryEl =
            parent.find('div', class_: 'serial-country') ??
            parent.find('span', class_: 'country');
        if (countryEl != null) {
          country = countryEl.text.trim().split(',').first.trim();
        }
      }

      return MediaItem(
        id: id,
        providerId: this.id,
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
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

  MediaDetails _parseDetails(String html, String id) {
    final soup = BeautifulSoup(html);

    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    String? description;
    // UaSerials uses 'ftext full-text' or 'full-text' class for description
    final descEl =
        soup.find('div', class_: 'full-text') ??
        soup.find('div', class_: 'ftext') ??
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
    if (url.startsWith('/')) return '$effectiveBaseUrl$url';
    return '$effectiveBaseUrl/$url';
  }
}
