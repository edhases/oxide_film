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

    test('getPopular should return unique anime with metadata', () async {
      final items = await provider.getPopular(type: ContentType.anime, page: 1);

      expect(items, isNotEmpty);

      // 1. Deduplication check
      final ids = items.map((e) => e.id).toList();
      final uniqueIds = ids.toSet();
      expect(
        ids.length,
        equals(uniqueIds.length),
        reason: 'Duplicate items found in results',
      );

      // 2. Metadata check (Year and Rating)
      bool foundYear = false;
      bool foundRating = false;

      for (final item in items) {
        if (item.year != null && item.year! > 2000) foundYear = true;
        if (item.rating != null && item.rating! > 0) foundRating = true;

        expect(item.title, isNotEmpty);
        expect(item.id, isNotEmpty);
        expect(item.posterUrl, startsWith('http'));
      }

      expect(foundYear, isTrue, reason: 'No items with year found');
      expect(foundRating, isTrue, reason: 'No items with rating found');
    });

    test('getDetails should return full info and correct seasons', () async {
      final items = await provider.getPopular(type: ContentType.anime, page: 1);
      if (items.isEmpty) fail('No items found');

      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.id, equals(item.id));
      expect(details.item.title, isNotEmpty);

      if (details.seasons != null && details.seasons!.isNotEmpty) {
        expect(details.seasons!.first.episodes, isNotEmpty);
        for (final ep in details.seasons!.first.episodes) {
          expect(ep.number, isPositive);
          expect(ep.title, isNotEmpty);
        }
      }
    });

    test(
      'getStreams should return available sources from multiple players',
      () async {
        // Find a specific anime known to have multiple players (like Adskij Raj or similar ongoing)
        // Or just try the first few from popular
        final items = await provider.getPopular(
          type: ContentType.anime,
          page: 1,
        );
        if (items.isEmpty) fail('No items found');

        bool foundMultiSource = false;

        for (var i = 0; i < 5 && i < items.length; i++) {
          try {
            final streams = await provider.getStreams(items[i].id);
            if (streams.isNotEmpty) {
              expect(streams.every((s) => s.url.isNotEmpty), isTrue);

              // Checking if we found multiple sources (Kodik, Ashdi, etc.)
              final sourceNames = streams
                  .map((s) => s.sourceName)
                  .whereType<String>()
                  .toSet();
              if (sourceNames.length > 1) {
                foundMultiSource = true;
              }

              // If we found any streams, we at least verified basic fetching
              if (foundMultiSource) break;
            }
          } catch (e) {
            // ignore errors in loop
          }
        }

        expect(
          foundMultiSource,
          isTrue,
          reason:
              'Expected to find at least one anime with multiple stream sources',
        );
      },
    );
  });
}
