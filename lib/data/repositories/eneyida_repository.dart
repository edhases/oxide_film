import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/eneyida_parser.dart';
import '../parsers/playerjs_parser.dart';

class EneyidaRepository {
  static const String _tag = 'EneyidaRepository';
  final ApiClient _client;

  EneyidaRepository(this._client);

  String get baseUrl => EneyidaParser.baseUrl;

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    try {
      final url =
          '$baseUrl/index.php?do=search&subaction=search'
          '&story=${Uri.encodeComponent(query)}'
          '&search_start=$page';

      final html = await _client.get(url);
      return compute(EneyidaParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String id) async {
    try {
      var cleanId = _cleanId(id);
      final html = await _client.get('$baseUrl/$cleanId.html');
      return compute(_parseDetailsCompute, {'html': html, 'id': cleanId});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  // Wrapper for compute
  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return EneyidaParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      String section = _typeToSection(type);
      final html = await _client.get('$baseUrl/$section/page/$page/');
      return compute(EneyidaParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      // Eneyida "new" is just main page
      final html = await _client.get('$baseUrl/page/$page/');
      // TODO: Filter by type if needed? Main page has mix.
      // Current provider impl just returned mix.
      return compute(EneyidaParser.parseCatalog, html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getByCategory(
    String categorySlug, {
    int page = 1,
  }) async {
    try {
      final html = await _client.get(
        '$baseUrl/genre/$categorySlug/page/$page/',
      );
      return compute(EneyidaParser.parseCatalog, html);
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

  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) async {
    try {
      var cleanId = _cleanId(id);
      final url = '$baseUrl/$cleanId.html';
      final html = await _client.get(url);
      final sources = <StreamSource>[];

      // 1. Try AJAX playlist (Priority 1)
      final newsId = EneyidaParser.extractNewsId(html, cleanId);
      if (newsId != null) {
        try {
          final ajaxSources = await _fetchAjaxPlaylist(newsId, url);
          // Resolve any indirect sources
          for (final source in ajaxSources) {
            if (source.type == StreamType.direct &&
                !source.url.endsWith('.mp4') &&
                !source.url.endsWith('.m3u8')) {
              // Likely a player page link, resolve it
              await _resolvePlayerUrl(source, sources);
            } else {
              sources.add(source);
            }
          }
        } catch (e) {
          Logger.w('AJAX playlist failed: $e', tag: _tag);
        }
      }

      // 2. If AJAX yielded nothing, try Iframes
      if (sources.isEmpty) {
        final iframes = await compute(EneyidaParser.extractIframeSrcs, html);
        for (final src in iframes) {
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

      // 3. Script Parsing (PlayerJS directly in HTML)
      if (sources.isEmpty) {
        // We can use PlayerJS parser on the whole HTML
        final playerJsSources = await compute(
          PlayerJsParser.parseFromHtml,
          html,
        );
        sources.addAll(playerJsSources);
      }

      return _deduplicateSources(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<StreamSource>> _fetchAjaxPlaylist(
    String newsId,
    String referer,
  ) async {
    final url = '$baseUrl/engine/ajax/playlists.php';
    final response = await _client.dio.post<String>(
      url,
      data: {'news_id': newsId, 'xfield': 'playlist'},
      options: Options(
        headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': referer},
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    final body = response.data ?? '';
    if (body.isEmpty) return [];

    return compute(EneyidaParser.parseAjaxPlaylist, body);
  }

  Future<void> _resolvePlayerUrl(
    StreamSource source,
    List<StreamSource> sources,
  ) async {
    try {
      var url = source.url;
      if (url.startsWith('//')) url = 'https:$url';

      final html = await _client.get(url);
      final parsed = await compute(PlayerJsParser.parseFromHtml, html);

      for (final s in parsed) {
        sources.add(
          s.copyWith(
            voiceover: source.voiceover ?? s.voiceover,
            season: source.season ?? s.season,
            episode: source.episode ?? s.episode,
          ),
        );
      }
    } catch (e) {
      Logger.w('Failed to resolve player URL: ${source.url}', tag: _tag);
    }
  }

  List<StreamSource> _deduplicateSources(List<StreamSource> sources) {
    final unique = <String, StreamSource>{};
    for (final s in sources) {
      // Simple dedupe by URL
      if (!unique.containsKey(s.url)) {
        unique[s.url] = s;
      }
    }
    return unique.values.toList();
  }

  String _cleanId(String id) {
    var clean = id;
    if (clean.contains('eneyida.tv/'))
      clean = clean.replaceAll('eneyida.tv/', '');
    if (clean.startsWith('/')) clean = clean.substring(1);
    return clean;
  }

  String _typeToSection(ContentType? type) {
    switch (type) {
      case ContentType.movie:
        return 'films';
      case ContentType.series:
        return 'series';
      case ContentType.cartoon:
        return 'cartoon';
      case ContentType.anime:
        return 'anime';
      default:
        return 'films';
    }
  }
}
