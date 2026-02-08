import 'dart:io';
import 'package:oxide_film/data/parsers/uaflix_parser.dart';

void main() async {
  final file = File(
    'test/uaflix_debug_serials_gra-v-kalmara-viprobuvannja-squid-game-the-challenge.html',
  );
  if (!await file.exists()) {
    print('File not found');
    return;
  }

  final html = await file.readAsString();

  print('--- Testing extractIframeSrcs ---');
  final iframes = UaflixParser.extractIframeSrcs(html);
  print('Found ${iframes.length} iframes');
  for (var src in iframes) {
    print('Iframe: $src');
  }

  print('\n--- Testing extractVideoSrcs ---');
  final videos = UaflixParser.extractVideoSrcs(html);
  print('Found ${videos.length} videos');
  for (var src in videos) {
    print('Video: $src');
  }

  print('\n--- Analysis ---');
  if (iframes.isEmpty && videos.isEmpty) {
    print(
      'FAIL: No sources found. The parser is unable to handle the current HTML structure.',
    );

    // Simple check for AMSP presence
    if (html.contains('AMSP')) {
      print(
        'Detected AMSP script in HTML. This likely indicates a new protection/player loader.',
      );
    }
  } else {
    print('SUCCESS: Sources found.');
  }
}
