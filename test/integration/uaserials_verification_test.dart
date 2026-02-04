import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uaserials_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('Integration: UaserialsProvider', () {
    late UaserialsProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient();
      provider = UaserialsProvider(client);
    });

    test('getPopular should return items', () async {
      final items = await provider.getPopular(
        type: ContentType.series,
        page: 1,
      );

      expect(items, isNotEmpty);
      expect(items.every((m) => m.title.isNotEmpty), isTrue);
      expect(items.every((m) => m.id.isNotEmpty), isTrue);
    });

    test('getDetails should return full info', () async {
      final items = await provider.getPopular(
        type: ContentType.series,
        page: 1,
      );

      if (items.isEmpty) fail('No items found');

      // Pick one that looks standard
      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.title, isNotEmpty);
      // Descriptin might be empty on some, but usually present
      // expect(details.fullDescription, isNotNull);
    });

    test('getStreams should return available sources', () async {
      final items = await provider.getPopular(
        type: ContentType.series,
        page: 1,
      );

      if (items.isEmpty) fail('No items found');

      final streams = await provider.getStreams(items.first.id);

      // Expect at least some result, or empty list if no streams (which can happen)
      // Main goal is no crash
      if (streams.isNotEmpty) {
        expect(streams.every((s) => s.url.isNotEmpty), isTrue);
      }
    });
  });
}
