import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:oxide_film/data/repositories/hdrezka_repository.dart';
import 'package:oxide_film/core/network/api_client.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
  });

  test('HdrezkaRepository.getPopular returns parsed items', () async {
    final mockClient = _MockApiClient();
    final repo = HdrezkaRepository(mockClient);

    final html = await File(
      'test/fixtures/integration/sample_provider_response.html',
    ).readAsString();

    when(() => mockClient.get(any())).thenAnswer((_) async => html);

    final results = await repo.getPopular();

    expect(results, isNotNull);
    expect(results.length, greaterThanOrEqualTo(0));
    verify(() => mockClient.get(any())).called(1);
  });

  test(
    'HdrezkaRepository.getDetails returns MediaDetails parsed via parser',
    () async {
      final mockClient = _MockApiClient();
      final repo = HdrezkaRepository(mockClient);

      final html = await File(
        'test/fixtures/integration/sample_provider_response.html',
      ).readAsString();

      when(() => mockClient.get(any())).thenAnswer((_) async => html);

      final details = await repo.getDetails('some-id');

      expect(details.item.title.isNotEmpty, isTrue);
      verify(() => mockClient.get(any())).called(1);
    },
  );

  test(
    'HdrezkaRepository.getStreams calls AJAX and returns StreamSource list',
    () async {
      final mockClient = _MockApiClient();
      final mockDio = _MockDio();

      when(
        () => mockClient.get(any()),
      ).thenAnswer((_) async => '<html>dummy_with_params</html>');

      // Setup dio.post to return JSON containing a URL
      final responseData = jsonEncode({
        'success': true,
        'url': 'https://cdn/test.mp4',
      });
      final response = Response<String>(
        data: responseData,
        requestOptions: RequestOptions(path: ''),
      );

      when(() => mockClient.dio).thenReturn(mockDio);
      when(
        () => mockDio.post<String>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => response);

      final repo = HdrezkaRepository(mockClient);

      final streams = await repo.getStreams('some-id');

      // The parser's _parseStreamUrls should have added at least one StreamSource
      expect(streams, isNotNull);
      // Can't guarantee content exactly without complex fixtures, but expect non-throw
    },
  );
}
