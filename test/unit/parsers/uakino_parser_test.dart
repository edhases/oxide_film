import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/uakino_parser.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('UakinoParser', () {
    test('parseCatalog should extract items from valid HTML', () {
      const html = '''
        <div class="movie-item">
          <a href="/filmy/drama/123-test-movie.html" class="movie-title">Test Movie</a>
          <img src="/poster.jpg" />
          <div class="movie-year">2024</div>
          <div class="movie-rating">8.5</div>
          <div class="movie-genre"><a>Drama</a>, <a>Action</a></div>
        </div>
      ''';

      final results = UakinoParser.parseCatalog(html);

      expect(results.length, 1);
      expect(results[0].title, 'Test Movie');
      expect(results[0].id, 'filmy/drama/123-test-movie');
      expect(results[0].year, 2024);
      expect(results[0].rating, 8.5);
      expect(results[0].genres, containsAll(['Drama', 'Action']));
      expect(results[0].type, ContentType.movie);
    });

    test('parseDetails should extract full info', () {
      const html = '''
        <h1 class="solototle">Test Movie Detailed</h1>
        <div class="fposter"><img src="/full_poster.jpg" /></div>
        <div class="fdesc">This is a great movie description. It is long enough to be valid.</div>
        <div class="flist">
          <li>Рік: <a href="/y/2023/">2023</a></li>
          <li>Країна: <a href="/c/ua/">Україна</a></li>
          <li>Режисер: <a href="/d/director/">John Doe</a></li>
          <li>Актори: <a href="/a/1/">Actor 1</a>, <a href="/a/2/">Actor 2</a></li>
          <li>Жанр: <a href="/g/1/">Drama</a></li>
        </div>
      ''';

      final details = UakinoParser.parseDetails(html, '123-test');

      expect(details.item.title, 'Test Movie Detailed');
      expect(details.item.year, 2023);
      expect(details.director, 'John Doe');
      expect(details.actors, containsAll(['Actor 1', 'Actor 2']));
      expect(details.genres, contains('Drama'));
      expect(details.fullDescription, contains('great movie description'));
    });

    test('parseAjaxPlaylist should extract stream sources', () {
      const html = '''
        <div class="playlists-videos">
          <li data-file="https://example.com/stream1.m3u8" data-voice="UA" data-id="0_1">Серія 1</li>
          <li data-file="https://example.com/stream2.m3u8" data-voice="UA" data-id="0_2">Серія 2</li>
        </div>
      ''';

      final sources = UakinoParser.parseAjaxPlaylist(html);

      expect(sources.length, 2);
      expect(sources[0].url, 'https://example.com/stream1.m3u8');
      expect(sources[0].voiceover, 'UA');
      expect(sources[0].episode, 1);
      expect(sources[0].type, StreamType.hls);
    });
  });
}
