import 'dart:io';

import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';

/// YouTube content provider
///
/// Uses youtube_explode for direct stream extraction on desktop platforms.
/// Falls back to youtube_player_iframe on mobile/web.
///
/// Features:
/// - Search via YouTube search page parsing
/// - Direct stream URLs for desktop (Windows/Linux/macOS)
/// - Embed playback via youtube_player_iframe for mobile
/// - No login/cookies required
///
/// This provider is shown in a separate category, not on the home page.
class YouTubeProvider implements ContentProvider {
  static const String _tag = 'YouTube';

  final ApiClient _client;
  bool _isEnabled = false;

  /// Whether to show this provider on the home page (false for YouTube)
  static const bool showOnHome = false;

  /// Whether browsing requires search (no catalog available)
  /// YouTube blocks scraping catalog pages, only search works
  static const bool requiresSearch = true;

  /// YouTube base URL
  static const String _baseUrl = 'https://www.youtube.com';

  YouTubeProvider(this._client);

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  String? get iconUrl => 'https://www.youtube.com/favicon.ico';

  @override
  String get baseUrl => _baseUrl;

  @override
  String get effectiveBaseUrl => _baseUrl;

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
      // YouTube search via web scraping (basic parsing)
      final searchUrl =
          '$_baseUrl/results?search_query=${Uri.encodeComponent(query)}';

      final html = await _client.get(searchUrl, headers: _browserHeaders);

      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Search failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  /// Parse search results from YouTube HTML
  List<MediaItem> _parseSearchResults(String html) {
    final results = <MediaItem>[];

    try {
      Logger.d('YouTube HTML length: ${html.length}', tag: _tag);

      // YouTube embeds video data in JSON within script tags
      // Try multiple patterns for ytInitialData
      String? jsonStr;

      // Pattern 1: var ytInitialData = {...};
      var dataMatch = RegExp(
        r'var ytInitialData\s*=\s*(\{.+?\});\s*</script>',
        dotAll: true,
      ).firstMatch(html);

      if (dataMatch != null) {
        jsonStr = dataMatch.group(1);
        Logger.d('Found ytInitialData via pattern 1', tag: _tag);
      }

      // Pattern 2: ytInitialData = {...};
      if (jsonStr == null) {
        dataMatch = RegExp(
          r'ytInitialData\s*=\s*(\{.+?\});\s*</script>',
          dotAll: true,
        ).firstMatch(html);
        if (dataMatch != null) {
          jsonStr = dataMatch.group(1);
          Logger.d('Found ytInitialData via pattern 2', tag: _tag);
        }
      }

      // Pattern 3: window["ytInitialData"] = {...};
      if (jsonStr == null) {
        dataMatch = RegExp(
          r'window\["ytInitialData"\]\s*=\s*(\{.+?\});',
          dotAll: true,
        ).firstMatch(html);
        if (dataMatch != null) {
          jsonStr = dataMatch.group(1);
          Logger.d('Found ytInitialData via pattern 3', tag: _tag);
        }
      }

      if (jsonStr != null) {
        results.addAll(_parseYtInitialData(jsonStr));
        Logger.d(
          'Parsed ${results.length} videos from ytInitialData',
          tag: _tag,
        );
      }

      // Fallback: basic HTML parsing
      if (results.isEmpty) {
        final soup = BeautifulSoup(html);
        final videoElements = soup.findAll(
          'a',
          attrs: {'href': RegExp(r'/watch\?v=')},
        );

        final seenIds = <String>{};
        for (final element in videoElements.take(20)) {
          final href = element.attributes['href'] ?? '';
          final videoId = _extractVideoId(href);

          if (videoId != null && !seenIds.contains(videoId)) {
            seenIds.add(videoId);

            final title = element.attributes['title'] ?? element.text.trim();

            if (title.isNotEmpty) {
              results.add(
                MediaItem(
                  id: videoId,
                  providerId: id,
                  title: title,
                  posterUrl:
                      'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                  type: ContentType.movie, // Default type
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      Logger.w('Parse search results failed: $e', tag: _tag);
    }

    return results;
  }

  /// Parse ytInitialData JSON for video results
  List<MediaItem> _parseYtInitialData(String jsonStr) {
    final results = <MediaItem>[];

    try {
      // Extract video IDs and titles from the JSON structure
      // This is a simplified parser - YouTube's structure is complex
      final videoIdPattern = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"');
      final titlePattern = RegExp(r'"title":\{"runs":\[\{"text":"([^"]+)"');

      final videoIds = videoIdPattern
          .allMatches(jsonStr)
          .map((m) => m.group(1)!)
          .toSet();
      final titles = titlePattern
          .allMatches(jsonStr)
          .map((m) => m.group(1)!)
          .toList();

      var titleIndex = 0;
      for (final videoId in videoIds.take(20)) {
        final title = titleIndex < titles.length
            ? titles[titleIndex]
            : 'YouTube Video';
        titleIndex++;

        results.add(
          MediaItem(
            id: videoId,
            providerId: id,
            title: _decodeHtmlEntities(title),
            posterUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
            type: ContentType.movie,
          ),
        );
      }
    } catch (e) {
      Logger.w('Parse ytInitialData failed: $e', tag: _tag);
    }

    return results;
  }

  @override
  Future<MediaDetails> getDetails(String videoId) async {
    try {
      // Fetch video page for metadata
      final html = await _client.get(
        '$_baseUrl/watch?v=$videoId',
        headers: _browserHeaders,
      );

      return _parseDetails(html, videoId);
    } catch (e, stack) {
      Logger.e('Get details failed', tag: _tag, error: e, stackTrace: stack);
      // Return basic details on error
      return MediaDetails(
        item: MediaItem(
          id: videoId,
          providerId: id,
          title: 'YouTube Video',
          posterUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
          type: ContentType.movie,
        ),
      );
    }
  }

  /// Parse video details from YouTube page
  MediaDetails _parseDetails(String html, String videoId) {
    String title = 'YouTube Video';
    String? description;

    try {
      // Extract title
      final titleMatch = RegExp(r'"title":"([^"]+)"').firstMatch(html);
      if (titleMatch != null) {
        title = _decodeHtmlEntities(titleMatch.group(1)!);
      }

      // Extract description
      final descMatch = RegExp(
        r'"shortDescription":"([^"]*)"',
      ).firstMatch(html);
      if (descMatch != null) {
        description = _decodeHtmlEntities(descMatch.group(1)!);
      }
    } catch (e) {
      Logger.w('Parse details failed: $e', tag: _tag);
    }

    return MediaDetails(
      item: MediaItem(
        id: videoId,
        providerId: id,
        title: title,
        description: description,
        posterUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
        type: ContentType.movie,
      ),
      fullDescription: description,
    );
  }

  @override
  Future<List<StreamSource>> getStreams(
    String videoId, {
    int? season,
    int? episode,
  }) async {
    // On desktop platforms, use youtube_explode to get direct stream URLs
    // This allows playback via media_kit which doesn't support iframe embed
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _getDirectStreams(videoId);
    }

    // On mobile/web, use YouTube embed (ToS-compliant)
    return [
      StreamSource(
        url: videoId, // Just the video ID, player will construct embed URL
        quality: StreamQuality.unknown, // YouTube handles quality adaptively
        type: StreamType.youtubeEmbed,
        voiceover: 'YouTube',
        sourceName: 'YouTube',
      ),
    ];
  }

  /// Get direct stream URLs using youtube_explode
  Future<List<StreamSource>> _getDirectStreams(String videoId) async {
    final youtube = yt.YoutubeExplode();
    try {
      Logger.d('Getting direct streams for: $videoId', tag: _tag);

      final manifest = await youtube.videos.streamsClient.getManifest(videoId);
      final sources = <StreamSource>[];

      // Get ALL muxed streams (video + audio combined)
      // YouTube provides 144p, 240p, 360p, 480p, 720p as muxed
      // Higher qualities (1080p+) are video-only and need separate audio
      for (final stream in manifest.muxed) {
        final quality = _mapQuality(stream.videoQuality);

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

      // Remove duplicates by quality, keep highest bitrate
      final uniqueQualities = <StreamQuality, StreamSource>{};
      for (final source in sources) {
        uniqueQualities[source.quality] = source;
      }
      sources
        ..clear()
        ..addAll(uniqueQualities.values);

      // Sort by quality (highest first)
      sources.sort((a, b) => b.quality.index.compareTo(a.quality.index));

      Logger.d('Found ${sources.length} muxed streams', tag: _tag);

      // If no muxed streams available, return embed fallback
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
      // Fallback to embed on error
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

  /// Map YouTube quality to StreamQuality
  StreamQuality _mapQuality(yt.VideoQuality quality) {
    switch (quality) {
      case yt.VideoQuality.low144:
      case yt.VideoQuality.low240:
        return StreamQuality.unknown;
      case yt.VideoQuality.medium360:
        return StreamQuality.q360p;
      case yt.VideoQuality.medium480:
        return StreamQuality.q480p;
      case yt.VideoQuality.high720:
        return StreamQuality.q720p;
      case yt.VideoQuality.high1080:
        return StreamQuality.q1080p;
      case yt.VideoQuality.high1440:
        return StreamQuality.q1440p;
      case yt.VideoQuality.high2160:
        return StreamQuality.q4k;
      default:
        return StreamQuality.unknown;
    }
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) async {
    // YouTube trending - simplified implementation
    try {
      final html = await _client.get(
        '$_baseUrl/feed/trending',
        headers: _browserHeaders,
      );
      return _parseSearchResults(html);
    } catch (e, stack) {
      Logger.e('Get popular failed', tag: _tag, error: e, stackTrace: stack);
      return [];
    }
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) async {
    // Same as popular for YouTube
    return getPopular(type: type, page: page);
  }

  @override
  Future<List<String>> getCategories() async {
    // YouTube categories
    return [
      'Фільми',
      'Музика',
      'Ігри',
      'Новини',
      'Спорт',
      'Освіта',
      'Наука і технології',
      'Розваги',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) async {
    // Search by category name
    return search(category, type: type, page: page);
  }

  /// Extract video ID from YouTube URL
  String? _extractVideoId(String url) {
    // Handle various YouTube URL formats
    final patterns = [
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }

    // If it's already just a video ID
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) {
      return url;
    }

    return null;
  }

  /// Decode HTML entities
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('\\u0026', '&')
        .replaceAll('\\u003c', '<')
        .replaceAll('\\u003e', '>')
        .replaceAll('\\u0027', "'")
        .replaceAll('\\u0022', '"')
        .replaceAll('\\n', '\n')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  /// Browser-like headers to avoid blocks
  Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'uk-UA,uk;q=0.9,en-US;q=0.8,en;q=0.7',
    // Don't request compressed data - Dio may not decompress automatically
    // 'Accept-Encoding': 'gzip, deflate, br',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
  };

  /// Check if a URL is a valid YouTube video URL
  static bool isYouTubeUrl(String url) {
    return url.contains('youtube.com') || url.contains('youtu.be');
  }

  /// Extract video ID from any YouTube URL format
  static String? extractVideoIdFromUrl(String url) {
    final patterns = [
      RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'/shorts/([a-zA-Z0-9_-]{11})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// Get embed URL for a video ID
  static String getEmbedUrl(String videoId) {
    return 'https://www.youtube.com/embed/$videoId';
  }

  /// Get thumbnail URL for a video ID
  static String getThumbnailUrl(
    String videoId, {
    String quality = 'hqdefault',
  }) {
    // quality options: default, mqdefault, hqdefault, sddefault, maxresdefault
    return 'https://img.youtube.com/vi/$videoId/$quality.jpg';
  }
}
