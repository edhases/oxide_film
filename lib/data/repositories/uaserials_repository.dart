import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/playerjs_parser.dart';
import '../parsers/uaserials_parser.dart';

class UaserialsRepository {
  static const String _tag = 'UaserialsRepository';
  final ApiClient _client;

  UaserialsRepository(this._client);

  String get baseUrl => UaserialsParser.baseUrl;

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    try {
      final url =
          '$baseUrl/index.php?do=search&subaction=search'
          '&story=${Uri.encodeComponent(query)}'
          '&search_start=$page';

      final html = await _client.get(url);
      return compute(UaserialsParser.parseList, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String id) async {
    try {
      // id cleanup handled by provider/repo logic usually, but here ID is assumed clean derived from parser
      final url = '$baseUrl/$id.html';
      final html = await _client.get(url);
      return compute(_parseDetailsCompute, {'html': html, 'id': id});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return UaserialsParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final url = page == 1 ? baseUrl : '$baseUrl/page/$page/';
      final html = await _client.get(url);
      return compute(UaserialsParser.parseList, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) {
    return getPopular(type: type, page: page);
  }

  Future<List<MediaItem>> getByCategory(String category, {int page = 1}) async {
    try {
      final url = '$baseUrl/$category/page/$page/';
      final html = await _client.get(url);
      return compute(UaserialsParser.parseList, html);
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
      final url = '$baseUrl/$id.html';
      final html = await _client.get(url);
      final sources = <StreamSource>[];

      // 1. Check Iframes
      final iframeSrcs = await compute(UaserialsParser.extractIframeSrcs, html);
      for (final src in iframeSrcs) {
        try {
          // Fetch iframe content
          final frameHtml = await _client.get(
            src,
            headers: {'Referer': baseUrl},
          );

          // Parse PlayerJS from iframe
          final parsed = await compute(PlayerJsParser.parseFromHtml, frameHtml);
          if (parsed.isNotEmpty) {
            sources.addAll(parsed);
          }
        } catch (e) {
          Logger.w('Failed to parse iframe: $src', tag: _tag);
        }
      }

      // 2. Check Main Page
      final pageSources = await compute(PlayerJsParser.parseFromHtml, html);
      sources.addAll(pageSources);

      return _deduplicateSources(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
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
}
