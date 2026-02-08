import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/yummyanime_repository.dart';

class YummyAnimeProvider implements ContentProvider {
  final ApiClient _client;
  late final YummyAnimeRepository _repository;
  bool _isEnabled = true;

  YummyAnimeProvider(this._client) {
    _repository = YummyAnimeRepository(_client);
  }

  @override
  String get id => 'yummyanime';

  @override
  String get name => 'YummyAnime';

  @override
  String get baseUrl => _repository.baseUrl;

  void setMirror(String url) {
    _repository.setMirror(url);
  }

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => '$effectiveBaseUrl/favicon.ico';

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  @override
  List<ContentType> get supportedTypes => [ContentType.anime];

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
      'Бойовик',
      'Комедія',
      'Романтика',
      'Драма',
      'Фентезі',
      'Пригоди',
      'Школа',
      'Надприродне',
      'Меха',
      'Сьонен',
      'Сьодзьо',
      'Ісекай',
      'Спорт',
      'Психологія',
      'Жахи',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    // Parser converts human readable category to slug
    String slug = _categoryToSlug(category);
    return _repository.getByCategory(slug, page: page);
  }

  String _categoryToSlug(String category) {
    final map = {
      'Бойовик': 'action',
      'Комедія': 'comedy',
      'Романтика': 'romance',
      'Драма': 'drama',
      'Фентезі': 'fantasy',
      'Пригоди': 'adventure',
      'Школа': 'school',
      'Надприродне': 'supernatural',
      'Меха': 'mecha',
      'Сьонен': 'shounen',
      'Сьодзьо': 'shoujo',
      'Ісекай': 'isekai',
      'Спорт': 'sports',
      'Психологія': 'psychological',
      'Жахи': 'horror',
    };
    return map[category] ?? category.toLowerCase();
  }

  @override
  Future<MediaDetails> getDetails(String id) {
    return _repository.getDetails(id);
  }

  @override
  Future<List<MediaItem>> getSimilar(String id, MediaDetails details) async {
    if (details.genres == null || details.genres!.isEmpty) {
      return [];
    }
    try {
      final slug = ContentGenres.getSlug(details.genres!.first);
      final items = await getByCategory(slug, page: 1);
      return items.where((item) => item.id != id).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) {
    return _repository.getStreams(id, season: season, episode: episode);
  }
}
