import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/uakino_repository.dart';

class UakinoProvider implements ContentProvider {
  final ApiClient _client;
  late final UakinoRepository _repository;
  bool _isEnabled = true;

  UakinoProvider(this._client) {
    _repository = UakinoRepository(_client);
  }

  @override
  String get id => 'uakino';

  @override
  String get name => 'UAKino';

  @override
  String get iconUrl => 'https://uakino.best/favicon.ico';

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
  Future<List<MediaItem>> getSimilar(String id, MediaDetails details) async {
    if (details.genres == null || details.genres!.isEmpty) {
      return [];
    }

    try {
      final genreDisplayName = details.genres!.first;

      final slug = ProviderGenreMappings.getSlugForProvider(
        id,
        genreDisplayName,
        fallback: ContentGenres.getSlug(genreDisplayName),
      );

      if (slug.isEmpty) return [];

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
  }) async {
    // Repository handles stream extraction.
    // Season/Episode handling is done AFTER extraction usually, or filtered.
    // Provider interface asks for streams for a specific ID.
    // Usually streams return ALL episodes/seasons in the list (or playlist).
    // The player then filters/selects.
    return _repository.getStreams(id);
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
      'Трилери',
      'Детективи',
      'Фантастика',
      'Бойовики',
      'Військові',
      'Комедії',
      'Драми',
      'Мелодрами',
      'Пригоди',
      'Жахи',
      'Фентезі',
      'Сімейні',
      'Історичні',
      'Містичні',
      'Документальні',
      'Спортивні',
      'Біографія',
      'Кримінал',
      'Вестерн',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    // Map category name to slug using ProviderGenreMappings if needed,
    // but Repository takes slug. ProviderGenreMappings is usually available here.
    // However, in previous code:
    // final genreSlug = ProviderGenreMappings.getSlugForProvider(id, category);
    // So we need ProviderGenreMappings.
    // I need to import it.

    // Actually, I can keep the mapping logic here as "Adapter" logic.
    final genreSlug = _getSlugForProvider(category);
    return _repository.getByCategory(genreSlug, type: type, page: page);
  }

  // Minimal mapping logic helper, or better import ProviderGenreMappings?
  // Previous code imported it? No, it used `ProviderGenreMappings.getSlugForProvider(id, category)`.
  // Wait, I don't see `ProviderGenreMappings` imported in the previous file content I viewed (lines 1-800).
  // Maybe it was implicitly imported or I missed it.
  // Ah, line 719: `final genreSlug = ProviderGenreMappings.getSlugForProvider(id, category);`
  // But where is it imported? Maybe `content_constants.dart` exports it?

  // Let's assume it is in `../../core/constants/content_constants.dart` or similar.
  // I will check imports of previous file.
  // import '../../core/constants/content_constants.dart';

  // I'll try to use it. If analysis fails, I'll fix.

  String _getSlugForProvider(String category) {
    // Re-implementing mapping locally or using shared class?
    // I'll assume ProviderGenreMappings is available.
    // If not, I'll use a simple map for now to avoid breaking changes if imports are tricky.
    // The previous implementation used ProviderGenreMappings.
    // I'll try to find where it is defined.
    return ProviderGenreMappings.getSlugForProvider(id, category);
  }
}

// I need to make sure ProviderGenreMappings is available.
// I will start by assuming it is available via imports.
