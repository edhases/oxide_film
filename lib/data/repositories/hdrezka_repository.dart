import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/hdrezka_parser.dart';

class HdrezkaRepository {
  static const String _tag = 'HdrezkaRepository';
  final ApiClient _client;
  String _mirror = 'https://hdrezka-home.tv'; // Default mirror

  HdrezkaRepository(this._client);

  String get mirror => _mirror;

  void setMirror(String url) {
    _mirror = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    final url =
        '$_mirror/search/?do=search&subaction=search'
        '&q=${Uri.encodeComponent(query)}'
        '&page=$page';

    final html = await _client.get(url);
    return compute(_parseSearchCompute, {'html': html, 'id': 'hdrezka'});
  }

  static List<MediaItem> _parseSearchCompute(Map<String, String> data) {
    return HDRezkaParser.parseSearchResults(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    String section = '';
    switch (type) {
      case ContentType.movie:
        section = 'films';
        break;
      case ContentType.series:
        section = 'series';
        break;
      case ContentType.cartoon:
        section = 'cartoons';
        break;
      case ContentType.anime:
        section = 'animation';
        break;
      default:
        section = 'films';
    }

    final html = await _client.get(
      '$_mirror/$section/page/$page/?filter=popular',
    );
    return compute(_parseSearchCompute, {'html': html, 'id': 'hdrezka'});
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    String section = '';
    switch (type) {
      case ContentType.movie:
        section = 'films';
        break;
      case ContentType.series:
        section = 'series';
        break;
      case ContentType.cartoon:
        section = 'cartoons';
        break;
      case ContentType.anime:
        section = 'animation';
        break;
      default:
        section = 'new';
    }

    final html = await _client.get('$_mirror/$section/page/$page/');
    return compute(_parseSearchCompute, {'html': html, 'id': 'hdrezka'});
  }

  Future<List<String>> getCategories() async {
    // Return subset of genres that HDRezka supports
    return ContentGenres.all.take(10).toList();
  }

  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
    String providerId = 'hdrezka',
  }) async {
    final genreSlug = ProviderGenreMappings.getSlugForProvider(
      providerId,
      category,
    );
    final html = await _client.get(
      '$_mirror/films/genre/$genreSlug/page/$page/',
    );
    return compute(_parseSearchCompute, {'html': html, 'id': providerId});
  }

  Future<MediaDetails> getDetails(String id) async {
    final html = await _client.get('$_mirror/$id.html');
    return compute(_parseDetailsCompute, {
      'html': html,
      'id': id,
      'pid': 'hdrezka',
    });
  }

  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return HDRezkaParser.parseDetails(data['html']!, data['id']!, data['pid']!);
  }

  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) async {
    Logger.d(' getStreams called: id=$id, s=$season, e=$episode');
    try {
      final url = '$_mirror/$id.html';
      Logger.d(' Fetching: $url');
      final html = await _client.get(url);
      final sources = <StreamSource>[];

      // Offload initial parsing to isolate
      final params = await compute(HDRezkaParser.parseStreamInitParams, html);

      final csrfToken = params['csrf_token'] as String?;
      final dataId = params['data_id'] as String? ?? '';
      final translatorId = params['translator_id'] as String? ?? '';
      final translators = Map<String, String>.from(params['translators'] ?? {});

      if (dataId.isEmpty) {
        return sources;
      }

      // Default translator check logic handled in parser now, or fallback here?
      // Parser returns '238' default if missing.

      if (season != null && episode != null) {
        await _getEpisodeStreams(
          dataId,
          translatorId,
          season,
          episode,
          translators[translatorId] ?? 'Оригінал',
          sources,
          csrfToken: csrfToken,
        );
      } else {
        for (final entry in translators.entries) {
          await _getMovieStreams(
            dataId,
            entry.key,
            entry.value,
            sources,
            csrfToken: csrfToken,
          );
        }
      }

      return sources;
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<void> _getMovieStreams(
    String dataId,
    String translatorId,
    String voiceover,
    List<StreamSource> sources, {
    String? csrfToken,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'id': dataId,
        'translator_id': translatorId,
        'action': 'get_movie',
      };

      if (csrfToken != null) {
        requestData['_token'] = csrfToken;
      }

      final response = await _client.dio.post<String>(
        '$_mirror/ajax/get_cdn_series/',
        data: requestData,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$_mirror/',
            'Origin': _mirror,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-CSRF-TOKEN': ?csrfToken,
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final json = jsonDecode(response.data ?? '{}');
      if (json['success'] == true && json['url'] != null) {
        await _parseStreamUrls(json['url'], voiceover, sources);
      }
    } catch (e) {
      Logger.w('Failed to get movie streams for $voiceover', tag: _tag);
    }
  }

  Future<void> _getEpisodeStreams(
    String dataId,
    String translatorId,
    int season,
    int episode,
    String voiceover,
    List<StreamSource> sources, {
    String? csrfToken,
  }) async {
    try {
      final requestData = <String, dynamic>{
        'id': dataId,
        'translator_id': translatorId,
        'season': season.toString(),
        'episode': episode.toString(),
        'action': 'get_stream',
      };

      if (csrfToken != null) {
        requestData['_token'] = csrfToken;
      }

      final response = await _client.dio.post<String>(
        '$_mirror/ajax/get_cdn_series/',
        data: requestData,
        options: Options(
          headers: {
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': '$_mirror/',
            'Origin': _mirror,
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'X-CSRF-TOKEN': ?csrfToken,
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final json = jsonDecode(response.data ?? '{}');
      if (json['success'] == true && json['url'] != null) {
        await _parseStreamUrls(json['url'], voiceover, sources);
      }
    } catch (e) {
      Logger.w('Failed to get episode streams', tag: _tag);
    }
  }

  Future<void> _parseStreamUrls(
    String urlData,
    String voiceover,
    List<StreamSource> sources,
  ) async {
    try {
      final extracted = await compute(HDRezkaParser.extractStreamSources, {
        'url': urlData,
        'voiceover': voiceover,
      });
      sources.addAll(extracted);
    } catch (e) {
      Logger.w('Failed to parse stream URLs in isolate', tag: _tag, error: e);
    }
  }
}
