import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oxide_film/data/repositories/uaflix_repository.dart';
import 'package:oxide_film/core/network/api_client.dart';

import 'dart:io';

class _MockApiClient extends Mock implements ApiClient {}

void main() {
  test('UaflixRepository.search returns parsed results from HTML', () async {
    final mockClient = _MockApiClient();
    final repo = UaflixRepository(mockClient);

    final html = await File(
      'test/fixtures/parsers/uaflix_sample.html',
    ).readAsString();

    when(() => mockClient.get(any())).thenAnswer((_) async => html);

    final results = await repo.search('query');

    expect(results, isNotEmpty);
    expect(results.first.providerId, 'uaflix');
    verify(() => mockClient.get(any())).called(1);
  });
}
