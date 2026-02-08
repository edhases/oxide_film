/// Integration tests for UAFlix provider
///
/// Run with: flutter test test/integration/uaflix_provider_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uaflix_provider.dart';
import 'package:oxide_film/data/services/user_agent_service.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  group('Integration: UaflixProvider', () {
    late UaflixProvider provider;
    late ApiClient client;

    setUp(() {
      client = ApiClient(uaService: MockUserAgentService());
      provider = UaflixProvider(client);
    });

    test('getPopular should return items', () async {
      final items = await provider.getPopular(type: ContentType.movie, page: 1);

      expect(items, isNotEmpty);
      expect(items.first.title, isNotEmpty);
      expect(items.first.id, isNotEmpty);
    });

    test('search should find content and clean titles', () async {
      // Known movie that likely has SEO suffix
      final results = await provider.search('Месники');

      expect(results, isNotEmpty);
      final item = results.first;

      // Check that title is clean (no "дивитись онлайн" etc)
      expect(item.title.toLowerCase(), isNot(contains('дивитись')));
      expect(item.title.toLowerCase(), isNot(contains('онлайн')));
    });

    test('getDetails should return sanitized description', () async {
      final popular = await provider.getPopular();
      if (popular.isEmpty) fail('No popular items found');

      final details = await provider.getDetails(popular.first.id);

      expect(details.fullDescription, isNotNull);
      final desc = details.fullDescription!;

      // Check for script tags
      expect(desc, isNot(contains('<script')));
      expect(desc, isNot(contains('function(')));
      expect(desc, isNot(contains('var ')));

      // Check for pagination numbers leakage (rough check)
      expect(desc, isNot(matches(r'\n\s*1\s*2\s*3')));

      // Check title cleaning in details too
      expect(
        details.item.title.toLowerCase(),
        isNot(contains('дивитись онлайн')),
      );

      // Check metadata
      // Note: some items might legitimately miss this data, but popular ones usually have it
      // expect(details.year, isNotNull);
      // expect(details.countries, isNotEmpty);
    });
  });
}

class MockUserAgentService extends Fake implements UserAgentService {
  @override
  String getRandomUA() => 'Mozilla/5.0 (Test Agent)';

  @override
  List<String> get userAgents => ['Mozilla/5.0 (Test Agent)'];
}
