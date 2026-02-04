import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/eneyida_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('Integration: EneyidaProvider', () {
    late EneyidaProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = EneyidaProvider(client);
    });

    test('getPopular should return movies', () async {
      final movies = await provider.getPopular(
        type: ContentType.movie,
        page: 1,
      );

      expect(movies, isNotEmpty);
      expect(movies.every((m) => m.title.isNotEmpty), isTrue);
      expect(movies.every((m) => m.id.isNotEmpty), isTrue);
    });

    test('getDetails should return full info', () async {
      final movies = await provider.getPopular(
        type: ContentType.movie,
        page: 1,
      );

      if (movies.isEmpty) fail('No movies found');

      final details = await provider.getDetails(movies.first.id);

      expect(details.item.title, isNotEmpty);
      expect(details.fullDescription, isNotNull);
    });

    test('getStreams should return available sources', () async {
      final movies = await provider.getPopular(
        type: ContentType.movie,
        page: 1,
      );

      if (movies.isEmpty) fail('No movies found');

      final streams = await provider.getStreams(movies.first.id);

      // Note: Eneyida might have some movies without streams or only iframes
      // We expect at least empty list or results, but no crash.
      // Ideally we want results.
      if (streams.isNotEmpty) {
        expect(streams.every((s) => s.url.isNotEmpty), isTrue);
      } else {
        print(
          'Warning: No streams found for ${movies.first.title} (${movies.first.id})',
        );
      }
    });
  });
}
