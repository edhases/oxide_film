/// Integration tests for provider workflows
///
/// These tests verify end-to-end functionality of providers
/// using real network calls (when not mocked).
///
/// Run with: flutter test test/integration/

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uakino_provider.dart';
import 'package:oxide_film/data/providers/filmix_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

/// Note: These tests make real network requests.
/// Skip them in CI or when network is unavailable.
void main() {
  group('Integration: UakinoProvider', () {
    late UakinoProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = UakinoProvider(client);
    });

    test(
      'getPopular should return movies',
      () async {
        final movies = await provider.getPopular(
          type: ContentType.movie,
          page: 1,
        );

        expect(movies, isNotEmpty);
        expect(movies.every((m) => m.title.isNotEmpty), isTrue);
        expect(movies.every((m) => m.id.isNotEmpty), isTrue);
      },
      skip: 'Integration test - requires network',
    );

    test(
      'getPopular should return series',
      () async {
        final series = await provider.getPopular(
          type: ContentType.series,
          page: 1,
        );

        expect(series, isNotEmpty);
      },
      skip: 'Integration test - requires network',
    );

    test('search should find content', () async {
      final results = await provider.search('Вартові');

      expect(results, isNotEmpty);
    }, skip: 'Integration test - requires network');

    test(
      'getDetails should return full info',
      () async {
        // First get a movie
        final movies = await provider.getPopular(
          type: ContentType.movie,
          page: 1,
        );

        if (movies.isEmpty) {
          fail('No movies found');
        }

        final details = await provider.getDetails(movies.first.id);

        expect(details.item.title, isNotEmpty);
      },
      skip: 'Integration test - requires network',
    );

    test(
      'getStreams should return playable sources',
      () async {
        final movies = await provider.getPopular(
          type: ContentType.movie,
          page: 1,
        );

        if (movies.isEmpty) {
          fail('No movies found');
        }

        final streams = await provider.getStreams(movies.first.id);

        // At least one stream should be available
        expect(streams, isNotEmpty);
        expect(streams.every((s) => s.url.isNotEmpty), isTrue);
        expect(streams.every((s) => s.url.startsWith('http')), isTrue);
      },
      skip: 'Integration test - requires network',
    );
  });

  group('Integration: FilmixProvider', () {
    late FilmixProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = FilmixProvider(client);
    });

    test(
      'getPopular should return content',
      () async {
        final content = await provider.getPopular(
          type: ContentType.movie,
          page: 1,
        );

        expect(content, isNotEmpty);
      },
      skip: 'Integration test - requires network',
    );

    test(
      'pagination should work correctly',
      () async {
        final page1 = await provider.getPopular(
          type: ContentType.movie,
          page: 1,
        );
        final page2 = await provider.getPopular(
          type: ContentType.movie,
          page: 2,
        );

        expect(page1, isNotEmpty);
        expect(page2, isNotEmpty);

        // Pages should have different content
        final page1Ids = page1.map((m) => m.id).toSet();
        final page2Ids = page2.map((m) => m.id).toSet();
        expect(page1Ids.intersection(page2Ids), isEmpty);
      },
      skip: 'Integration test - requires network',
    );
  });

  group('Stream URL Validation', () {
    test('HLS URL should be valid', () {
      const hlsUrl = 'https://example.com/video.m3u8';
      expect(hlsUrl.contains('.m3u8'), isTrue);
    });

    test('MP4 URL should be valid', () {
      const mp4Url = 'https://example.com/video.mp4';
      expect(mp4Url.contains('.mp4'), isTrue);
    });

    test('should detect stream type from URL', () {
      const hlsUrl = 'https://example.com/stream/video.m3u8';
      const mp4Url = 'https://example.com/stream/video.mp4';

      expect(
        hlsUrl.contains('.m3u8') ? StreamType.hls : StreamType.direct,
        StreamType.hls,
      );

      expect(
        mp4Url.contains('.m3u8') ? StreamType.hls : StreamType.direct,
        StreamType.direct,
      );
    });
  });
}
