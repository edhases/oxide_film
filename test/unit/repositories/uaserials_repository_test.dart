import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oxide_film/data/repositories/uaserials_repository.dart';
import 'package:oxide_film/core/network/api_client.dart';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('UaserialsRepository.search returns parsed items from HTML', () async {
    final mockClient = _MockApiClient();
    final repo = UaserialsRepository(mockClient);

    final html = await File(
      'test/fixtures/parsers/uaserials_sample.html',
    ).readAsString();

    when(() => mockClient.get(any())).thenAnswer((_) async => html);

    final results = await repo.search('query');

    expect(results, isNotEmpty);
    expect(results.first.providerId, 'uaserials');
    verify(() => mockClient.get(any())).called(1);
  });

  test('UaserialsRepository.getDetails parses details correctly', () async {
    final mockClient = _MockApiClient();
    final repo = UaserialsRepository(mockClient);

    final html = await File(
      'test/fixtures/parsers/uaserials_sample.html',
    ).readAsString();
    when(() => mockClient.get(any())).thenAnswer((_) async => html);

    final details = await repo.getDetails('some-id');

    expect(details.item.title.isNotEmpty, isTrue);
    verify(() => mockClient.get(any())).called(1);
  });
}
