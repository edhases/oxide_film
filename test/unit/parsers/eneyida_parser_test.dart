import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/eneyida_parser.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('EneyidaParser', () {
    test('parseCatalog should extract items from valid HTML', () {
      const html = '''
        <article class="short">
          <a href="/films/drama/123-test-movie.html" class="short_img">
            <img src="/poster.jpg" />
          </a>
          <a href="/films/drama/123-test-movie.html" class="short_title">Test Movie Eneyida</a>
          <div class="short_info">2024, USA</div>
        </article>
      ''';

      final results = EneyidaParser.parseCatalog(html);

      expect(results.length, 1);
      expect(results[0].title, 'Test Movie Eneyida');
      expect(results[0].id, 'films/drama/123-test-movie');
      expect(results[0].year, 2024);
      expect(results[0].type, ContentType.movie);
    });

    test('parseDetails should extract full info', () {
      const html = '''
        <h1 class="full_title">Test Movie Detailed Eneyida</h1>
        <div class="full_poster"><img src="/uploads/posts/poster.jpg" /></div>
        <div class="full_text">This is a great movie description from Eneyida. It is long enough to be valid.</div>
        <div class="full_info">
          <div class="full_info-item">
            <span class="fi-label">Рік:</span>
            <span class="fi-value">2023</span>
          </div>
          <div class="full_info-item">
            <span class="fi-label">Режисер:</span>
            <span class="fi-value">Jane Doe</span>
          </div>
          <div class="full_info-item">
            <span class="fi-label">Актори:</span>
            <span class="fi-value"><a>Actor A</a>, <a>Actor B</a></span>
          </div>
        </div>
        <span class="full_rating">8.9</span>
      ''';

      final details = EneyidaParser.parseDetails(html, 'films/123-test');

      expect(details.item.title, 'Test Movie Detailed Eneyida');
      expect(details.item.year, 2023);
      expect(details.director, 'Jane Doe');
      expect(details.actors, containsAll(['Actor A', 'Actor B']));
      expect(details.item.rating, 8.9);
      expect(details.fullDescription, contains('great movie description'));
    });

    test('parseAjaxPlaylist should extract stream sources', () {
      const html = '''
        <li data-file="https://example.com/stream1.m3u8" data-voice="UA" data-season="1" data-episode="1">Episode 1</li>
        <li data-file="https://example.com/stream2.m3u8" data-voice="UA" data-season="1" data-episode="2">Episode 2</li>
      ''';

      final sources = EneyidaParser.parseAjaxPlaylist(html);

      expect(sources.length, 2);
      expect(sources[0].url, 'https://example.com/stream1.m3u8');
      expect(sources[0].voiceover, 'UA');
      expect(sources[0].season, 1);
      expect(sources[0].episode, 1);
    });
  });
}
