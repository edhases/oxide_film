import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/entities.dart';
import '../database/app_database.dart';
import '../database/dao/favorites_dao.dart';

/// Service for managing favorites
class FavoritesService extends ChangeNotifier {
  final FavoritesDao _dao;

  List<Favorite> _favorites = [];
  List<Favorite> get favorites => _favorites;

  final bool _isLoading = false;
  bool get isLoading => _isLoading;

  StreamSubscription<List<Favorite>>? _subscription;

  FavoritesService(AppDatabase database) : _dao = FavoritesDao(database) {
    _init();
  }

  void _init() {
    _subscription = _dao.watchAll().listen((items) {
      _favorites = items;
      notifyListeners();
    });
  }

  /// Check if item is in favorites
  bool isFavorite(String mediaId, String providerId) {
    return _favorites.any(
      (f) => f.mediaId == mediaId && f.providerId == providerId,
    );
  }

  /// Toggle favorite status
  Future<bool> toggle(MediaItem item) async {
    final result = await _dao.toggle(
      mediaId: item.id,
      providerId: item.providerId,
      title: item.title,
      posterUrl: item.posterUrl,
      year: item.year,
      mediaType: item.type.name,
    );
    return result;
  }

  /// Add to favorites
  Future<void> add(MediaItem item) async {
    await _dao.add(
      mediaId: item.id,
      providerId: item.providerId,
      title: item.title,
      posterUrl: item.posterUrl,
      year: item.year,
      mediaType: item.type.name,
    );
  }

  /// Remove from favorites
  Future<void> remove(String mediaId, String providerId) async {
    await _dao.remove(mediaId, providerId);
  }

  /// Get favorites by type
  Future<List<Favorite>> getByType(ContentType type) async {
    return _dao.getByType(type.name);
  }

  /// Get favorites count
  Future<int> get count => _dao.count();

  /// Clear all favorites
  Future<void> clearAll() async {
    await _dao.clearAll();
  }

  /// Watch favorite status for specific item
  Stream<bool> watchIsFavorite(String mediaId, String providerId) {
    return _dao.watchIsFavorite(mediaId, providerId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
