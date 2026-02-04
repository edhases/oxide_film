import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/youtube_provider.dart';

void main() {
  group('Integration: YouTubeProvider', () {
    late YouTubeProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = YouTubeProvider(client);
    });

    test('search should return videos', () async {
      // Search for something safe and popular
      final items = await provider.search('Flutter Framework', page: 1);

      expect(items, isNotEmpty);
      expect(items.every((m) => m.title.isNotEmpty), isTrue);
      expect(items.every((m) => m.id.isNotEmpty), isTrue);
    });

    test('getDetails should return info', () async {
      // Use a known video ID (e.g. Flutter generic) or search result
      final items = await provider.search('Flutter', page: 1);
      if (items.isEmpty) fail('No items found');

      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.id, equals(item.id));
      expect(details.item.title, isNotEmpty);
    });

    test('getStreams should return sources', () async {
      final items = await provider.search('Flutter', page: 1);
      if (items.isEmpty) fail('No items found');

      final item = items.first;
      final streams = await provider.getStreams(item.id);

      expect(streams, isNotEmpty);
      // On desktop should find direct streams, otherwise embed
    });
  });
}
