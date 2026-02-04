import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/eneyida_repository.dart';

/// Eneyida content provider adapter
class EneyidaProvider implements ContentProvider {
  final ApiClient _client;
  late final EneyidaRepository _repository;
  bool _isEnabled = true;

  EneyidaProvider(this._client) {
    _repository = EneyidaRepository(_client);
  }

  @override
  String get id => 'eneyida';

  @override
  String get name => 'Eneyida';

  // Note: previously it was '$effectiveBaseUrl/favicon.ico' but effectiveBaseUrl came from mixin.
  // Repository has baseUrl.
  @override
  String? get iconUrl => '${_repository.baseUrl}/favicon.ico';

  @override
  String get baseUrl => _repository.baseUrl;

  @override
  String get effectiveBaseUrl => baseUrl;

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
  Future<MediaDetails> getDetails(String id) {
    return _repository.getDetails(id);
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) {
    // Repository handles finding correct stream for season/episode via parsing logic if it was built-in,
    // but here we just return all streams. The player logic will filter by season/episode if attributes match.
    // Our new Parser extracts season/episode info into StreamSource.
    return _repository.getStreams(id, season: season, episode: episode);
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
      'Бойовик',
      'Детектив',
      'Драма',
      'Комедія',
      'Мелодрама',
      'Пригоди',
      'Трилер',
      'Фантастика',
      'Фентезі',
      'Жахи',
      'Історичний',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    final genreSlug = _categoryToSlug(category);
    return _repository.getByCategory(genreSlug, page: page);
  }

  String _categoryToSlug(String category) {
    final map = {
      'Бойовик': 'boyovik',
      'Детектив': 'detektyv',
      'Драма': 'drama',
      'Комедія': 'komediya',
      'Мелодрама': 'melodrama',
      'Пригоди': 'pryhody',
      'Трилер': 'tryler',
      'Фантастика': 'fantastyka',
      'Фентезі': 'fentezi',
      'Жахи': 'zhakhy',
      'Історичний': 'istorychnyy',
    };
    return map[category] ?? category.toLowerCase();
  }
}
