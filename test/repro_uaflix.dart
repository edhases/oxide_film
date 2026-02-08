import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/repositories/uaflix_repository.dart';
import 'package:oxide_film/data/services/user_agent_service.dart';

class MockUserAgentService extends Mock implements UserAgentService {}

void main() {
  late ApiClient client;
  late UaflixRepository repository;
  late MockUserAgentService mockUaService;

  setUp(() {
    mockUaService = MockUserAgentService();
    when(() => mockUaService.getRandomUA()).thenReturn(
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    );
    client = ApiClient(uaService: mockUaService);
    repository = UaflixRepository(client);
  });

  test('Reproduction: No sources for specific titles', () async {
    final titlesToTest = ['Гра в кальмара', 'Лінкольн для адвоката'];

    for (final title in titlesToTest) {
      print('\n--- Testing: $title ---');
      final results = await repository.search(title);
      if (results.isEmpty) {
        print('No results found for "$title"');
        continue;
      }

      final item = results.first;
      print('Found: ${item.title} (ID: ${item.id})');

      final streams = await repository.getStreams(item.id);
      print('Streams found: ${streams.length}');
      for (final stream in streams) {
        print('- ${stream.quality}: ${stream.url}');
      }

      if (streams.isEmpty) {
        print('❌ NO SOURCES FOUND for $title');
        // Fetch and save HTML for analysis
        try {
          // We need to construct URL same as repository does
          final url = 'https://uafix.net/${item.id}/';
          final html = await client.get(url);
          final file = io.File(
            'test/uaflix_debug_${item.id.replaceAll('/', '_')}.html',
          );
          await file.writeAsString(html);
          print('Saved HTML to ${file.path}');
        } catch (e) {
          print('Failed to save HTML: $e');
        }
      } else {
        print('✅ Sources found for $title');
      }
    }
  });

  test('Reproduction: Pagination / Load More', () async {
    print('\n--- Testing Pagination ---');
    final category = 'films/new_netflix_ua';

    print('Fetching page 1...');
    final page1 = await repository.getByCategory(category, page: 1);
    print('Page 1 items: ${page1.length}');
    for (final item in page1.take(3)) {
      print('- ${item.title}');
    }

    print('Fetching page 2...');
    final page2 = await repository.getByCategory(category, page: 2);
    print('Page 2 items: ${page2.length}');
    for (final item in page2.take(3)) {
      print('- ${item.title}');
    }

    if (page2.isEmpty) {
      print('❌ Page 2 is empty! Pagination might be broken.');
    } else if (page1.isNotEmpty &&
        page2.isNotEmpty &&
        page1.first.id == page2.first.id) {
      print('❌ Page 2 has same content as Page 1! Pagination ignored.');
    } else {
      print('✅ Pagination seems to work (different content on page 2).');
    }
  });
}
