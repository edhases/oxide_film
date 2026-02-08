import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/uaserials_repository.dart';

class UaserialsProvider implements ContentProvider {
  final ApiClient _client;
  late final UaserialsRepository _repository;
  bool _isEnabled = true;

  UaserialsProvider(this._client) {
    _repository = UaserialsRepository(_client);
  }

  @override
  String get id => 'uaserials';

  @override
  String get name => 'UaSerials';

  @override
  String get baseUrl => _repository.baseUrl;

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => '$baseUrl/templates/uaserials2020/images/favicon.png';

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  @override
  List<ContentType> get supportedTypes => [
    ContentType.series,
    ContentType.anime,
    ContentType.cartoon,
    ContentType.movie,
  ];

  @override
  Future<List<MediaItem>> search(
    String query, {
    ContentType? type,
    int page = 1,
  }) {
    return _repository.search(query, page: page);
  }

  @override
  Future<List<MediaItem>> getPopular({ContentType? type, int page = 1}) {
    return _repository.getPopular(type: type, page: page);
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) {
    return _repository.getNew(type: type, page: page);
  }

  @override
  Future<List<String>> getCategories() async {
    return ['seriess', 'filmss', 'cartoons', 'anime'];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    return _repository.getByCategory(category, page: page);
  }

  @override
  Future<MediaDetails> getDetails(String id) {
    return _repository.getDetails(id);
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) {
    return _repository.getStreams(id, season: season, episode: episode);
  }

  @override
  Future<List<MediaItem>> getSimilar(String id, MediaDetails details) async {
    if (details.genres == null || details.genres!.isEmpty) {
      return [];
    }

    try {
      // Uaserials uses specific slugs for genres
      // Try to get popular from the category of the first genre
      // For Uaserials, categories are often top-level like 'seriess', 'filmss'
      // BUT they also support genre slugs like 'fantastika', 'detective', etc.

      final genreDisplayName = details.genres!.first;
      // Use general slug generation, might need fine-tuning
      final slug = ContentGenres.getSlug(genreDisplayName);

      // Note: Uaserials usually puts genres at root like /boiovyk/, /drama/
      final items = await getByCategory(slug, page: 1);
      // Filter out the current item
      return items.where((item) => item.id != id).toList();
    } catch (e) {
      return [];
    }
  }
}
