import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/youtube_repository.dart';

/// YouTube content provider adapter
class YouTubeProvider implements ContentProvider {
  final ApiClient _client;
  late final YouTubeRepository _repository;
  bool _isEnabled = false;

  /// Whether to show this provider on the home page (false for YouTube)
  static const bool showOnHome = false;

  /// Whether browsing requires search
  static const bool requiresSearch = true;

  YouTubeProvider(this._client) {
    _repository = YouTubeRepository(_client);
  }

  @override
  String get id => 'youtube';

  @override
  String get name => 'YouTube';

  @override
  String get baseUrl => _repository.baseUrl;

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => 'https://www.youtube.com/favicon.ico';

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
    // YouTube trending
    return _repository.getPopular();
  }

  @override
  Future<List<MediaItem>> getNew({ContentType? type, int page = 1}) {
    // Same as popular
    return _repository.getPopular();
  }

  @override
  Future<List<String>> getCategories() async {
    return [
      'Фільми',
      'Музика',
      'Ігри',
      'Новини',
      'Спорт',
      'Освіта',
      'Наука і технології',
      'Розваги',
    ];
  }

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    return _repository.search(category, page: page);
  }

  @override
  Future<MediaDetails> getDetails(String id) {
    return _repository.getDetails(id);
  }

  @override
  Future<List<MediaItem>> getSimilar(String id, MediaDetails details) async {
    // YouTube provider integration is basic, no specific similar logic yet
    return [];
  }

  @override
  Future<List<StreamSource>> getStreams(
    String id, {
    int? season,
    int? episode,
  }) {
    // No season/episode support for YouTube generally
    return _repository.getStreams(id);
  }
}
