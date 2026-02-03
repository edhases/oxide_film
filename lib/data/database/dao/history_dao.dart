import 'package:drift/drift.dart';
import '../app_database.dart';

/// Data Access Object for watch history
class HistoryDao {
  final AppDatabase _db;

  HistoryDao(this._db);

  /// Get all history entries
  Future<List<WatchHistoryData>> getAll({int? limit}) async {
    var query = _db.select(_db.watchHistory)
      ..orderBy([(t) => OrderingTerm.desc(t.watchedAt)]);
    if (limit != null) {
      query = query..limit(limit);
    }
    return query.get();
  }

  /// Get history for specific media
  Future<WatchHistoryData?> getForMedia(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    var query = _db.select(_db.watchHistory)
      ..where(
        (t) => t.mediaId.equals(mediaId) & t.providerId.equals(providerId),
      );

    if (season != null) {
      query = query..where((t) => t.season.equals(season));
    }
    if (episode != null) {
      query = query..where((t) => t.episode.equals(episode));
    }

    return query.getSingleOrNull();
  }

  /// Get continue watching list (items with progress > 5% and < 95%)
  Future<List<WatchHistoryData>> getContinueWatching({int limit = 20}) async {
    final query = _db.select(_db.watchHistory)
      ..where(
        (t) =>
            t.positionMs.isBiggerThanValue(0) &
            t.durationMs.isBiggerThanValue(0),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.watchedAt)])
      ..limit(limit);

    final results = await query.get();

    // Filter in Dart for progress percentage
    return results.where((item) {
      if (item.durationMs == 0) return false;
      final progress = item.positionMs / item.durationMs;
      return progress > 0.05 && progress < 0.95;
    }).toList();
  }

  /// Save watch progress
  Future<void> saveProgress({
    required String mediaId,
    required String providerId,
    required String title,
    String? posterUrl,
    int? year,
    required String mediaType,
    required int positionMs,
    required int durationMs,
    int? season,
    int? episode,
    String? episodeTitle,
    String? lastStreamUrl,
    String? voiceover,
  }) async {
    await _db
        .into(_db.watchHistory)
        .insert(
          WatchHistoryCompanion.insert(
            mediaId: mediaId,
            providerId: providerId,
            title: title,
            posterUrl: Value(posterUrl),
            year: Value(year),
            mediaType: mediaType,
            positionMs: Value(positionMs),
            durationMs: Value(durationMs),
            season: Value(season),
            episode: Value(episode),
            episodeTitle: Value(episodeTitle),
            lastStreamUrl: Value(lastStreamUrl),
            voiceover: Value(voiceover),
            watchedAt: Value(DateTime.now()),
          ),
          onConflict: DoUpdate(
            (old) => WatchHistoryCompanion(
              title: Value(title),
              posterUrl: Value(posterUrl),
              year: Value(year),
              positionMs: Value(positionMs),
              durationMs: Value(durationMs),
              episodeTitle: Value(episodeTitle),
              lastStreamUrl: Value(lastStreamUrl),
              voiceover: Value(voiceover),
              watchedAt: Value(DateTime.now()),
            ),
            target: [
              _db.watchHistory.mediaId,
              _db.watchHistory.providerId,
              _db.watchHistory.season,
              _db.watchHistory.episode,
            ],
          ),
        );
  }

  /// Get last watched position for media
  Future<Duration?> getLastPosition(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    final entry = await getForMedia(
      mediaId,
      providerId,
      season: season,
      episode: episode,
    );
    if (entry == null || entry.positionMs == 0) return null;
    return Duration(milliseconds: entry.positionMs);
  }

  /// Clear history entry
  Future<int> remove(String mediaId, String providerId) async {
    return (_db.delete(_db.watchHistory)..where(
          (t) => t.mediaId.equals(mediaId) & t.providerId.equals(providerId),
        ))
        .go();
  }

  /// Clear all history
  Future<int> clearAll() async {
    return _db.delete(_db.watchHistory).go();
  }

  /// Watch history stream
  Stream<List<WatchHistoryData>> watchAll({int? limit}) {
    var query = _db.select(_db.watchHistory)
      ..orderBy([(t) => OrderingTerm.desc(t.watchedAt)]);
    if (limit != null) {
      query = query..limit(limit);
    }
    return query.watch();
  }

  /// Watch continue watching list
  Stream<List<WatchHistoryData>> watchContinueWatching({int limit = 10}) {
    final query = _db.select(_db.watchHistory)
      ..where(
        (t) =>
            t.positionMs.isBiggerThanValue(0) &
            t.durationMs.isBiggerThanValue(0),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.watchedAt)])
      ..limit(limit * 2); // Get more to filter

    return query.watch().map((results) {
      return results
          .where((item) {
            if (item.durationMs == 0) return false;
            final progress = item.positionMs / item.durationMs;
            return progress > 0.05 && progress < 0.95;
          })
          .take(limit)
          .toList();
    });
  }

  /// Get history count
  Future<int> count() async {
    final countExp = _db.watchHistory.id.count();
    final query = _db.selectOnly(_db.watchHistory)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }
}
