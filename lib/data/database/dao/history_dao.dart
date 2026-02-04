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
        (t) =>
            t.mediaId.equals(mediaId) &
            t.providerId.equals(providerId) &
            (season != null ? t.season.equals(season) : t.season.isNull()) &
            (episode != null ? t.episode.equals(episode) : t.episode.isNull()),
      );

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
    double? rating,
    String? ratingSource,
  }) async {
    // Manually check for existing entry to handle NULLs in Unique Keys correctly
    final existing =
        await (_db.select(_db.watchHistory)..where(
              (t) =>
                  t.mediaId.equals(mediaId) &
                  t.providerId.equals(providerId) &
                  (season != null
                      ? t.season.equals(season)
                      : t.season.isNull()) &
                  (episode != null
                      ? t.episode.equals(episode)
                      : t.episode.isNull()),
            ))
            .getSingleOrNull();

    if (existing != null) {
      // Update existing
      await (_db.update(
        _db.watchHistory,
      )..where((t) => t.id.equals(existing.id))).write(
        WatchHistoryCompanion(
          title: Value(title),
          posterUrl: Value(posterUrl),
          year: Value(year),
          positionMs: Value(positionMs),
          durationMs: Value(durationMs),
          episodeTitle: Value(episodeTitle),
          lastStreamUrl: Value(lastStreamUrl),
          voiceover: Value(voiceover),
          rating: Value(rating),
          ratingSource: Value(ratingSource),
          watchedAt: Value(DateTime.now()),
        ),
      );
    } else {
      // Insert new
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
              rating: Value(rating),
              ratingSource: Value(ratingSource),
              watchedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  /// Remove duplicates from history
  /// Keeps only the most recent entry for each unique media/episode combination
  Future<int> cleanupDuplicates() async {
    final allHistory = await getAll();
    final uniqueKeys = <String>{};
    final idsToDelete = <int>[];

    // history is already ordered by watchedAt DESC (newest first)
    for (final item in allHistory) {
      final key =
          '${item.mediaId}_${item.providerId}_${item.season}_${item.episode}';

      if (uniqueKeys.contains(key)) {
        // This is a duplicate (older than the one we already saw)
        idsToDelete.add(item.id);
      } else {
        uniqueKeys.add(key);
      }
    }

    if (idsToDelete.isEmpty) return 0;

    // Delete in batches if needed, but for now single batch is fine
    // Drift doesn't support 'WHERE id IN list' easily in fluent API for delete
    // So we use custom statement or loop.
    // Actually, we can use where((t) => t.id.isIn(idsToDelete))
    return (_db.delete(
      _db.watchHistory,
    )..where((t) => t.id.isIn(idsToDelete))).go();
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
