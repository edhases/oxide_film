import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oxide_film/data/parsers/uaserials_parser.dart';

void main() {
  test('UaserialsParser.parseList extracts items and types', () async {
    final html = await File(
      'test/fixtures/parsers/uaserials_sample.html',
    ).readAsString();
    final items = UaserialsParser.parseList(html);

    expect(items, isNotEmpty);
    final item = items.first;
    expect(item.providerId, 'uaserials');
    expect(item.title.isNotEmpty, isTrue);
  });
}
