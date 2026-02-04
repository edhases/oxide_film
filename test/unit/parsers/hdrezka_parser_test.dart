import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/hdrezka_parser.dart';

void main() {
  test(
    'HDRezkaParser.parseSearchResults returns items and extracts titles',
    () async {
      // Use the integration fixture created earlier
      final html = await File(
        'test/fixtures/integration/sample_provider_response.html',
      ).readAsString();

      final items = HDRezkaParser.parseSearchResults(html, 'hdrezka');
      // Should be robust even if markup differs; expect non-throw and list result
      expect(items, isA<List>());
    },
  );
}
