import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/uaflix_repository.dart';

/// UAFlix content provider adapter
class UaflixProvider implements ContentProvider {
  final ApiClient _client;
  late final UaflixRepository _repository;
  bool _isEnabled = true;

  UaflixProvider(this._client) {
    _repository = UaflixRepository(_client);
  }

  @override
  String get id => 'uaflix';

  @override
  String get name => 'UAFlix';

  @override
  String get baseUrl => _repository.baseUrl;

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => '$baseUrl/favicon.ico';

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  @override
  List<ContentType> get supportedTypes => [
    ContentType.movie,
    ContentType.series,
    ContentType.cartoon,
    ContentType.anime,
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
    return [
      'films/new_netflix_ua',
      'films/teen_films',
      'films/love_films',
      'films/documental_films',
      'films/films_horror',
      'films/action',
      'films/melodrama',
      'films/fantastics',
      'films/comedy',
      'serials/new_uaserial',
      'serials/detective',
      'serials/history_serials',
      'serials/comedy_serials',
      'serials/fantasy_serialy',
    ];
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
  Future<MediaDetails> getDetails(String mediaId) {
    return _repository.getDetails(mediaId);
  }

  @override
  Future<List<StreamSource>> getStreams(
    String mediaId, {
    int? season,
    int? episode,
  }) {
    // Repository handles full stream extraction
    // Filtering by season/episode is done by logic or post-processing if needed
    // But usually repo returns what it finds.
    return _repository.getStreams(mediaId, season: season, episode: episode);
  }
}
