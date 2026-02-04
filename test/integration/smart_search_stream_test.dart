import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/services/search_service.dart';
import 'package:oxide_film/data/services/smart_search/smart_search_service.dart';
import 'package:oxide_film/domain/entities/entities.dart';
import 'package:oxide_film/data/providers/provider_registry.dart';
import 'package:oxide_film/data/database/dao/search_history_dao.dart';
import 'package:oxide_film/data/database/app_database.dart';

// Manual Mocks
class MockSearchService extends Fake implements SearchService {
  @override
  Stream<AggregatedSearchResult> searchStream(
    String query, {
    ContentType? type,
    int page = 1,
  }) {
    final controller = StreamController<AggregatedSearchResult>();

    // Emit Fast Result (10ms)
    // We use a microtask or simple delayed future in test env
    Future.delayed(const Duration(milliseconds: 10), () {
      if (controller.isClosed) return;
      controller.add(
        AggregatedSearchResult(
          query: query,
          providerResults: [
            ProviderSearchResult(
              providerId: 'fast',
              providerName: 'Fast',
              items: [
                MediaItem(
                  id: 'fast:1',
                  title: 'The Matrix Fast',
                  type: ContentType.movie,
                  providerId: 'fast',
                ),
              ],
              searchDuration: const Duration(milliseconds: 10),
            ),
          ],
          totalDuration: const Duration(milliseconds: 10),
          isComplete: false,
        ),
      );
    });

    // Emit Slow Result (200ms)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (controller.isClosed) return;
      controller.add(
        AggregatedSearchResult(
          query: query,
          providerResults: [
            ProviderSearchResult(
              providerId: 'fast',
              providerName: 'Fast',
              items: [
                MediaItem(
                  id: 'fast:1',
                  title: 'The Matrix Fast',
                  type: ContentType.movie,
                  providerId: 'fast',
                ),
              ],
              searchDuration: const Duration(milliseconds: 10),
            ),
            ProviderSearchResult(
              providerId: 'slow',
              providerName: 'Slow',
              items: [
                MediaItem(
                  id: 'slow:1',
                  title: 'The Matrix Slow',
                  type: ContentType.movie,
                  providerId: 'slow',
                ),
              ],
              searchDuration: const Duration(milliseconds: 200),
            ),
          ],
          totalDuration: const Duration(milliseconds: 200),
          isComplete: true,
        ),
      );
      controller.close();
    });

    return controller.stream;
  }

  @override
  Future<List<MediaItem>> getSuggestions(
    String query, {
    int maxPerProvider = 3,
    int maxTotal = 10,
  }) async => [];
}

class MockProviderRegistry extends Fake implements ProviderRegistry {}

class MockSearchHistoryDao extends Fake implements SearchHistoryDao {
  @override
  Future<void> addSearch({
    required String query,
    required String normalizedQuery,
    required int resultCount,
  }) async {}

  @override
  Future<List<SearchHistoryTableData>> searchByPrefix(
    String prefix, {
    int limit = 10,
  }) async => [];

  @override
  Future<List<SearchHistoryTableData>> getSuccessful({int limit = 20}) async =>
      [];

  @override
  Future<List<SearchHistoryTableData>> getRecent({int limit = 100}) async => [];
}

void main() {
  group('SmartSearchService Streaming', () {
    late SmartSearchService service;
    late MockSearchService mockSearchService;
    late MockProviderRegistry mockRegistry;
    late MockSearchHistoryDao mockHistoryDao;

    setUp(() {
      mockSearchService = MockSearchService();
      mockRegistry = MockProviderRegistry();
      mockHistoryDao = MockSearchHistoryDao();
      service = SmartSearchService(
        mockSearchService,
        mockRegistry,
        mockHistoryDao,
      );
    });

    test('should emit partial results progressively', () async {
      final query = 'Matrix';
      final stream = service.search(query);
      final events = <SmartSearchResult>[];

      await for (final event in stream) {
        events.add(event);
      }

      // Verify
      // Expect at least 2 events (partial and full)
      expect(events.length, greaterThanOrEqualTo(2));

      // First event should have 1 item (Fast)
      final first = events.first;
      expect(
        first.rankedItems.length,
        1,
        reason: 'First event should be from fast provider',
      );
      expect(first.rankedItems.first.title, 'The Matrix Fast');

      // Last event should have 2 items (Fast + Slow)
      final last = events.last;
      expect(
        last.rankedItems.length,
        2,
        reason: 'Last event should be combined',
      );
      expect(last.rankedItems.any((i) => i.title == 'The Matrix Slow'), isTrue);
    });
  });
}
