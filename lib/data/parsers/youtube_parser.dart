import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';

class YouTubeParser {
  static const String _tag = 'YouTubeParser';
  static const String baseUrl = 'https://www.youtube.com';

  /// Parse search results from YouTube HTML
  static List<MediaItem> parseSearchResults(String html) {
    final results = <MediaItem>[];

    try {
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
      }

      // Pattern 2: ytInitialData = {...};
      if (jsonStr == null) {
        dataMatch = RegExp(
          r'ytInitialData\s*=\s*(\{.+?\});\s*</script>',
          dotAll: true,
        ).firstMatch(html);
        if (dataMatch != null) {
          jsonStr = dataMatch.group(1);
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
        }
      }

      if (jsonStr != null) {
        results.addAll(_parseYtInitialData(jsonStr));
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
                  providerId: 'youtube',
                  title: title,
                  posterUrl:
                      'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                  type: ContentType.movie,
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
  static List<MediaItem> _parseYtInitialData(String jsonStr) {
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
            providerId: 'youtube',
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

  /// Parse video details from YouTube page
  static MediaDetails parseDetails(String html, String videoId) {
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
        providerId: 'youtube',
        title: title,
        description: description,
        posterUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
        type: ContentType.movie,
      ),
      fullDescription: description,
    );
  }

  static String? _extractVideoId(String url) {
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

  static String _decodeHtmlEntities(String text) {
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

  /// Map YouTube quality to StreamQuality
  static StreamQuality mapQuality(yt.VideoQuality quality) {
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
}
