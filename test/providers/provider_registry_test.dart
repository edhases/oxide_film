import 'package:flutter_test/flutter_test.dart';

import 'package:oxide_film/data/providers/provider_registry.dart';
import 'package:oxide_film/core/network/api_client.dart';
import 'package:oxide_film/data/providers/uakino_provider.dart';
import 'package:oxide_film/data/providers/yummyanime_provider.dart';
import 'package:oxide_film/domain/entities/entities.dart';

void main() {
  late ProviderRegistry registry;
  late ApiClient client;

  setUp(() {
    registry = ProviderRegistry();
    client = ApiClient();
  });

  group('ProviderRegistry', () {
    test('should register providers', () {
      registry.register(UakinoProvider(client));
      registry.register(YummyAnimeProvider(client));

      expect(registry.all.length, 2);
    });

    test('should not register duplicate providers', () {
      final provider = UakinoProvider(client);
      registry.register(provider);
      registry.register(provider);

      // Second registration with same ID should be ignored
      expect(registry.all.length, 1);
    });

    test('getById should return correct provider', () {
      registry.register(UakinoProvider(client));
      registry.register(YummyAnimeProvider(client));

      final result = registry.getById('uakino');

      expect(result, isNotNull);
      expect(result?.id, 'uakino');
    });

    test('getById should return null for unknown id', () {
      registry.register(UakinoProvider(client));

      final result = registry.getById('unknown');

      expect(result, isNull);
    });

    test('getByContentType should return matching providers', () {
      registry.register(UakinoProvider(client)); // all types
      registry.register(YummyAnimeProvider(client)); // anime only

      final movieProviders = registry.getByContentType(ContentType.movie);
      final animeProviders = registry.getByContentType(ContentType.anime);

      expect(movieProviders.length, 1); // uakino
      expect(animeProviders.length, 2); // uakino + yummyanime
    });

    test('unregister should remove provider', () {
      registry.register(UakinoProvider(client));
      registry.register(YummyAnimeProvider(client));

      registry.unregister('uakino');

      expect(registry.all.length, 1);
      expect(registry.getById('uakino'), isNull);
    });

    test('clear should remove all providers', () {
      registry.register(UakinoProvider(client));
      registry.register(YummyAnimeProvider(client));

      registry.clear();

      expect(registry.all, isEmpty);
    });

    test('enabled should return only enabled providers', () {
      final provider = UakinoProvider(client);
      registry.register(provider);

      // By default, provider is enabled
      expect(registry.enabled.length, 1);
    });

    test('all should return all providers regardless of enabled state', () {
      final provider = UakinoProvider(client);
      provider.isEnabled = false;
      registry.register(provider);

      expect(registry.all.length, 1);
    });
  });
}
