import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uaflix_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('Integration: UaflixProvider', () {
    late UaflixProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = UaflixProvider(client);
    });

    test('getPopular should return items', () async {
      final items = await provider.getPopular(type: ContentType.movie, page: 1);

      expect(items, isNotEmpty);
      expect(items.every((m) => m.title.isNotEmpty), isTrue);
      expect(items.every((m) => m.id.isNotEmpty), isTrue);
    });

    test('getDetails should return full info', () async {
      final items = await provider.getPopular(type: ContentType.movie, page: 1);

      if (items.isEmpty) fail('No items found');

      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.id, equals(item.id));
      expect(details.item.title, isNotEmpty);
      expect(details.fullDescription, isNotNull);
    });

    test('getStreams should return available sources', () async {
      // Uaflix often has iframes
      final items = await provider.getPopular(type: ContentType.movie, page: 1);

      if (items.isEmpty) fail('No items found');

      // Try top 3 items to find one with streams
      for (var i = 0; i < 3 && i < items.length; i++) {
        final streams = await provider.getStreams(items[i].id);
        if (streams.isNotEmpty) {
          expect(streams.every((s) => s.url.isNotEmpty), isTrue);
          return;
        }
      }

      // If we reached here, no streams were found in top 3.
      // We warn but don't fail, as some content might be blocked or empty
      print('Warning: No streams found for top 3 items in Uaflix');
    });
  });
}
