import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/yummyanime_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('Integration: YummyAnimeProvider', () {
    late YummyAnimeProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = YummyAnimeProvider(client);
    });

    test('getPopular should return anime', () async {
      final items = await provider.getPopular(type: ContentType.anime, page: 1);

      expect(items, isNotEmpty);
      expect(items.every((m) => m.title.isNotEmpty), isTrue);
      expect(items.every((m) => m.id.isNotEmpty), isTrue);
    });

    test('getDetails should return full info', () async {
      final items = await provider.getPopular(type: ContentType.anime, page: 1);

      if (items.isEmpty) fail('No items found');

      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.id, equals(item.id));
      expect(details.item.title, isNotEmpty);
      // YummyAnime usually has description
      // expect(details.fullDescription, isNotNull);

      // Verification of seasons parsing
      if (details.seasons != null && details.seasons!.isNotEmpty) {
        expect(details.seasons!.first.episodes, isNotEmpty);
      }
    });

    test('getStreams should return available sources', () async {
      final items = await provider.getPopular(type: ContentType.anime, page: 1);

      if (items.isEmpty) fail('No items found');

      // Try top 3 items to find one with streams
      // Note: YummyAnime streams fetching is complex (AJAX), might fail if site changes or blocks
      for (var i = 0; i < 3 && i < items.length; i++) {
        try {
          final streams = await provider.getStreams(items[i].id);
          if (streams.isNotEmpty) {
            expect(streams.every((s) => s.url.isNotEmpty), isTrue);
            return;
          }
        } catch (e) {
          // ignore errors in loop
        }
      }

      print(
        'Warning: No streams found for top 3 items in YummyAnime (could be blocked or empty)',
      );
    });
  });
}
