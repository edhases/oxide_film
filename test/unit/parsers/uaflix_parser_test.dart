import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/uaflix_parser.dart';

void main() {
  test(
    'UaflixParser.parseSearchResults handles search cards and video items',
    () async {
      final html = await File(
        'test/fixtures/parsers/uaflix_sample.html',
      ).readAsString();

      final items = UaflixParser.parseSearchResults(html);

      expect(items, isNotEmpty);
      // We expect at least two items from fixture
      expect(items.length >= 2, isTrue);

      final first = items.firstWhere(
        (i) => i.id.isNotEmpty,
        orElse: () => items.first,
      );
      expect(first.title.isNotEmpty, isTrue);
      expect(first.providerId, 'uaflix');
    },
  );
}
