import 'package:mocktail/mocktail.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/parsers/uakino_parser.dart';
import 'package:oxide_film/data/parsers/playerjs_parser.dart';
import 'package:oxide_film/data/repositories/uakino_repository.dart';
import 'package:oxide_film/domain/entities/entities.dart';
import 'package:oxide_film/data/services/user_agent_service.dart';

class MockUserAgentService extends Mock implements UserAgentService {}

void main() async {
  final mockUA = MockUserAgentService();
  when(() => mockUA.getRandomUA()).thenReturn(
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  );

  final client = ApiClient(uaService: mockUA);
  final repo = UakinoRepository(client);

  print('Fetching popular items...');
  List<MediaItem> popular = [];
  try {
    popular = await repo.getPopular(page: 1);
  } catch (e) {
    print('Error fetching popular: $e');
    return;
  }

  final item = popular.first;
  print('Selected item: ${item.title} (${item.id})');

  final baseUrl = 'https://uakino.best';
  final url = '$baseUrl/${item.id}.html';
  print('Fetching page: $url');

  try {
    final html = await client.get(url);
    print('Page fetched.');

    // Check iframes
    final iframes = UakinoParser.parseIframeSrcs(html);
    print('Found ${iframes.length} iframes.');

    for (final src in iframes) {
      print('Processing iframe: $src');
      try {
        final iframeHtml = await client.get(src);
        print('Iframe content length: ${iframeHtml.length}');

        // Debug: print PlayerJS config snippet
        final playerJsMatch = RegExp(
          r'Playerjs\((.*?)\)',
          dotAll: true,
        ).firstMatch(iframeHtml);
        if (playerJsMatch != null) {
          print(
            'PlayerJS Config found: ${playerJsMatch.group(1)?.substring(0, 100)}...',
          );
        } else {
          print('No PlayerJS config found directly.');
          // Check for "file:"
          final fileMatch = RegExp(
            'file\\s*:\\s*["\']([^"\']+)["\']',
          ).firstMatch(iframeHtml);
          if (fileMatch != null) {
            print('File param found: ${fileMatch.group(1)}');
          }
        }

        final sources = PlayerJsParser.parseFromHtml(iframeHtml);
        print('Parsed ${sources.length} sources from iframe:');
        for (final s in sources) {
          print(
            '  - Quality: ${s.quality}, Voice: ${s.voiceover}, URL: ${s.url}',
          );
        }
      } catch (e) {
        print('Error fetching/parsing iframe $src: $e');
      }
    }
  } catch (e, s) {
    print('Error: $e');
    print(s);
  }
}
