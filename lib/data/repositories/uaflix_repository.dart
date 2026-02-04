import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/playerjs_parser.dart';
import '../parsers/uaflix_parser.dart';

class UaflixRepository {
  static const String _tag = 'UaflixRepository';
  final ApiClient _client;

  UaflixRepository(this._client);

  String get baseUrl => UaflixParser.baseUrl;

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    try {
      final url =
          '$baseUrl/index.php?do=search&subaction=search'
          '&story=${Uri.encodeComponent(query)}'
          '&search_start=$page';

      final html = await _client.get(url);
      return compute(UaflixParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String id) async {
    try {
      final url = '$baseUrl/$id/';
      final html = await _client.get(url);
      return compute(_parseDetailsCompute, {'html': html, 'id': id});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return UaflixParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      String category = _typeToCategory(type);
      final url = '$baseUrl/$category/page/$page/';
      final html = await _client.get(url);
      return compute(UaflixParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      // Logic from old provider: movies -> films/new_netflix_ua, series -> serials/new_uaserial
      String category = 'films/new_netflix_ua';
      if (type == ContentType.series) {
        category = 'serials/new_uaserial';
      }

      final url = '$baseUrl/$category/page/$page/';
      final html = await _client.get(url);
      return compute(UaflixParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getByCategory(String category, {int page = 1}) async {
    try {
      final url = '$baseUrl/$category/page/$page/';
      final html = await _client.get(url);
      return compute(UaflixParser.parseSearchResults, html);
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
      final url = '$baseUrl/$id/';
      final html = await _client.get(url);
      final sources = <StreamSource>[];

      // 1. Iframes
      final iframes = await compute(UaflixParser.extractIframeSrcs, html);
      for (final src in iframes) {
        await _parseIframeSource(src, sources);
      }

      // 2. PlayJS on main page
      if (sources.isEmpty) {
        final parsed = await compute(PlayerJsParser.parseFromHtml, html);
        sources.addAll(parsed);
      }

      // 3. Video elements fallback
      if (sources.isEmpty) {
        final videoSrcs = await compute(UaflixParser.extractVideoSrcs, html);
        sources.addAll(
          videoSrcs.map(
            (e) => StreamSource(
              url: e,
              quality: StreamQuality.unknown,
              type: StreamType.direct,
            ),
          ),
        );
      }

      return _deduplicateSources(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> _parseIframeSource(
    String src,
    List<StreamSource> sources,
  ) async {
    try {
      // UAFlix iframes require Referer
      final html = await _client.get(src, headers: {'Referer': '$baseUrl/'});
      final parsed = await compute(PlayerJsParser.parseFromHtml, html);
      sources.addAll(parsed);
    } catch (e) {
      Logger.w('Failed to parse iframe: $src', tag: _tag);
    }
  }

  List<StreamSource> _deduplicateSources(List<StreamSource> sources) {
    final unique = <String, StreamSource>{};
    for (final s in sources) {
      if (!unique.containsKey(s.url)) {
        unique[s.url] = s;
      }
    }
    return unique.values.toList();
  }

  String _typeToCategory(ContentType? type) {
    switch (type) {
      case ContentType.movie:
        return 'film';
      case ContentType.series:
        return 'serials';
      case ContentType.cartoon:
        return 'cartoons';
      case ContentType.anime:
        return 'anime';
      default:
        return 'film';
    }
  }
}
