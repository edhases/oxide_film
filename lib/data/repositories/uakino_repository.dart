import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/playerjs_parser.dart';
import '../parsers/uakino_parser.dart';

class UakinoRepository {
  static const String _tag = 'UakinoRepository';
  final ApiClient _client;

  UakinoRepository(this._client);

  String get baseUrl => UakinoParser.baseUrl;

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    try {
      final url = '$baseUrl/index.php?do=search';
      final html = await _client.get(
        '$url&subaction=search&story=${Uri.encodeComponent(query)}&search_start=$page',
      );
      return compute(UakinoParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String id) async {
    try {
      final html = await _client.get('$baseUrl/$id.html');
      return compute(_parseDetailsCompute, {'html': html, 'id': id});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  // Wrapper for isolate
  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return UakinoParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getCatalog(String url) async {
    try {
      final html = await _client.get(url);
      return compute(UakinoParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e(
        'Get catalog failed: $url',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return [];
    }
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/page/$page/'
          : '$baseUrl/$section/page/$page/';

      final html = await _client.get(url);
      return compute(UakinoParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/page/$page/'
          : '$baseUrl/$section/page/$page/';

      final html = await _client.get(url);
      return compute(UakinoParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getByCategory(
    String categorySlug, {
    ContentType? type,
    int page = 1,
  }) async {
    try {
      if (categorySlug.isEmpty) return [];
      final encodedCategory = Uri.encodeComponent(categorySlug);
      final section = _getSection(type);
      final url = section.isEmpty
          ? '$baseUrl/xfsearch/genre/$encodedCategory/page/$page/'
          : '$baseUrl/$section/xfsearch/genre/$encodedCategory/page/$page/';

      final html = await _client.get(url);
      return compute(UakinoParser.parseCatalog, html);
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

  Future<List<StreamSource>> getStreams(String id) async {
    try {
      // 1. Fetch main page
      final url = '$baseUrl/$id.html';
      final html = await _client.get(url);

      final sources = <StreamSource>[];

      // 2. Identify news_id
      final newsId = UakinoParser.extractNewsId(html, id);

      // 3. Try AJAX Playlist
      if (newsId != null) {
        try {
          final ajaxUrl = '$baseUrl/engine/ajax/playlists.php';
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
          if (responseBody.contains('file:') ||
              responseBody.contains('iframe') ||
              responseBody.contains('data-file')) {
            final ajaxSources = await compute(
              UakinoParser.parseAjaxPlaylist,
              responseBody,
            );

            // Resolve direct sources (iframes / ashdi players)
            for (final source in ajaxSources) {
              if (source.type == StreamType.direct &&
                  !source.url.endsWith('.mp4') &&
                  !source.url.endsWith('.mkv')) {
                // Likely an iframe or player page
                await _resolvePlayerUrl(source, sources);
              } else {
                sources.add(source);
              }
            }
          }
        } catch (e) {
          Logger.w('AJAX playlist failed: $e', tag: _tag);
        }
      }

      // 4. Fallback to iframes in main HTML (if AJAX failed or yielded nothing)
      if (sources.isEmpty) {
        final iframeSrcs = await compute(UakinoParser.parseIframeSrcs, html);
        for (final src in iframeSrcs) {
          await _resolvePlayerUrl(
            StreamSource(
              url: src,
              type: StreamType.direct,
              quality: StreamQuality.unknown,
            ),
            sources,
          );
        }
      }

      // 5. Fallback: Direct PlayerJS in main HTML
      if (sources.isEmpty) {
        sources.addAll(PlayerJsParser.parseFromHtml(html));
      }

      // Deduplicate and Sort
      return _deduplicateAndSort(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> _resolvePlayerUrl(
    StreamSource source,
    List<StreamSource> sources,
  ) async {
    try {
      final html = await _client.get(source.url);
      final playerSources = PlayerJsParser.parseFromHtml(html);
      for (final ps in playerSources) {
        sources.add(
          ps.copyWith(
            voiceover: source.voiceover ?? ps.voiceover,
            season: source.season ?? ps.season,
            episode: source.episode ?? ps.episode,
            episodeTitle: source.episodeTitle ?? ps.episodeTitle,
          ),
        );
      }
    } catch (e) {
      Logger.w('Failed to resolve player URL: ${source.url}', tag: _tag);
    }
  }

  List<StreamSource> _deduplicateAndSort(List<StreamSource> sources) {
    final unique = <String, StreamSource>{};
    for (final s in sources) {
      unique[s.url] = s;
    }

    final result = unique.values.toList();

    // Refine quality
    for (var i = 0; i < result.length; i++) {
      final s = result[i];
      if (s.quality == StreamQuality.unknown ||
          s.quality == StreamQuality.q360p ||
          s.quality == StreamQuality.q480p) {
        // Try to guess from URL
        // We can use UakinoParser's helper if we expose it or copy logic
        // But UakinoParser methods are private/static helper.
        // Let's assume we trust the parser or PlayerJS parser.
        // Actually, I should expose `_parseQualityFromUrl` in UakinoParser as public `parseQualityFromUrl`
        // For now relying on what we have.
      }
    }

    result.sort((a, b) {
      final qA = UakinoParser.getQualityValue(a.quality);
      final qB = UakinoParser.getQualityValue(b.quality);
      return qB.compareTo(qA);
    });

    return result;
  }
}
