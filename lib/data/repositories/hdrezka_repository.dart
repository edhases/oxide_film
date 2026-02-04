import 'dart:convert';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
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
      final soup = BeautifulSoup(html);
      final sources = <StreamSource>[];

      // Extract CSRF
      String? csrfToken;
      final metaCsrf = soup.find('meta', attrs: {'name': 'csrf-token'});
      csrfToken = metaCsrf?.attributes['content'];

      if (csrfToken == null) {
        for (final script in soup.findAll('script')) {
          final content = script.text;
          final tokenMatch = RegExp(
            r'''(?:b_token|csrf_token|_token)\s*[:=]\s*["']([^"']+)["']''',
          ).firstMatch(content);
          if (tokenMatch != null) {
            csrfToken = tokenMatch.group(1);
            break;
          }
        }
      }

      // Extract IDs
      var dataId = '';
      var translatorId = '';

      for (final script in soup.findAll('script')) {
        final content = script.text;
        final initMatch = RegExp(
          r'initCDN(?:Movies|Series)Events\s*\(\s*(\d+)\s*,\s*(\d+)',
        ).firstMatch(content);
        if (initMatch != null) {
          dataId = initMatch.group(1) ?? '';
          translatorId = initMatch.group(2) ?? '';
          break;
        }

        final sofMatch = RegExp(
          r'sof\.tv\.initCDN\w+Events\s*\(\s*(\d+)\s*,\s*(\d+)',
        ).firstMatch(content);
        if (sofMatch != null) {
          dataId = sofMatch.group(1) ?? '';
          translatorId = sofMatch.group(2) ?? '';
          break;
        }
      }

      if (dataId.isEmpty) {
        final playerDiv =
            soup.find('div', attrs: {'id': 'cdnplayer'}) ??
            soup.find('div', class_: 'b-player') ??
            soup.find('div', class_: 'b-content__inline_item') ??
            soup.find('div', attrs: {'id': 'player'});

        dataId = playerDiv?.attributes['data-id'] ?? '';
        translatorId =
            playerDiv?.attributes['data-translator_id'] ?? translatorId;
      }

      if (translatorId.isEmpty || translatorId == '0') {
        final firstTranslator = soup.find('li', class_: 'b-translator__item');
        if (firstTranslator != null) {
          translatorId = firstTranslator.attributes['data-translator_id'] ?? '';
        }
      }

      if (dataId.isEmpty) {
        final fallback = soup.find('*', attrs: {'data-id': true});
        if (fallback != null) {
          dataId = fallback.attributes['data-id'] ?? '';
          if (translatorId.isEmpty) {
            translatorId = fallback.attributes['data-translator_id'] ?? '';
          }
        }
      }

      if (dataId.isEmpty) {
        final urlMatch = RegExp(r'/(\d+)-').firstMatch(id);
        if (urlMatch != null) {
          dataId = urlMatch.group(1) ?? '';
        }
      }

      if (translatorId.isEmpty) {
        translatorId = '238';
      }

      if (dataId.isEmpty) {
        return sources;
      }

      // Translators
      final translators = <String, String>{};
      final translatorsList = soup.find('ul', id: 'translators-list');

      if (translatorsList != null) {
        for (final li in translatorsList.findAll('li')) {
          final tid = li.attributes['data-translator_id'];
          final tname = li.text.trim();
          if (tid != null) {
            translators[tid] = tname;
          }
        }
      }

      if (translators.isEmpty) {
        translators[translatorId] = 'Оригінал';
      }

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
            if (csrfToken != null) 'X-CSRF-TOKEN': csrfToken,
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final json = jsonDecode(response.data ?? '{}');
      if (json['success'] == true && json['url'] != null) {
        _parseStreamUrls(json['url'], voiceover, sources);
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
            if (csrfToken != null) 'X-CSRF-TOKEN': csrfToken,
          },
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final json = jsonDecode(response.data ?? '{}');
      if (json['success'] == true && json['url'] != null) {
        _parseStreamUrls(json['url'], voiceover, sources);
      }
    } catch (e) {
      Logger.w('Failed to get episode streams', tag: _tag);
    }
  }

  void _parseStreamUrls(
    String urlData,
    String voiceover,
    List<StreamSource> sources,
  ) {
    final decoded = HDRezkaParser.decodeStreamUrl(urlData);
    final pattern = RegExp(r'\[(\d+)p?\s*[^\]]*\]([^\[]+)');
    final matches = pattern.allMatches(decoded).toList();

    for (final match in matches) {
      final quality = match.group(1);
      var url = match.group(2)?.trim() ?? '';

      // Use parser utilities for cleaning and validation
      url = HDRezkaParser.normalizeStreamUrl(url);

      if (url.isNotEmpty &&
          !url.contains('undefined') &&
          HDRezkaParser.isValidStreamUrl(url)) {
        sources.add(
          StreamSource(
            url: url,
            quality: HDRezkaParser.parseQuality(quality),
            voiceover: voiceover,
            type: url.contains('.m3u8') ? StreamType.hls : StreamType.direct,
          ),
        );
      }
    }
  }
}
