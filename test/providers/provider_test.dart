import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uakino_provider.dart';
import 'package:oxide_film/data/providers/eneyida_provider.dart';
import 'package:oxide_film/data/providers/hdrezka_provider.dart';
import 'package:oxide_film/data/providers/yummyanime_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';
import 'package:oxide_film/domain/repositories/content_provider.dart';
import '../helpers/mock_services.dart';

void main() {
  group('UakinoProvider', () {
    late ApiClient client;
    late UakinoProvider provider;

    setUp(() {
      client = ApiClient();
      provider = UakinoProvider(client);
    });

    test('should have correct metadata', () {
      expect(provider.id, 'uakino');
      expect(provider.name, 'UAKino');
      expect(provider.baseUrl, 'https://uakino.best');
      expect(provider.supportedTypes, contains(ContentType.movie));
      expect(provider.supportedTypes, contains(ContentType.series));
      expect(provider.supportedTypes, contains(ContentType.cartoon));
      expect(provider.supportedTypes, contains(ContentType.anime));
    });

    test('should be enabled by default', () {
      expect(provider.isEnabled, isTrue);
    });

    test('supportedTypes should include all content types', () {
      expect(provider.supportedTypes.length, 4);
    });
  });

  group('EneyidaProvider', () {
    late ApiClient client;
    late EneyidaProvider provider;

    setUp(() {
      client = ApiClient();
      provider = EneyidaProvider(client);
    });

    test('should have correct metadata', () {
      expect(provider.id, 'eneyida');
      expect(provider.name, 'Eneyida');
      expect(provider.baseUrl, 'https://eneyida.tv');
      expect(provider.supportedTypes, contains(ContentType.movie));
    });

    test('should be enabled by default', () {
      expect(provider.isEnabled, isTrue);
    });
  });

  group('HdrezkaProvider', () {
    late ApiClient client;
    late HdrezkaProvider provider;
    late MockUserAgentService mockUaService;

    setUp(() {
      client = ApiClient();
      mockUaService = MockUserAgentService();
      when(() => mockUaService.getChromeUserAgent()).thenReturn('Chrome/Mock');
      provider = HdrezkaProvider(client, mockUaService);
    });

    test('should have correct metadata', () {
      expect(provider.id, 'hdrezka');
      expect(provider.name, 'HDRezka');
      expect(provider.baseUrl, 'https://hdrezka-home.tv');
    });

    test('setMirror should update baseUrl', () {
      provider.setMirror('https://hdrezka.me/');
      expect(provider.baseUrl, 'https://hdrezka.me');
    });

    test('setMirror should handle trailing slash', () {
      provider.setMirror('https://hdrezka.me');
      expect(provider.baseUrl, 'https://hdrezka.me');

      provider.setMirror('https://hdrezka.me/');
      expect(provider.baseUrl, 'https://hdrezka.me');
    });

    test('should support all content types', () {
      expect(provider.supportedTypes, contains(ContentType.movie));
      expect(provider.supportedTypes, contains(ContentType.series));
      expect(provider.supportedTypes, contains(ContentType.cartoon));
      expect(provider.supportedTypes, contains(ContentType.anime));
    });
  });

  group('YummyAnimeProvider', () {
    late ApiClient client;
    late YummyAnimeProvider provider;

    setUp(() {
      client = ApiClient();
      provider = YummyAnimeProvider(client);
    });

    test('should only support anime content type', () {
      expect(provider.supportedTypes, equals([ContentType.anime]));
    });

    test('should have correct metadata', () {
      expect(provider.id, 'yummyanime');
      expect(provider.name, 'YummyAnime');
      expect(provider.baseUrl, 'https://yummyanime.club');
    });

    test('should only support anime', () {
      expect(provider.supportedTypes.length, 1);
      expect(provider.supportedTypes.first, ContentType.anime);
    });
  });

  group('Provider Common Interface', () {
    test('all providers should implement ContentProvider', () {
      final client = ApiClient();
      final mockUaService = MockUserAgentService();
      when(() => mockUaService.getChromeUserAgent()).thenReturn('Chrome/Mock');

      final List<ContentProvider> providers = [
        UakinoProvider(client),
        EneyidaProvider(client),
        HdrezkaProvider(client, mockUaService),
        YummyAnimeProvider(client),
      ];

      for (final provider in providers) {
        expect(provider.id, isNotEmpty);
        expect(provider.name, isNotEmpty);
        expect(provider.baseUrl, startsWith('http'));
        expect(provider.supportedTypes, isNotEmpty);
      }
    });
  });
}
