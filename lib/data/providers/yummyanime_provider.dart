import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../mixins/resolved_url_mixin.dart';

/// YummyAnime content provider
///
/// Ukrainian anime streaming site
class YummyAnimeProvider with ResolvedUrlMixin implements ContentProvider {
  static const String _tag = 'YummyAnime';

  final ApiClient _client;
  bool _isEnabled = true;

  YummyAnimeProvider(this._client);

  @override
  String get id => 'yummyanime';

  @override
  String get name => 'YummyAnime';

  @override
  String? get iconUrl => '$effectiveBaseUrl/favicon.ico';

  String _mirror = 'https://yummyanime.club';

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
  List<ContentType> get supportedTypes => [ContentType.anime];

  /// Headers that mimic a real browser to bypass Cloudflare
  Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
    'Accept-Encoding': 'gzip, deflate, br',
    'Referer': _mirror,
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-Fetch-User': '?1',
    'Cache-Control': 'max-age=0',
  };

  /// Make a GET request with browser headers
  Future<String> _get(String url) async {
    return await _client.get(url, headers: _browserHeaders);
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      // YummyAnime uses AJAX search
      final response = await _client.dio.get<String>(
        '$baseUrl/api/search',
        queryParameters: {'q': query},
        options: Options(
          headers: {..._browserHeaders, 'X-Requested-With': 'XMLHttpRequest'},
        ),
      );

      if (response.data != null && response.data!.trim().startsWith('{')) {
        final json = jsonDecode(response.data!);
        return _parseSearchJson(json);
      } else {
        throw FormatException('Response is not JSON');
      }
    } catch (e) {
      Logger.w('JSON Search failed, falling back to HTML', tag: _tag);

      // Fallback to HTML search
      try {
        final html = await _get(
          '$baseUrl/search?q=${Uri.encodeComponent(query)}',
        );
        return _parseSearchResults(html);
      } catch (_) {
        return [];
      }
    }
  }

  List<MediaItem> _parseSearchJson(dynamic json) {
    final items = <MediaItem>[];

    if (json is! List) return items;

    for (final item in json) {
      try {
        final id = item['slug']?.toString() ?? item['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        items.add(
          MediaItem(
            id: id,
            providerId: this.id,
            title: item['title']?.toString() ?? '',
            originalTitle: item['title_orig']?.toString(),
            posterUrl: _absoluteUrl(item['poster']?.toString()),
            year: int.tryParse(item['year']?.toString() ?? ''),
            rating: double.tryParse(item['rating']?.toString() ?? ''),
            type: ContentType.anime,
          ),
        );
      } catch (e) {
        Logger.w('Failed to parse search item', tag: _tag);
      }
    }

    return items;
  }

  @override
  Future<MediaDetails> getDetails(String id) async {
    try {
      final html = await _get('$baseUrl/anime/$id');
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

      // Get anime page
      final url = '$baseUrl/anime/$id';
      Logger.d('Fetching anime page: $url', tag: _tag);
      final html = await _get(url);
      final soup = BeautifulSoup(html);

      // Find episode data
      final episodeNum = episode ?? 1;
      final episodeData = await _getEpisodeData(soup, id, episodeNum);

      if (episodeData != null) {
        Logger.d('Found episode data for ep $episodeNum', tag: _tag);
        await _parseEpisodeStreams(episodeData, sources);
      } else {
        Logger.w('No episode data found for ep $episodeNum', tag: _tag);
      }

      Logger.i('Total streams found: ${sources.length}', tag: _tag);
      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getEpisodeData(
    BeautifulSoup soup,
    String animeId,
    int episode,
  ) async {
    try {
      // Find episode list
      final episodeItems = soup.findAll('li', class_: 'episode-item');

      for (final item in episodeItems) {
        final epNum = int.tryParse(item.attributes['data-episode'] ?? '');
        if (epNum == episode) {
          final dataId = item.attributes['data-id'];
          if (dataId != null) {
            // Fetch episode data via API
            final response = await _client.dio.get<String>(
              '$baseUrl/api/episode/$dataId',
              options: Options(
                headers: {
                  ..._browserHeaders,
                  'X-Requested-With': 'XMLHttpRequest',
                },
              ),
            );
            return jsonDecode(response.data ?? '{}');
          }
        }
      }

      // Fallback: try direct API call
      final response = await _client.dio.get<String>(
        '$baseUrl/api/anime/$animeId/episode/$episode',
        options: Options(
          headers: {..._browserHeaders, 'X-Requested-With': 'XMLHttpRequest'},
        ),
      );
      return jsonDecode(response.data ?? '{}');
    } catch (e) {
      Logger.w('Failed to get episode data: $e', tag: _tag);
      return null;
    }
  }

  Future<void> _parseEpisodeStreams(
    Map<String, dynamic> data,
    List<StreamSource> sources,
  ) async {
    // Parse players/sources from episode data
    final players = data['players'] as List? ?? [];

    for (final player in players) {
      final url = player['url']?.toString();
      final voiceover =
          player['name']?.toString() ?? player['voice']?.toString();
      final quality = player['quality']?.toString();

      if (url != null && url.isNotEmpty) {
        // Check if it's an embed URL that needs parsing
        if (url.contains('ashdi') ||
            url.contains('kodik') ||
            url.contains('aniboom')) {
          await _parseEmbedPlayer(url, voiceover, sources);
        } else {
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

    // Also check for direct video URLs
    final videoUrl = data['video']?.toString() ?? data['file']?.toString();
    if (videoUrl != null && videoUrl.isNotEmpty) {
      sources.add(
        StreamSource(
          url: videoUrl,
          quality: StreamQuality.unknown,
          type: videoUrl.contains('.m3u8') ? StreamType.hls : StreamType.direct,
        ),
      );
    }
  }

  Future<void> _parseEmbedPlayer(
    String embedUrl,
    String? voiceover,
    List<StreamSource> sources,
  ) async {
    Logger.d('_parseEmbedPlayer: $embedUrl (voice: $voiceover)', tag: _tag);
    try {
      var url = embedUrl;
      if (url.startsWith('//')) {
        url = 'https:$url';
      }

      final html = await _client.get(url);
      Logger.d('Embed HTML length: ${html.length}', tag: _tag);

      // 1. Check for specific players
      if (url.contains('ashdi')) {
        _parseAshdi(html, voiceover, sources);
      } else if (url.contains('kodik')) {
        // Kodik usually needs API or separate decoder, but sometimes exposes m3u8
        final match = RegExp(
          r'src=["\x27]([^"\x27]+\.m3u8[^"\x27]*)["\x27]',
        ).firstMatch(html);
        if (match != null) {
          final m3u8 = match.group(1);
          if (m3u8 != null && !m3u8.contains('error')) {
            sources.add(
              StreamSource(
                url: m3u8,
                quality: StreamQuality.unknown,
                voiceover: voiceover,
                type: StreamType.hls,
              ),
            );
          }
        }
      }

      // 2. Generic fallback patterns
      final patterns = [
        RegExp(r'file["\s]*:["\s]*["\x27](https?://[^"\x27]+)["\x27]'),
        RegExp(
          r'src["\s]*:["\s]*["\x27](https?://[^"\x27]+\.m3u8[^"\x27]*)["\x27]',
        ),
        RegExp(r'"hls"["\s]*:["\s]*["\x27](https?://[^"\x27]+)["\x27]'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final streamUrl = match.group(1)!;
          Logger.d('Found extracted stream: $streamUrl', tag: _tag);

          if (!streamUrl.contains('.mp4') && !streamUrl.contains('.m3u8')) {
            Logger.w('Ignored non-video URL: $streamUrl', tag: _tag);
            continue;
          }

          sources.add(
            StreamSource(
              url: streamUrl,
              quality: StreamQuality.unknown,
              voiceover: voiceover,
              type: streamUrl.contains('.m3u8')
                  ? StreamType.hls
                  : StreamType.direct,
            ),
          );
        }
      }
    } catch (e) {
      Logger.w('Failed to parse embed player: $e', tag: _tag);
    }
  }

  void _parseAshdi(String html, String? voiceover, List<StreamSource> sources) {
    final match = RegExp(
      r'file\s*:\s*["\x27](https?://[^"\x27]+)["\x27]',
    ).firstMatch(html);
    if (match != null) {
      final url = match.group(1)!;
      Logger.d('Ashdi stream: $url', tag: _tag);
      sources.add(
        StreamSource(
          url: url,
          quality: StreamQuality.unknown,
          voiceover: voiceover,
          type: StreamType.hls,
        ),
      );
    }
  }

  StreamQuality _parseQuality(String? quality) {
    if (quality == null) return StreamQuality.unknown;
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
      default:
        return StreamQuality.unknown;
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final html = await _get('$baseUrl/anime?sort=popular&page=$page');
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      final html = await _get('$baseUrl/anime?sort=latest&page=$page');
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
      'Комедія',
      'Романтика',
      'Драма',
      'Фентезі',
      'Пригоди',
      'Школа',
      'Надприродне',
      'Меха',
      'Сьонен',
      'Сьодзьо',
      'Ісекай',
      'Спорт',
      'Психологія',
      'Жахи',
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
      final html = await _get('$baseUrl/anime?genre=$genreSlug&page=$page');
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

  String _categoryToSlug(String category) {
    final map = {
      'Бойовик': 'action',
      'Комедія': 'comedy',
      'Романтика': 'romance',
      'Драма': 'drama',
      'Фентезі': 'fantasy',
      'Пригоди': 'adventure',
      'Школа': 'school',
      'Надприродне': 'supernatural',
      'Меха': 'mecha',
      'Сьонен': 'shounen',
      'Сьодзьо': 'shoujo',
      'Ісекай': 'isekai',
      'Спорт': 'sports',
      'Психологія': 'psychological',
      'Жахи': 'horror',
    };
    return map[category] ?? category.toLowerCase();
  }

  List<MediaItem> _parseSearchResults(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // Anime cards
    final cards = soup.findAll('div', class_: 'anime-card');
    if (cards.isEmpty) {
      // Try alternative selectors
      final altCards = soup.findAll('article', class_: 'anime-item');
      for (final card in altCards) {
        final item = _parseCard(card);
        if (item != null) items.add(item);
      }
    }

    for (final card in cards) {
      final item = _parseCard(card);
      if (item != null) items.add(item);
    }

    return items;
  }

  MediaItem? _parseCard(dynamic card) {
    try {
      final link = card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      final titleEl =
          card.find('div', class_: 'anime-title') ??
          card.find('h3') ??
          card.find('span', class_: 'title');
      final title = titleEl?.text.trim() ?? '';

      int? year;
      final infoEl = card.find('div', class_: 'anime-info');
      if (infoEl != null) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl = card.find('span', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
      }

      // Parse genres
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'anime-genre') ??
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

      return MediaItem(
        id: mediaId,
        providerId: id,
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: ContentType.anime,
        genres: genres,
      );
    } catch (e) {
      return null;
    }
  }

  String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }

  String _extractIdFromUrl(String url) {
    // Format: https://yummyanime.tv/anime/some-anime-slug
    final match = RegExp(r'/anime/([^/?#]+)').firstMatch(url);
    if (match != null) {
      return match.group(1) ?? '';
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.length >= 2) {
      return uri.pathSegments.last;
    }
    return '';
  }

  MediaDetails _parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1', class_: 'anime-title');
    final title = titleEl?.text.trim() ?? '';

    String? originalTitle;
    final origEl = soup.find('div', class_: 'original-title');
    if (origEl != null) {
      originalTitle = origEl.text.trim();
    }

    // Poster
    final posterEl = soup.find('div', class_: 'anime-poster');
    final posterUrl = posterEl?.find('img')?.attributes['src'];

    // Info block
    final infoBlock = soup.find('div', class_: 'anime-info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    String? status;

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('div', class_: 'info-item')) {
        final label =
            row.find('span', class_: 'label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'value');

        if (label.contains('студ')) {
          director = value?.text.trim();
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік')) {
          year = int.tryParse(value?.text.trim() ?? '');
        } else if (label.contains('стату')) {
          status = value?.text.trim();
        }
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'anime-description');
    final description = descEl?.text.trim();

    // Rating
    double? rating;
    final ratingEl = soup.find('div', class_: 'anime-rating');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    // Episodes/Seasons
    List<Season>? seasons;
    final episodesList = soup.find('div', class_: 'episodes-list');
    if (episodesList != null) {
      seasons = _parseSeasons(soup);
    }

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: id,
        title: title,
        originalTitle: originalTitle,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: ContentType.anime,
        description: status,
      ),
      fullDescription: description,
      genres: genres,
      countries: countries,
      director: director,
      actors: actors,
      seasons: seasons,
    );
  }

  List<Season> _parseSeasons(BeautifulSoup soup) {
    final seasons = <Season>[];

    // YummyAnime usually has single season with episodes
    final episodes = <Episode>[];
    final episodeItems = soup.findAll('li', class_: 'episode-item');

    for (final item in episodeItems) {
      final epNum =
          int.tryParse(item.attributes['data-episode'] ?? '') ??
          episodes.length + 1;

      final epTitle =
          item.find('span', class_: 'episode-title')?.text.trim() ??
          'Серія $epNum';

      episodes.add(Episode(number: epNum, title: epTitle));
    }

    if (episodes.isNotEmpty) {
      seasons.add(Season(number: 1, episodes: episodes));
    }

    return seasons;
  }
}
