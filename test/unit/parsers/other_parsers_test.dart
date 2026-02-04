import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/uaserials_parser.dart';
import 'package:oxide_film/data/parsers/uaflix_parser.dart';
import 'package:oxide_film/data/parsers/hdrezka_parser.dart';

void main() {
  group('UaserialsParser', () {
    test('parseList should extract items', () {
      const html = '''
        <div class="short-item">
          <a href="/series/123-test-series.html" class="short-img">
            <img src="/poster.jpg" alt="Test Series" />
          </a>
          <div class="th-title">Test Series</div>
          <div class="th-title-oname">Original Name</div>
          <span class="rating">8.2</span>
        </div>
      ''';

      final results = UaserialsParser.parseList(html);

      expect(results.length, 1);
      expect(results[0].title, 'Test Series');
      expect(results[0].id, 'series/123-test-series');
      expect(results[0].rating, 8.2);
    });
  });

  group('UaflixParser', () {
    test('parseSearchResults should extract items', () {
      const html = '''
        <a href="/films/123-test-movie.html" class="sres-wrap">
          <div class="sres-img">
            <img src="/poster.jpg" alt="Movie (2024)" />
          </div>
        </a>
      ''';

      final results = UaflixParser.parseSearchResults(html);

      expect(results.length, 1);
      expect(results[0].title, 'Movie');
      expect(results[0].year, 2024);
      expect(results[0].id, 'films/123-test-movie');
    });
  });

  group('HDRezkaParser', () {
    test('parseSearchResults should extract items', () {
      const html = '''
        <div class="b-content__inline_item">
          <div class="b-content__inline_item-link">
            <a href="https://hdrezka.ag/films/action/123-movie.html">Action Movie</a>
          </div>
          <img src="/poster.jpg" alt="Action Movie" />
          <div class="misc">2023, USA, Action</div>
        </div>
      ''';

      final results = HDRezkaParser.parseSearchResults(html, 'hdrezka');

      expect(results.length, 1);
      expect(results[0].title, 'Action Movie');
      expect(results[0].year, 2023);
      expect(results[0].country, 'USA');
    });

    test('decodeStreamUrl should handle HDRezka encoding', () {
      // Testing simple base64 first to verify the cleaner logic
      const encoded =
          '#h'
          'aHR0cHM6Ly9leGFtcGxlLmNvbS92aWRlby5tcDQ='; // "https://example.com/video.mp4"
      final decoded = HDRezkaParser.decodeStreamUrl(encoded);
      expect(decoded, 'https://example.com/video.mp4');
    });
  });
}
