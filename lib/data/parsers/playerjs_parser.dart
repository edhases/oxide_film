import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/entities.dart';

/// Parser for PlayerJS-based video players
///
/// Many Ukrainian streaming sites use PlayerJS (https://playerjs.com)
/// This utility extracts video streams from PlayerJS configurations
class PlayerJsParser {
  static const String _tag = 'PlayerJS';

  /// Parse PlayerJS configuration from page HTML
  ///
  /// Looks for patterns like:
  /// - new Playerjs({...file:"..."...})
  /// - Playerjs({...file:"..."...})
  /// - file:"[encoded_data]"
  static Future<List<StreamSource>> parseFromHtmlCompute(String html) async {
    return compute(parseFromHtml, html);
  }

  static List<StreamSource> parseFromHtml(String html) {
    final sources = <StreamSource>[];

    try {
      // Extract default_quality if present
      String? defaultQuality;
      final defaultQualityPattern = RegExp(
        r'''default_quality\s*[:=]\s*["'](\d+p?)["']''',
        caseSensitive: false,
      );
      final defaultQualityMatch = defaultQualityPattern.firstMatch(html);
      if (defaultQualityMatch != null) {
        defaultQuality = defaultQualityMatch.group(1);
      }

      // Pattern 1: Extract file parameter from PlayerJS init
      // Matches: file:"..." or file:'...'
      final filePattern = RegExp(
        r'''file\s*[:=]\s*["']([^"']+)["']''',
        caseSensitive: false,
      );

      for (final match in filePattern.allMatches(html)) {
        final fileValue = match.group(1);
        if (fileValue != null && fileValue.isNotEmpty) {
          sources.addAll(
            _parseFileValue(fileValue, defaultQuality: defaultQuality),
          );
        }
      }

      // Pattern 2: Look for encoded data (often base64 or custom encoding)
      // Matches: file:"#encoded..."
      final encodedPattern = RegExp(
        r'''file\s*[:=]\s*["']#([^"']+)["']''',
        caseSensitive: false,
      );

      for (final match in encodedPattern.allMatches(html)) {
        final encodedValue = match.group(1);
        if (encodedValue != null) {
          final decoded = _decodePlayerJsString(encodedValue);
          if (decoded != null) {
            sources.addAll(
              _parseFileValue(decoded, defaultQuality: defaultQuality),
            );
          }
        }
      }
    } catch (e, stack) {
      Logger.e(
        'Failed to parse PlayerJS config',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }

    return sources;
  }

  /// Parse the file value which can be:
  /// - Direct URL: https://...
  /// - HLS playlist: https://...m3u8
  /// - Quality array: [720p]https://...[/720p],[1080p]https://...[/1080p]
  /// - JSON array of sources
  static List<StreamSource> _parseFileValue(
    String fileValue, {
    String? defaultQuality,
  }) {
    final sources = <StreamSource>[];

    try {
      // Check if it's a JSON array
      if (fileValue.trim().startsWith('[') && fileValue.contains('{')) {
        try {
          final dynamic jsonData = json.decode(fileValue);
          if (jsonData is List) {
            for (final source in jsonData) {
              try {
                if (source is Map<String, dynamic>) {
                  final file = source['file'] as String?;
                  final title = source['title'] as String?;
                  if (file != null && _isValidUrl(file)) {
                    sources.add(
                      _createStreamSource(
                        file,
                        voiceover: title,
                        qualityLabel: defaultQuality,
                      ),
                    );
                  }
                }
              } catch (e) {
                // Log but continue parsing other items
                Logger.w('Failed to parse single JSON source: $e', tag: _tag);
              }
            }
            if (sources.isNotEmpty) return sources;
          }
        } on FormatException catch (e) {
          Logger.d(
            'JSON parsing failed: ${e.message}, trying other patterns',
            tag: _tag,
          );
          // Not valid JSON, continue with other parsing
        } catch (e) {
          Logger.w('Unexpected JSON parse error: $e', tag: _tag);
          // Continue with other parsing methods
        }
      }

      // Check for quality markers: [720p]url[/720p],[1080p]url[/1080p]
      // OR [720p]url
      final qualityPattern = RegExp(
        r'\[(\d+p?)\]([^,\[\]]+)(?:\[/\1\])?',
        caseSensitive: false,
      );

      if (qualityPattern.hasMatch(fileValue)) {
        for (final match in qualityPattern.allMatches(fileValue)) {
          try {
            final quality = match.group(1);
            final url = match.group(2)?.trim();
            if (url != null && url.isNotEmpty && _isValidUrl(url)) {
              sources.add(_createStreamSource(url, qualityLabel: quality));
            }
          } catch (e) {
            Logger.w('Failed to parse quality marker', tag: _tag);
          }
        }
        if (sources.isNotEmpty) return sources;
      }

      // Check for comma-separated URLs with quality
      if (fileValue.contains(',') && fileValue.contains('or ')) {
        final parts = fileValue.split(',');
        for (final part in parts) {
          try {
            final trimmed = part.trim();
            // Pattern: "720p or URL" or just URL
            final orMatch = RegExp(
              r'(\d+p)\s+or\s+(.+)',
              caseSensitive: false,
            ).firstMatch(trimmed);
            if (orMatch != null) {
              final quality = orMatch.group(1);
              final url = orMatch.group(2)?.trim();
              if (url != null && _isValidUrl(url)) {
                sources.add(_createStreamSource(url, qualityLabel: quality));
              }
            } else if (trimmed.startsWith('http') && _isValidUrl(trimmed)) {
              sources.add(_createStreamSource(trimmed));
            }
          } catch (e) {
            Logger.w('Failed to parse comma-separated URL part', tag: _tag);
          }
        }
        if (sources.isNotEmpty) return sources;
      }

      // Single URL - use defaultQuality if no quality markers found
      if (fileValue.startsWith('http') && _isValidUrl(fileValue)) {
        sources.add(
          _createStreamSource(fileValue, qualityLabel: defaultQuality),
        );
      }
    } catch (e, stack) {
      Logger.e(
        'Failed to parse file value',
        tag: _tag,
        error: e,
        stackTrace: stack,
      );
    }

    return sources;
  }

  /// Create StreamSource from URL with optional quality label and voiceover
  static StreamSource _createStreamSource(
    String url, {
    String? qualityLabel,
    String? voiceover,
  }) {
    final quality = _parseQuality(qualityLabel);
    final type = _detectStreamType(url);

    return StreamSource(
      url: url.trim(),
      quality: quality,
      type: type,
      voiceover: voiceover,
    );
  }

  /// Validate if string is a proper URL
  /// Enhanced validation beyond just checking scheme presence
  static bool _isValidUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final trimmed = url.trim();
      final uri = Uri.parse(trimmed);

      // Must have http or https scheme
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;

      // Must have a host
      if (uri.host.isEmpty) return false;

      // Host must contain at least one dot (basic domain validation)
      // or be localhost/IP
      if (!uri.host.contains('.') &&
          uri.host != 'localhost' &&
          !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host)) {
        return false;
      }

      // Check for common injection patterns
      if (trimmed.contains('<script') ||
          trimmed.contains('javascript:') ||
          trimmed.contains('data:')) {
        Logger.w('Rejected URL with potential injection: $trimmed', tag: _tag);
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Detect stream type from URL
  static StreamType _detectStreamType(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('.m3u8')) {
      return StreamType.hls;
    } else if (lowerUrl.contains('.mpd')) {
      return StreamType.dash;
    } else if (lowerUrl.startsWith('magnet:')) {
      return StreamType.torrent;
    }
    return StreamType.direct;
  }

  /// Parse quality label to StreamQuality enum
  /// Returns StreamQuality.unknown on parse failure for graceful degradation
  static StreamQuality _parseQuality(String? label) {
    if (label == null || label.isEmpty) return StreamQuality.unknown;

    try {
      final normalized = label.toLowerCase().replaceAll('p', '').trim();
      switch (normalized) {
        case '360':
          return StreamQuality.q360p;
        case '480':
          return StreamQuality.q480p;
        case '720':
          return StreamQuality.q720p;
        case '1080':
          return StreamQuality.q1080p;
        case '1440':
        case '2k':
          return StreamQuality.q1440p;
        case '2160':
        case '4k':
          return StreamQuality.q4k;
        default:
          // Try parsing as integer for non-standard quality labels
          final parsed = int.tryParse(normalized);
          if (parsed != null) {
            if (parsed <= 360) return StreamQuality.q360p;
            if (parsed <= 480) return StreamQuality.q480p;
            if (parsed <= 720) return StreamQuality.q720p;
            if (parsed <= 1080) return StreamQuality.q1080p;
            if (parsed <= 1440) return StreamQuality.q1440p;
            return StreamQuality.q4k;
          }
          return StreamQuality.unknown;
      }
    } catch (_) {
      return StreamQuality.unknown;
    }
  }

  /// Decode PlayerJS encoded strings
  ///
  /// PlayerJS sometimes uses custom encoding (base64 variants, character shifts, etc.)
  /// This method tries multiple decoding strategies with graceful fallback
  static String? _decodePlayerJsString(String encoded) {
    if (encoded.isEmpty) return null;

    // Try standard base64 first
    try {
      final decoded = utf8.decode(base64.decode(encoded));
      if (decoded.contains('http')) {
        Logger.d('Decoded with standard base64', tag: _tag);
        return decoded;
      }
    } catch (_) {
      // Continue to next method
    }

    // Try URL-safe base64
    try {
      final normalized = encoded.replaceAll('-', '+').replaceAll('_', '/');
      // Pad if needed
      final padded = normalized.padRight((normalized.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64.decode(padded));
      if (decoded.contains('http')) {
        Logger.d('Decoded with URL-safe base64', tag: _tag);
        return decoded;
      }
    } catch (_) {
      // Continue to next method
    }

    // Try character shift decoding (some sites use ROT-like encoding)
    for (final shift in [-13, -3, 3, 13]) {
      try {
        final shifted = _caesarShift(encoded, shift);
        if (shifted.contains('http')) {
          Logger.d('Decoded with Caesar shift ($shift)', tag: _tag);
          return shifted;
        }
      } catch (_) {
        // Continue to next shift
      }
    }

    // Try hex decoding
    try {
      if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(encoded) &&
          encoded.length % 2 == 0) {
        final bytes = <int>[];
        for (var i = 0; i < encoded.length; i += 2) {
          bytes.add(int.parse(encoded.substring(i, i + 2), radix: 16));
        }
        final decoded = utf8.decode(bytes);
        if (decoded.contains('http')) {
          Logger.d('Decoded with hex', tag: _tag);
          return decoded;
        }
      }
    } catch (_) {
      // Continue
    }

    Logger.w('Could not decode PlayerJS string (tried all methods)', tag: _tag);
    return null;
  }

  /// Simple ROT/Caesar shift for string decoding
  static String _caesarShift(String input, int shift) {
    return String.fromCharCodes(input.codeUnits.map((c) => c + shift));
  }
}
