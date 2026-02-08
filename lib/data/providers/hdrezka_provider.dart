import '../../core/constants/content_constants.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/entities.dart';
import '../../domain/repositories/content_provider.dart';
import '../repositories/hdrezka_repository.dart';

import '../../data/services/user_agent_service.dart';

/// HDRezka content provider adapter
class HdrezkaProvider implements ContentProvider {
  final ApiClient _client;
  final UserAgentService _uaService;
  late final HdrezkaRepository _repository;
  bool _isEnabled = false;

  /// Whether to show this provider on the home page (false for HDRezka)
  static const bool showOnHome = false;

  /// Whether streams from this provider are "fixed"
  static const bool hasFixedStreams = true;

  /// List of known working mirrors
  static const List<String> _mirrors = [
    'https://hdrezka-home.tv',
    'https://rezka.ag',
    'https://hdrezka.ag',
    'https://hdrezka.me',
    'https://hdrezka.co',
    'https://hdrezka.sh',
  ];

  /// Get available mirrors
  List<String> get availableMirrors => _mirrors;

  HdrezkaProvider(this._client, this._uaService) {
    _repository = HdrezkaRepository(_client, _uaService);
  }

  @override
  String get id => 'hdrezka';

  @override
  String get name => 'HDRezka';

  @override
  String get baseUrl => _repository.mirror;

  @override
  String get effectiveBaseUrl => baseUrl;

  @override
  String? get iconUrl => '$baseUrl/favicon.ico';

  @override
  bool get isEnabled => _isEnabled;

  set isEnabled(bool value) => _isEnabled = value;

  /// Set mirror URL
  void setMirror(String url) {
    _repository.setMirror(url);
  }

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
  Future<List<String>> getCategories() => _repository.getCategories(); // Not implemented in base repo yet, but provider had it

  @override
  Future<List<MediaItem>> getByCategory(
    String category, {
    ContentType? type,
    int page = 1,
  }) {
    return _repository.getByCategory(
      category,
      type: type,
      page: page,
      providerId: id,
    );
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
