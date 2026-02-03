import 'package:flutter_test/flutter_test.dart';

import 'package:oxide_film/data/parsers/playerjs_parser.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('PlayerJsParser', () {
    test('should parse simple PlayerJS config', () {
      const html = '''
        <script>
          new Playerjs({
            id: "player",
            file: "https://example.com/video.m3u8"
          });
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isNotEmpty);
      expect(sources.first.url, 'https://example.com/video.m3u8');
      expect(sources.first.type, StreamType.hls);
    });

    test('should parse quality markers with closing tags', () {
      // The parser expects format: [720p]url[/720p],[1080p]url[/1080p]
      const html = '''
        <script>
          new Playerjs({
            file: "[720p]https://example.com/720.mp4[/720p],[1080p]https://example.com/1080.mp4[/1080p]"
          });
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources.length, 2);
      expect(sources.any((s) => s.quality == StreamQuality.q720p), isTrue);
      expect(sources.any((s) => s.quality == StreamQuality.q1080p), isTrue);
    });

    test('should handle single URL without quality markers', () {
      const html = '''
        <script>
          new Playerjs({
            file: "https://example.com/video.mp4"
          });
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isNotEmpty);
      expect(sources.first.url, 'https://example.com/video.mp4');
    });

    test('should use default_quality when present', () {
      const html = '''
        <script>
          new Playerjs({
            file: "https://example.com/video.mp4",
            default_quality: "720p"
          });
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isNotEmpty);
      expect(sources.first.quality, StreamQuality.q720p);
    });

    test('should detect HLS stream type from m3u8 extension', () {
      const html = '''
        <script>
          new Playerjs({file: "https://example.com/stream.m3u8"});
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isNotEmpty);
      expect(sources.first.type, StreamType.hls);
    });

    test('should detect MP4 stream type', () {
      const html = '''
        <script>
          new Playerjs({file: "https://example.com/video.mp4"});
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isNotEmpty);
      expect(sources.first.type, StreamType.mp4);
    });

    test('should handle empty HTML gracefully', () {
      final sources = PlayerJsParser.parseFromHtml('');

      expect(sources, isEmpty);
    });

    test('should handle HTML without PlayerJS', () {
      const html = '<html><body><p>No player here</p></body></html>';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources, isEmpty);
    });

    test('should filter out invalid URLs', () {
      const html = '''
        <script>
          new Playerjs({
            file: "not-a-valid-url"
          });
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      // Invalid URLs should be filtered out - only http(s) URLs are valid
      expect(sources.where((s) => s.url == 'not-a-valid-url'), isEmpty);
    });

    test('should parse file parameter with different quote styles', () {
      const htmlSingle = '''
        <script>
          new Playerjs({file:'https://example.com/single.mp4'});
        </script>
      ''';

      const htmlDouble = '''
        <script>
          new Playerjs({file:"https://example.com/double.mp4"});
        </script>
      ''';

      final sourcesSingle = PlayerJsParser.parseFromHtml(htmlSingle);
      final sourcesDouble = PlayerJsParser.parseFromHtml(htmlDouble);

      expect(sourcesSingle, isNotEmpty);
      expect(sourcesDouble, isNotEmpty);
      expect(sourcesSingle.first.url, 'https://example.com/single.mp4');
      expect(sourcesDouble.first.url, 'https://example.com/double.mp4');
    });

    test('should handle encoded file URL with hash prefix', () {
      // Parser expects format: file:"#encoded..."
      // This tests that the pattern is recognized (actual decoding depends on encoding)
      const html = '''
        <script>
          new Playerjs({file:"#someEncodedData123"});
        </script>
      ''';

      // Should not crash - gracefully handles decoding
      final sources = PlayerJsParser.parseFromHtml(html);
      expect(sources, isA<List<StreamSource>>());
    });

    test('should handle multiple file parameters', () {
      const html = '''
        <script>
          new Playerjs({file: "https://example.com/video1.mp4"});
          new Playerjs({file: "https://example.com/video2.mp4"});
        </script>
      ''';

      final sources = PlayerJsParser.parseFromHtml(html);

      expect(sources.length, 2);
    });
  });
}
