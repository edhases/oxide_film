import 'dart:async';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/dao/history_dao.dart';

/// Service for managing watch history
class HistoryService extends ChangeNotifier {
  final HistoryDao _dao;

  List<WatchHistoryData> _history = [];
  List<WatchHistoryData> get history => _history;

  List<WatchHistoryData> _continueWatching = [];
  List<WatchHistoryData> get continueWatching => _continueWatching;

  final bool _isLoading = false;
  bool get isLoading => _isLoading;

  StreamSubscription<List<WatchHistoryData>>? _historySubscription;
  StreamSubscription<List<WatchHistoryData>>? _continueSubscription;

  HistoryService(AppDatabase database) : _dao = HistoryDao(database) {
    _init();
  }

  void _init() {
    // Cleanup duplicates on startup (fire and forget)
    _dao.cleanupDuplicates().then((count) {
      if (count > 0) {
        debugPrint('Cleaned up $count duplicate history entries');
        notifyListeners();
      }
    });

    _historySubscription = _dao.watchAll(limit: 50).listen((items) {
      _history = items;
      notifyListeners();
    });

    _continueSubscription = _dao.watchContinueWatching(limit: 10).listen((
      items,
    ) {
      _continueWatching = items;
      notifyListeners();
    });
  }

  /// Save watch progress
  Future<void> saveProgress({
    required String mediaId,
    required String providerId,
    required String title,
    String? posterUrl,
    int? year,
    required String mediaType,
    required Duration position,
    required Duration duration,
    int? season,
    int? episode,
    String? episodeTitle,
    String? lastStreamUrl,
    String? voiceover,
  }) async {
    await _dao.saveProgress(
      mediaId: mediaId,
      providerId: providerId,
      title: title,
      posterUrl: posterUrl,
      year: year,
      mediaType: mediaType,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      season: season,
      episode: episode,
      episodeTitle: episodeTitle,
      lastStreamUrl: lastStreamUrl,
      voiceover: voiceover,
    );
  }

  /// Get last position for media
  Future<Duration?> getLastPosition(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    return _dao.getLastPosition(
      mediaId,
      providerId,
      season: season,
      episode: episode,
    );
  }

  /// Get history entry for media
  Future<WatchHistoryData?> getForMedia(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    return _dao.getForMedia(
      mediaId,
      providerId,
      season: season,
      episode: episode,
    );
  }

  /// Remove from history
  Future<void> remove(String mediaId, String providerId) async {
    await _dao.remove(mediaId, providerId);
  }

  /// Clear all history
  Future<void> clearAll() async {
    await _dao.clearAll();
    notifyListeners();
  }

  /// Get history count
  Future<int> get count => _dao.count();

  /// Calculate progress percentage
  double getProgress(WatchHistoryData item) {
    if (item.durationMs == 0) return 0;
    return (item.positionMs / item.durationMs).clamp(0.0, 1.0);
  }

  /// Format remaining time
  String formatRemaining(WatchHistoryData item) {
    final remaining = Duration(milliseconds: item.durationMs - item.positionMs);
    if (remaining.inHours > 0) {
      return '${remaining.inHours}г ${remaining.inMinutes % 60}хв залишилось';
    }
    return '${remaining.inMinutes}хв залишилось';
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    _continueSubscription?.cancel();
    super.dispose();
  }
}
