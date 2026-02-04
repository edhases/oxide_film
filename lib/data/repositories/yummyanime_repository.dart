import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/yummyanime_parser.dart';

class YummyAnimeRepository {
  static const String _tag = 'YummyAnimeRepository';
  final ApiClient _client;
  String _mirror = 'https://yummyanime.tv'; // Club is blocked, use TV

  YummyAnimeRepository(this._client);

  String get baseUrl => _mirror;

  void setMirror(String url) {
    _mirror = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
    'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
    'Referer': _mirror,
    'DNT': '1',
    'Upgrade-Insecure-Requests': '1',
  };

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    // YummyAnime now uses POST for search
    try {
      // ApiClient.post returns Map<String, dynamic> by default/implementation?
      // In ApiClient.dart: Future<Map<String, dynamic>> post(...)
      // But YummyAnime returns HTML.
      // We need ApiClient to handle raw string response for POST or use dio directly.

      final response = await _client.dio.post(
        '$baseUrl/index.php?do=search',
        data: FormData.fromMap({
          'do': 'search',
          'subaction': 'search',
          'story': query,
        }),
        options: Options(
          headers: _browserHeaders,
          responseType: ResponseType.plain, // Force string
        ),
      );

      final html = response.data.toString();
      return compute(YummyAnimeParser.parseSearchResults, html);
    } catch (e) {
      Logger.w('POST Search failed, trying legacy GET', tag: _tag);
    }

    // Fallback to legacy GET (likely broken but harmless to keep)
    try {
      final html = await _client.get(
        '$baseUrl/search?q=${Uri.encodeComponent(query)}',
        headers: _browserHeaders,
      );
      return compute(YummyAnimeParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String id) async {
    try {
      // ID extracted from URL usually includes .html or is a slug.
      // New structure seems to be at root level or handled by redirect.
      // Safest is to try root first if it contains .html, or /anime/ if plain slug?
      // Actually, standard is now relative to root for many items.
      // Let's try to construct URL carefully.
      var url = '$baseUrl/$id';
      if (!id.endsWith('.html') && !id.contains('/')) {
        // Maybe it needs /anime/ prefix if it's a pure slug from API?
        // But parser extracts full filename from HTML.
        // Let's try straight append first.
      }

      // If ID already starts with anime/, remove baseUrl's slash
      if (id.startsWith('anime/')) {
        url =
            '$baseUrl/${id.substring(6)}'; // assumes baseUrl has no trailing slash, but we add one usually
        // Actually baseUrl is clean.
        url = '$baseUrl/$id';
      }

      final html = await _client.get(url, headers: _browserHeaders);
      return compute(_parseDetailsCompute, {'html': html, 'id': id});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      rethrow;
    }
  }

  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return YummyAnimeParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    try {
      final html = await _client.get(
        '$baseUrl/anime?sort=popular&page=$page',
        headers: _browserHeaders,
      );
      return compute(YummyAnimeParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    try {
      final html = await _client.get(
        '$baseUrl/anime?sort=latest&page=$page',
        headers: _browserHeaders,
      );
      return compute(YummyAnimeParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Get new failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getByCategory(String slug, {int page = 1}) async {
    try {
      final html = await _client.get(
        '$baseUrl/anime?genre=$slug&page=$page',
        headers: _browserHeaders,
      );
      return compute(YummyAnimeParser.parseSearchResults, html);
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
      final url = '$baseUrl/$id'; // Was $baseUrl/anime/$id
      final html = await _client.get(url, headers: _browserHeaders);
      final sources = <StreamSource>[];

      final episodeNum = episode ?? 1;

      // 1. Extract episode items (id mapping)
      final episodeItems = await compute(
        YummyAnimeParser.extractEpisodeItems,
        html,
      );
      String? dataId;
      String? playerParams;

      // Find matching episode
      // If we only found a single player (no proper episodes list), we use that if episode is 1
      if (episodeItems.length == 1 &&
          episodeItems.first['player_params'] != null) {
        if (episodeNum == 1) {
          playerParams = episodeItems.first['player_params'];
          dataId = episodeItems.first['id'];
        }
      } else {
        for (final item in episodeItems) {
          if (item['episode'] == episodeNum.toString()) {
            dataId = item['id'];
            playerParams =
                item['player_params']; // Might be null for standard list items
            break;
          }
        }
      }

      // If we have player_params, use controller.php to get the iframe
      if (playerParams != null) {
        try {
          // Parse params to map
          final paramsMap = Uri.splitQueryString(playerParams);

          final response = await _client.getJson(
            '$baseUrl/engine/ajax/controller.php',
            queryParameters: paramsMap,
            headers: {
              ..._browserHeaders,
              'X-Requested-With': 'XMLHttpRequest',
              'Referer': url,
            },
          );

          if (response['success'] == true && response['data'] != null) {
            final iframeUrl = response['data'].toString();
            // This is usually a Kodik or Ashdi URL.
            // We return it as a direct source, but typed as HLS/Embed so PlayerPage can extract it.
            // Actually, better to mark it as StreamType.youtubeEmbed or similar if it needs extraction?
            // Standard StreamType.direct with a known provider URL usually triggers extractor.
            // Or better, let's process it if it's Kodik.

            if (iframeUrl.contains('kodik')) {
              sources.add(
                StreamSource(
                  url: iframeUrl,
                  quality: StreamQuality.unknown, // Kodik handles quality
                  type: StreamType
                      .direct, // Needs extraction but marked as direct for now
                  sourceName: 'Kodik',
                ),
              );
            } else {
              sources.add(
                StreamSource(
                  url: iframeUrl,
                  quality: StreamQuality.unknown,
                  type: StreamType.direct,
                ),
              );
            }
          }
        } catch (e) {
          Logger.w(
            'Failed to fetch player from controller',
            tag: _tag,
            error: e,
          );
        }
      }

      Map<String, dynamic>? episodeData;

      if (dataId != null && playerParams == null) {
        // Fetch via API (Legacy/Standard flow)
        try {
          final response = await _client.dio.get<String>(
            '$baseUrl/api/episode/$dataId',
            options: Options(
              headers: {
                ..._browserHeaders,
                'X-Requested-With': 'XMLHttpRequest',
              },
            ),
          );
          if (response.data != null) {
            episodeData = jsonDecode(response.data!);
          }
        } catch (e) {
          Logger.w('Failed to get episode API data', tag: _tag);
        }
      }

      // Fallback API call
      if (episodeData == null && playerParams == null) {
        try {
          final response = await _client.dio.get<String>(
            '$baseUrl/api/anime/$id/episode/$episodeNum',
            options: Options(
              headers: {
                ..._browserHeaders,
                'X-Requested-With': 'XMLHttpRequest',
              },
            ),
          );
          if (response.data != null) {
            episodeData = jsonDecode(response.data!);
          }
        } catch (e) {
          Logger.w('Failed to get fallback episode API data', tag: _tag);
        }
      }

      if (episodeData != null) {
        // Parse basic sources
        final initialSources = await compute(
          YummyAnimeParser.parseEpisodeSources,
          episodeData,
        );

        // Process sources to resolve embeds
        for (final source in initialSources) {
          var processed = false;
          // Check if it's an embed URL we need to fetch
          if (source.url.contains('ashdi') ||
              source.url.contains('kodik') ||
              source.url.contains('aniboom')) {
            final embedSources = await _fetchEmbed(
              source.url,
              source.voiceover,
            );
            if (embedSources.isNotEmpty) {
              sources.addAll(embedSources);
              processed = true;
            }
          }

          // If not processed or we just want to keep the original (e.g. might be direct link)
          // Usually we keep unless we replaced it. But here we add found streams.
          if (!processed) {
            sources.add(source);
          }
        }
      }

      return _deduplicateSources(sources);
    } catch (e, stack) {
      Logger.e('Get streams failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<StreamSource>> _fetchEmbed(String url, String? voiceover) async {
    try {
      var fetchUrl = url;
      if (fetchUrl.startsWith('//')) fetchUrl = 'https:$fetchUrl';

      final html = await _client.get(
        fetchUrl,
      ); // Standard client might be enough for embeds

      // For Kodik, might need special logic or just regex
      // YummyAnimeParser has regex logic for Ashdi and generic
      return compute(_parseEmbedCompute, {
        'html': html,
        'voiceover': voiceover,
      });
    } catch (e) {
      Logger.w('Failed to fetch embed: $url', tag: _tag);
      return [];
    }
  }

  static List<StreamSource> _parseEmbedCompute(Map<String, String?> data) {
    return YummyAnimeParser.parseEmbedContent(
      data['html']!,
      voiceover: data['voiceover'],
    );
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
