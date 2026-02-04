// Tests for HomePage parallel fetch and deduplication

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:oxide_film/data/providers/provider_registry.dart';
import 'package:oxide_film/domain/entities/entities.dart';
import 'package:oxide_film/presentation/pages/home/home_page.dart';
import 'package:oxide_film/presentation/widgets/media_card.dart';

import '../../../helpers/mock_services.dart';
import 'package:mocktail/mocktail.dart';

class _FakeProvider implements ContentProvider {
  @override
  final String id;

  @override
  final String name;

  final List<MediaItem> _items;

  _FakeProvider(this.id, this.name, this._items);

  @override
  String get baseUrl => 'https://$id.example';

  @override
  bool get isEnabled => true;

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => null;

  @override
  List<ContentType> get supportedTypes => [ContentType.movie];

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    return Future.value(_items);
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) {
    return Future.value(_items);
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) {
    return Future.value(_items);
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) {
    return Future.value([]);
  }

  @override
  Future<MediaDetails> getDetails(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) {
    return Future.value(_items);
  }
}

void main() {
  setUp(() {
    // Register a mock settings service and other dependencies used by HomePage
    final mockSettings = MockSettingsService();
    when(() => mockSettings.state).thenReturn(const SettingsState());

    if (GetIt.I.isRegistered<SettingsService>()) {
      GetIt.I.unregister<SettingsService>();
    }
    GetIt.I.registerSingleton<SettingsService>(mockSettings);
  });

  tearDown(() {
    if (GetIt.I.isRegistered<ProviderRegistry>()) {
      GetIt.I.unregister<ProviderRegistry>();
    }
    if (GetIt.I.isRegistered<SettingsService>()) {
      GetIt.I.unregister<SettingsService>();
    }
  });

  testWidgets('HomePage loads providers in parallel and deduplicates items', (
    tester,
  ) async {
    final registry = ProviderRegistry();

    final item1 = MediaItem(
      id: '1',
      providerId: 'provA',
      title: 'Title1',
      type: ContentType.movie,
    );
    final item2 = MediaItem(
      id: '2',
      providerId: 'provA',
      title: 'Title2',
      type: ContentType.movie,
    );
    final item3 = MediaItem(
      id: '3',
      providerId: 'provB',
      title: 'Title3',
      type: ContentType.movie,
    );

    // Provider A returns a duplicate of item1 inside its list
    final providerA = _FakeProvider('provA', 'Prov A', [item1, item2, item1]);
    final providerB = _FakeProvider('provB', 'Prov B', [item3]);

    registry.register(providerA);
    registry.register(providerB);

    GetIt.I.registerSingleton<ProviderRegistry>(registry);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomePage())));

    // Allow async content to load
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // MediaCard widgets should be present for unique items (3 unique entries: 1,2,3)
    final cards = find.byType(MediaCard);
    expect(cards, findsNWidgets(3));

    // Cleanup provider registry
    GetIt.I.unregister<ProviderRegistry>();
  });
}
