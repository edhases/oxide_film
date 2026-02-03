import 'package:drift/drift.dart';
import '../app_database.dart';

/// Data Access Object for downloads
class DownloadsDao {
  final AppDatabase _db;

  DownloadsDao(this._db);

  /// Get all downloads
  Future<List<Download>> getAll() async {
    final query = _db.select(_db.downloads)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  /// Get downloads by status
  Future<List<Download>> getByStatus(String status) async {
    final query = _db.select(_db.downloads)
      ..where((t) => t.status.equals(status))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  /// Get completed downloads for offline viewing
  Future<List<Download>> getCompleted() async {
    return getByStatus('completed');
  }

  /// Get pending/downloading items
  Future<List<Download>> getActive() async {
    final query = _db.select(_db.downloads)
      ..where((t) => t.status.isIn(['pending', 'downloading', 'paused']))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Get download by media ID
  Future<Download?> getByMediaId(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    final query = _db.select(_db.downloads)
      ..where(
        (t) =>
            t.mediaId.equals(mediaId) &
            t.providerId.equals(providerId) &
            (season != null ? t.season.equals(season) : t.season.isNull()) &
            (episode != null ? t.episode.equals(episode) : t.episode.isNull()),
      );
    return query.getSingleOrNull();
  }

  /// Check if media is downloaded
  Future<bool> isDownloaded(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    final download = await getByMediaId(
      mediaId,
      providerId,
      season: season,
      episode: episode,
    );
    return download?.status == 'completed';
  }

  /// Add new download
  Future<int> add({
    required String mediaId,
    required String providerId,
    required String title,
    String? posterUrl,
    int? year,
    required String mediaType,
    int? season,
    int? episode,
    String? episodeTitle,
    required String streamUrl,
    required String localPath,
    required String quality,
    String? voiceover,
  }) async {
    return _db
        .into(_db.downloads)
        .insert(
          DownloadsCompanion.insert(
            mediaId: mediaId,
            providerId: providerId,
            title: title,
            posterUrl: Value(posterUrl),
            year: Value(year),
            mediaType: mediaType,
            season: Value(season),
            episode: Value(episode),
            episodeTitle: Value(episodeTitle),
            streamUrl: streamUrl,
            localPath: localPath,
            quality: quality,
            voiceover: Value(voiceover),
          ),
          mode: InsertMode.replace,
        );
  }

  /// Update download status
  Future<int> updateStatus(int id, String status) async {
    return (_db.update(_db.downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        status: Value(status),
        completedAt: status == 'completed'
            ? Value(DateTime.now())
            : const Value.absent(),
      ),
    );
  }

  /// Update download progress
  Future<int> updateProgress(
    int id, {
    required double progress,
    required int downloadedBytes,
    int? fileSizeBytes,
  }) async {
    return (_db.update(_db.downloads)..where((t) => t.id.equals(id))).write(
      DownloadsCompanion(
        progress: Value(progress),
        downloadedBytes: Value(downloadedBytes),
        fileSizeBytes: fileSizeBytes != null
            ? Value(fileSizeBytes)
            : const Value.absent(),
      ),
    );
  }

  /// Delete download
  Future<int> delete(int id) async {
    return (_db.delete(_db.downloads)..where((t) => t.id.equals(id))).go();
  }

  /// Delete by media ID
  Future<int> deleteByMediaId(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) async {
    final query = _db.delete(_db.downloads)
      ..where(
        (t) =>
            t.mediaId.equals(mediaId) &
            t.providerId.equals(providerId) &
            (season != null ? t.season.equals(season) : t.season.isNull()) &
            (episode != null ? t.episode.equals(episode) : t.episode.isNull()),
      );
    return query.go();
  }

  /// Clear all downloads
  Future<int> clearAll() async {
    return _db.delete(_db.downloads).go();
  }

  /// Get total downloaded size
  Future<int> getTotalSize() async {
    final downloads = await getCompleted();
    return downloads.fold<int>(0, (sum, d) => sum + d.fileSizeBytes);
  }

  /// Watch downloads stream
  Stream<List<Download>> watchAll() {
    final query = _db.select(_db.downloads)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.watch();
  }

  /// Watch active downloads
  Stream<List<Download>> watchActive() {
    final query = _db.select(_db.downloads)
      ..where((t) => t.status.isIn(['pending', 'downloading', 'paused']))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }
}
