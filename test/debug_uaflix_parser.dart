import 'dart:io';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:oxide_film/data/parsers/uaflix_parser.dart';

void main() {
  final file = File('test/uafix_dorama_page1.html');
  if (!file.existsSync()) {
    print('Error: test/uafix_dorama_page1.html not found');
    return;
  }

  final html = file.readAsStringSync();
  print('HTML length: ${html.length}');

  final soup = BeautifulSoup(html);

  // Test detection of video-item
  final cards = soup.findAll('div', class_: 'video-item');
  print('Found ${cards.length} cards with class "video-item"');

  if (cards.isNotEmpty) {
    print('First card classes: ${cards.first.attributes['class']}');
  }

  // Test actual parser
  final items = UaflixParser.parseSearchResults(html);
  print('Parsed ${items.length} items');

  for (var item in items) {
    print('Item: ${item.title} (${item.year}) [${item.type}] - ${item.id}');
  }
}
