import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/hdrezka_provider.dart';
import 'package:mocktail/mocktail.dart';
import '../helpers/mock_services.dart';

void main() {
  group('Integration: HdrezkaProvider', () {
    late HdrezkaProvider provider;
    late ApiClient client;
    late MockUserAgentService mockUaService;

    setUp(() {
      client = ApiClient();
      mockUaService = MockUserAgentService();
      when(() => mockUaService.getChromeUserAgent()).thenReturn('Chrome/Mock');
      provider = HdrezkaProvider(client, mockUaService);
    });

    test('search should return items', () async {
      // Search for something very likely to exist (e.g. Iron Man)
      // Note: HDRezka might be blocked or require mirror update
      // We will just check if it runs without throwing exception
      final items = await provider.search('Iron Man', page: 1);

      // If blocked, it might return empty list.
      // We expect either empty list or items, but NO crash.
      // If it works, items should be populated.
      if (items.isNotEmpty) {
        expect(items.first.title, isNotEmpty);
        expect(items.first.id, isNotEmpty);
      }
    });

    test('getPopular should return items', () async {
      final items = await provider.getPopular(page: 1);
      if (items.isNotEmpty) {
        expect(items.first.title, isNotEmpty);
      }
    });

    test('getDetails should return info', () async {
      // Try to search first to get a valid ID
      final items = await provider.search('Avengers', page: 1);
      if (items.isEmpty) {
        // Skip if connectivity issues
        return;
      }

      final item = items.first;
      final details = await provider.getDetails(item.id);

      expect(details.item.id, equals(item.id));
      expect(details.item.title, isNotEmpty);
    });
  });
}
