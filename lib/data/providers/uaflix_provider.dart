import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:flutter/foundation.dart'; // Added for compute

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../mixins/resolved_url_mixin.dart';
import '../parsers/playerjs_parser.dart';

/// UAFlix content provider
///
/// Ukrainian streaming site with Netflix content dubbed in Ukrainian
class UaflixProvider with ResolvedUrlMixin implements ContentProvider {
  static const String _tag = 'UAFlix';

  final ApiClient _client;
  bool _isEnabled = true;

  UaflixProvider(this._client);

  @override
  String get id => 'uaflix';

  @override
  String get name => 'UAFlix';

  @override
  String? get iconUrl => '$effectiveBaseUrl/favicon.ico';

  @override
  String get baseUrl => 'https://uafix.net';

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
          '$effectiveBaseUrl/index.php?do=search&subaction=search'
          '&story=${Uri.encodeComponent(query)}'
          '&search_start=$page';

      Logger.d('Search: $url', tag: _tag);
      final html = await _client.get(url);
      return compute(_parseSearchResultsStatic, html);
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

      final url = '$effectiveBaseUrl/$category/page/$page/';
      Logger.d('Get popular: $url', tag: _tag);
      final html = await _client.get(url);
      return compute(_parseSearchResultsStatic, html);
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

      final url = '$effectiveBaseUrl/$category/page/$page/';
      Logger.d('Get new: $url', tag: _tag);
      final html = await _client.get(url);
      return compute(_parseSearchResultsStatic, html);
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
      final url = '$effectiveBaseUrl/$category/page/$page/';
      Logger.d('Get by category: $url', tag: _tag);
      final html = await _client.get(url);
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

  @override
  Future<MediaDetails> getDetails(String mediaId) async {
    try {
      // UAFlix URLs end with / not .html
      final url = '$effectiveBaseUrl/$mediaId/';
      Logger.d('Get details: $url', tag: _tag);
      final html = await _client.get(url);
      return compute(_parseDetailsStatic, ParseDetailsArgs(html, mediaId));
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
    try {
      // UAFlix URLs end with / not .html
      final url = '$effectiveBaseUrl/$mediaId/';
      Logger.d('Fetching: $url', tag: _tag);
      final html = await _client.get(url);
      Logger.d('HTML length: ${html.length}', tag: _tag);

      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // Try iframes first
      final iframes = soup.findAll('iframe');
      Logger.d('Found ${iframes.length} iframes', tag: _tag);
      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
        if (src != null && src.isNotEmpty) {
          await _parseIframeSource(src, sources);
        }
      }

      // Try PlayerJS parsing
      if (sources.isEmpty) {
        Logger.d('Trying PlayerJS parsing...', tag: _tag);
        // Use compute for PlayerJS parsing
        final parsed = await PlayerJsParser.parseFromHtmlCompute(html);
        Logger.d('PlayerJS found ${parsed.length} sources', tag: _tag);
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
                url: _absoluteUrlStatic(src) ?? src,
                quality: StreamQuality.unknown,
                sourceName: 'default',
              ),
            );
          }
        }
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

  Future<void> _parseIframeSource(
    String src,
    List<StreamSource> sources,
  ) async {
    try {
      final fullUrl = _absoluteUrlStatic(src) ?? src;
      Logger.d('Parsing iframe: $fullUrl', tag: _tag);

      // UAFlix iframes require Referer from main site
      final html = await _client.get(
        fullUrl,
        headers: {'Referer': '$effectiveBaseUrl/'},
      );
      // Use compute for iframe parsing too
      final parsed = await PlayerJsParser.parseFromHtmlCompute(html);
      Logger.d('Iframe PlayerJS found ${parsed.length} sources', tag: _tag);
      sources.addAll(parsed);
    } catch (e) {
      Logger.w('Failed to parse iframe: $src', tag: _tag);
    }
  }

  // Static parsing methods for Compute (Isolate)

  static List<MediaItem> _parseSearchResultsStatic(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // UAFlix search results use a.sres-wrap (different from list pages)
    final searchCards = soup.findAll('a', class_: 'sres-wrap');

    if (searchCards.isNotEmpty) {
      // Parse search-specific format
      for (final card in searchCards) {
        final item = _parseSearchCardStatic(card);
        if (item != null) items.add(item);
      }
    } else {
      // Fallback to list page format (div.video-item)
      final listCards = soup.findAll('div', class_: 'video-item');
      for (final card in listCards) {
        final item = _parseCardStatic(card);
        if (item != null) items.add(item);
      }
    }

    return items;
  }

  /// Parse search result card (a.sres-wrap)
  static MediaItem? _parseSearchCardStatic(dynamic card) {
    try {
      final href = card.attributes['href'] ?? '';
      if (href.isEmpty) return null;

      final mediaId = _extractIdFromUrlStatic(href);
      if (mediaId.isEmpty) return null;

      // Image is in div.sres-img > img
      final imgDiv = card.find('div', class_: 'sres-img');
      final img = imgDiv?.find('img');
      final posterUrl = img?.attributes['src'];
      final title = img?.attributes['alt']?.trim() ?? '';

      if (title.isEmpty) return null;

      // Extract year from title (format: "Title (Year)" or "Title / English Title")
      int? year;
      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }

      // Fallback: try to find year in URL
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})/?$').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      // Clean title - remove English part after /
      var cleanTitle = title;
      if (cleanTitle.contains(' / ')) {
        cleanTitle = cleanTitle.split(' / ').first.trim();
      }

      // Determine content type from URL
      ContentType type = ContentType.movie;
      if (href.contains('/serials/')) {
        type = ContentType.series;
      } else if (href.contains('/anime/')) {
        type = ContentType.anime;
      } else if (href.contains('/cartoons/') || href.contains('/mult')) {
        type = ContentType.cartoon;
      }

      return MediaItem(
        id: mediaId,
        title: cleanTitle,
        originalTitle: title.contains(' / ')
            ? title.split(' / ').last.trim()
            : null,
        posterUrl: _absoluteUrlStatic(posterUrl),
        year: year,
        type: type,
        providerId: 'uaflix',
      );
    } catch (e) {
      return null;
    }
  }

  static MediaItem? _parseCardStatic(dynamic card) {
    try {
      // UAFlix: link is a.vi-img
      final link = card.find('a', class_: 'vi-img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrlStatic(href);
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

      // Fallback: search in card text matching 19xx or 20xx
      if (year == null) {
        final yearFallback = RegExp(
          r'\b(19\d{2}|20\d{2})\b',
        ).firstMatch(card.text);
        if (yearFallback != null) {
          year = int.tryParse(yearFallback.group(1) ?? '');
        }
      }

      // Fallback: extract year from URL
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})/?$').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl =
          card.find('span', class_: 'rating') ??
          card.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim().replaceAll(',', '.'));
      }

      // Parse genres
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'vi-genre') ??
          card.find('span', class_: 'genre') ??
          card.find('div', class_: 'genres');
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
          card.find('div', class_: 'vi-country') ??
          card.find('span', class_: 'country');
      if (countryEl != null) {
        country = countryEl.text.trim().split(',').first.trim();
      }

      final type = _detectContentTypeStatic(href);

      return MediaItem(
        id: mediaId,
        providerId: 'uaflix', // Use hardcoded id for static context
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

  static String _extractIdFromUrlStatic(String url) {
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

  static ContentType _detectContentTypeStatic(String url) {
    if (url.contains('/film/') || url.contains('/films/')) {
      return ContentType.movie;
    }
    if (url.contains('/serial/') || url.contains('/serials/')) {
      return ContentType.series;
    }
    if (url.contains('/cartoon/') || url.contains('/cartoons/')) {
      return ContentType.cartoon;
    }
    if (url.contains('/anime/')) {
      return ContentType.anime;
    }
    if (url.contains('/dorama/')) {
      return ContentType.series;
    }
    return ContentType.unknown;
  }

  static MediaDetails _parseDetailsStatic(ParseDetailsArgs args) {
    return _parseDetails(args.html, args.mediaId);
  }

  static MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    // Poster - improved detection with lazy loading support
    String? posterUrl;

    // 1. Try specific classes first (fposter2, fposter3 are common on UAFlix)
    final posterEl =
        soup.find('div', class_: 'fposter2') ??
        soup.find('div', class_: 'fposter3') ??
        soup.find('div', class_: 'fposter') ??
        soup.find('div', class_: 'full-poster') ??
        soup.find('div', class_: 'poster') ??
        soup.find('div', class_: 'fimg');

    if (posterEl != null) {
      final img = posterEl.find('img');
      // IMPORTANT: Check data-src FIRST for lazy-loaded images
      final dataSrc = img?.attributes['data-src'];
      final src = img?.attributes['src'];

      // Prefer data-src (real image) over src (which may be lazy placeholder)
      String? candidate = dataSrc ?? src;

      // Validate poster URL - skip if it's a logo/placeholder/lazy
      if (candidate != null &&
          !candidate.toLowerCase().contains('logo') &&
          !candidate.toLowerCase().contains('netflix') &&
          !candidate.toLowerCase().contains('placeholder') &&
          !candidate.toLowerCase().contains('default') &&
          !candidate.toLowerCase().contains('lazy-poster') &&
          !candidate.toLowerCase().contains('lazy.')) {
        posterUrl = candidate;
      }
    }

    // 2. Fallback: Search all images but exclude logos/placeholders
    if (posterUrl == null) {
      final images = soup.findAll('img');
      for (final img in images) {
        // IMPORTANT: Check data-src FIRST for lazy-loaded images
        final dataSrc = img.attributes['data-src'];
        final src = img.attributes['src'];
        final candidate = dataSrc ?? src;
        final alt = (img.attributes['alt'] ?? '').toLowerCase();

        if (candidate == null) continue;

        // Skip logos, placeholders, and lazy placeholders
        if (candidate.toLowerCase().contains('logo') ||
            candidate.toLowerCase().contains('netflix') ||
            candidate.toLowerCase().contains('placeholder') ||
            candidate.toLowerCase().contains('default') ||
            candidate.toLowerCase().contains('icon') ||
            candidate.toLowerCase().contains('lazy-poster') ||
            candidate.toLowerCase().contains('lazy.') ||
            alt.contains('logo') ||
            alt.contains('netflix')) {
          continue;
        }

        // Prefer posters from known paths
        if (candidate.contains('/uploads/posts/') ||
            candidate.contains('/posters/') ||
            candidate.contains('/covers/') ||
            candidate.contains('/thumbs/')) {
          posterUrl = candidate;
          break;
        }
      }

      // Last resort: first large-ish image
      if (posterUrl == null) {
        for (final img in images) {
          final dataSrc = img.attributes['data-src'];
          final src = img.attributes['src'];
          final candidate = dataSrc ?? src;
          if (candidate != null &&
              !candidate.toLowerCase().contains('logo') &&
              !candidate.toLowerCase().contains('netflix') &&
              !candidate.toLowerCase().contains('icon') &&
              !candidate.toLowerCase().contains('lazy') &&
              !candidate.endsWith('.ico') &&
              !candidate.endsWith('.svg')) {
            posterUrl = candidate;
            break;
          }
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

    final type = _detectContentTypeStatic('/$mediaId');

    // Create MediaItem first
    final item = MediaItem(
      id: mediaId,
      providerId: 'uaflix', // Use hardcoded id for static context
      title: title,
      posterUrl: _absoluteUrlStatic(posterUrl),
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

  static String? _absoluteUrlStatic(String? url) {
    const baseUrl = 'https://uaflix.net'; // Hardcoded for static context
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }
}

/// Arguments wrapper for parseDetails
class ParseDetailsArgs {
  final String html;
  final String mediaId;

  ParseDetailsArgs(this.html, this.mediaId);
}
