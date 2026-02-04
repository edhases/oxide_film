import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../parsers/youtube_parser.dart';

class YouTubeRepository {
  static const String _tag = 'YouTubeRepository';
  final ApiClient _client;

  YouTubeRepository(this._client);

  String get baseUrl => YouTubeParser.baseUrl;

  /// Browser-like headers to avoid blocks
  Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
  };

  Future<List<MediaItem>> search(String query, {int page = 1}) async {
    try {
      final searchUrl =
          '$baseUrl/results?search_query=${Uri.encodeComponent(query)}';
      final html = await _client.get(searchUrl, headers: _browserHeaders);
      return compute(YouTubeParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<List<MediaItem>> getPopular() async {
    try {
      final html = await _client.get(
        '$baseUrl/feed/trending',
        headers: _browserHeaders,
      );
      return compute(YouTubeParser.parseSearchResults, html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  Future<MediaDetails> getDetails(String videoId) async {
    try {
      final html = await _client.get(
        '$baseUrl/watch?v=$videoId',
        headers: _browserHeaders,
      );
      return compute(_parseDetailsCompute, {'html': html, 'id': videoId});
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      return MediaDetails(
        item: MediaItem(
          id: videoId,
          providerId: 'youtube',
          title: 'YouTube Video',
          posterUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
          type: ContentType.movie,
        ),
      );
    }
  }

  static MediaDetails _parseDetailsCompute(Map<String, String> data) {
    return YouTubeParser.parseDetails(data['html']!, data['id']!);
  }

  Future<List<StreamSource>> getStreams(String videoId) async {
    // On desktop platforms, use youtube_explode to get direct stream URLs
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _getDirectStreams(videoId);
    }

    // On mobile/web, use YouTube embed (ToS-compliant)
    return [
      StreamSource(
        url: videoId,
        quality: StreamQuality.unknown,
        type: StreamType.youtubeEmbed,
        voiceover: 'YouTube',
        sourceName: 'YouTube',
      ),
    ];
  }

  Future<List<StreamSource>> _getDirectStreams(String videoId) async {
    final youtube = yt.YoutubeExplode();
    try {
      Logger.d('Getting direct streams for: $videoId', tag: _tag);

      final manifest = await youtube.videos.streamsClient.getManifest(videoId);
      final sources = <StreamSource>[];

      for (final stream in manifest.muxed) {
        final quality = YouTubeParser.mapQuality(stream.videoQuality);
        sources.add(
          StreamSource(
            url: stream.url.toString(),
            quality: quality,
            type: StreamType.direct,
            voiceover: 'YouTube',
            sourceName: 'YouTube ${stream.videoQuality.name}',
          ),
        );
      }

      // Deduplicate keeping highest bitrate/quality
      final uniqueQualities = <StreamQuality, StreamSource>{};
      for (final source in sources) {
        uniqueQualities[source.quality] = source;
      }
      sources
        ..clear()
        ..addAll(uniqueQualities.values);

      sources.sort((a, b) => b.quality.index.compareTo(a.quality.index));

      if (sources.isEmpty) {
        return [
          StreamSource(
            url: videoId,
            quality: StreamQuality.unknown,
            type: StreamType.youtubeEmbed,
            voiceover: 'YouTube',
            sourceName: 'YouTube',
          ),
        ];
      }

      return sources;
    } catch (e, stack) {
      Logger.e(
        'Failed to get direct streams',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
      return [
        StreamSource(
          url: videoId,
          quality: StreamQuality.unknown,
          type: StreamType.youtubeEmbed,
          voiceover: 'YouTube',
          sourceName: 'YouTube',
        ),
      ];
    } finally {
      youtube.close();
    }
  }
}
