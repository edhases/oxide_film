import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import '../database/app_database.dart';
import '../database/dao/downloads_dao.dart';
import '../../domain/entities/entities.dart';

/// Download status enum
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed;

  static DownloadStatus fromString(String value) {
    return DownloadStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => DownloadStatus.pending,
    );
  }
}

/// Download task info
class DownloadTask {
  final Download download;
  final CancelToken cancelToken;
  final Completer<void>? completer;

  DownloadTask({
    required this.download,
    required this.cancelToken,
    this.completer,
  });
}

/// Service for managing offline downloads
class DownloadService extends ChangeNotifier {
  static const String _tag = 'DownloadService';

  final DownloadsDao _dao;
  final ApiClient _apiClient;
  final Map<int, DownloadTask> _activeTasks = {};

  List<Download> _downloads = [];
  bool _isLoading = false;
  String? _lastError;

  DownloadService(AppDatabase database, this._apiClient)
    : _dao = DownloadsDao(database) {
    _loadDownloads();
    _listenToDownloads();
  }

  // Getters
  List<Download> get downloads => _downloads;
  List<Download> get completed =>
      _downloads.where((d) => d.status == 'completed').toList();
  List<Download> get active => _downloads
      .where(
        (d) =>
            d.status == 'pending' ||
            d.status == 'downloading' ||
            d.status == 'paused',
      )
      .toList();
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  /// Check if we can download (mobile/desktop only, no web)
  bool get canDownload => !kIsWeb;

  Future<void> _loadDownloads() async {
    _isLoading = true;
    notifyListeners();

    try {
      _downloads = await _dao.getAll();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void _listenToDownloads() {
    _dao.watchAll().listen((downloads) {
      _downloads = downloads;
      notifyListeners();
    });
  }

  /// Get downloads directory
  Future<Directory> _getDownloadsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${appDir.path}/downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir;
  }

  /// Generate local file path for download
  Future<String> _generateLocalPath(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
    String? extension,
  }) async {
    final dir = await _getDownloadsDir();
    final safeMediaId = mediaId.replaceAll(RegExp(r'[^\w\-]'), '_');

    String filename = '${providerId}_$safeMediaId';
    if (season != null && episode != null) {
      filename += '_s${season}e$episode';
    }
    filename += '.${extension ?? "mp4"}';

    return '${dir.path}/$filename';
  }

  /// Start downloading media
  Future<bool> startDownload({
    required MediaItem item,
    required StreamSource source,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    if (!canDownload) {
      _lastError = 'Завантаження недоступне на цій платформі';
      return false;
    }

    try {
      // Check if already downloaded
      final existing = await _dao.getByMediaId(
        item.id,
        item.providerId,
        season: season,
        episode: episode,
      );

      if (existing != null && existing.status == 'completed') {
        _lastError = 'Вже завантажено';
        return false;
      }

      // Generate local path
      final localPath = await _generateLocalPath(
        item.id,
        item.providerId,
        season: season,
        episode: episode,
      );

      // Add to database
      final id = await _dao.add(
        mediaId: item.id,
        providerId: item.providerId,
        title: item.title,
        posterUrl: item.posterUrl,
        year: item.year,
        mediaType: item.type.name,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle,
        streamUrl: source.url,
        localPath: localPath,
        quality: source.quality.displayName,
        voiceover: source.voiceover,
      );

      // Start actual download
      _startDownloadTask(id, source.url, localPath);

      return true;
    } catch (e) {
      _lastError = e.toString();
      Logger.e('Download failed', tag: _tag, error: e);
      return false;
    }
  }

  /// Start the actual download task using Dio
  void _startDownloadTask(int id, String url, String localPath) async {
    final cancelToken = CancelToken();
    final completer = Completer<void>();

    try {
      await _dao.updateStatus(id, 'downloading');

      // Get download record for task tracking
      final download = await _dao.getAll().then(
        (list) => list.firstWhere((d) => d.id == id),
      );

      _activeTasks[id] = DownloadTask(
        download: download,
        cancelToken: cancelToken,
        completer: completer,
      );

      // Use Dio for downloading with progress tracking
      await _apiClient.dio.download(
        url,
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) async {
          if (total > 0) {
            final progress = received / total;
            await _dao.updateProgress(
              id,
              progress: progress,
              downloadedBytes: received,
              fileSizeBytes: total,
            );
          }
        },
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: true,
          receiveTimeout: const Duration(
            hours: 2,
          ), // Long timeout for large files
        ),
      );

      // Download completed successfully
      await _dao.updateStatus(id, 'completed');
      _activeTasks.remove(id);
      completer.complete();
      Logger.i('Download completed: $localPath', tag: _tag);
    } on DioException catch (e) {
      _activeTasks.remove(id);

      if (e.type == DioExceptionType.cancel) {
        // Download was cancelled (paused or deleted)
        Logger.d('Download cancelled: $id', tag: _tag);
        return;
      }

      Logger.e('Download task failed', tag: _tag, error: e);
      await _dao.updateStatus(id, 'failed');
      completer.completeError(e);

      // Clean up partial file
      try {
        final file = File(localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    } catch (e) {
      _activeTasks.remove(id);
      Logger.e('Download task failed', tag: _tag, error: e);
      await _dao.updateStatus(id, 'failed');
      completer.completeError(e);
    }
  }

  /// Pause download
  Future<void> pauseDownload(int id) async {
    final task = _activeTasks[id];
    if (task != null) {
      task.cancelToken.cancel('Paused by user');
      _activeTasks.remove(id);
    }
    await _dao.updateStatus(id, 'paused');
  }

  /// Resume download
  Future<void> resumeDownload(int id) async {
    final download = _downloads.firstWhere((d) => d.id == id);
    _startDownloadTask(id, download.streamUrl, download.localPath);
  }

  /// Cancel and delete download
  Future<void> cancelDownload(int id) async {
    // Cancel active task
    final task = _activeTasks[id];
    if (task != null) {
      task.cancelToken.cancel('Cancelled by user');
      _activeTasks.remove(id);
    }

    // Delete file if exists
    try {
      final download = _downloads.firstWhere((d) => d.id == id);
      final file = File(download.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      Logger.w('Failed to delete file', tag: _tag);
    }

    // Remove from database
    await _dao.delete(id);
  }

  /// Delete completed download
  Future<void> deleteDownload(int id) async {
    await cancelDownload(id);
  }

  /// Get local file path for offline playback
  String? getLocalPath(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) {
    try {
      final download = _downloads.firstWhere(
        (d) =>
            d.mediaId == mediaId &&
            d.providerId == providerId &&
            d.season == season &&
            d.episode == episode &&
            d.status == 'completed',
      );
      return download.localPath;
    } catch (_) {
      return null;
    }
  }

  /// Check if media is available offline
  bool isAvailableOffline(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) {
    return getLocalPath(
          mediaId,
          providerId,
          season: season,
          episode: episode,
        ) !=
        null;
  }

  /// Get download status for media
  DownloadStatus? getStatus(
    String mediaId,
    String providerId, {
    int? season,
    int? episode,
  }) {
    try {
      final download = _downloads.firstWhere(
        (d) =>
            d.mediaId == mediaId &&
            d.providerId == providerId &&
            d.season == season &&
            d.episode == episode,
      );
      return DownloadStatus.fromString(download.status);
    } catch (_) {
      return null;
    }
  }

  /// Get total downloaded size in bytes
  Future<int> getTotalSize() => _dao.getTotalSize();

  /// Format size for display
  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Clear all downloads
  Future<void> clearAll() async {
    // Cancel all active downloads
    for (final id in _activeTasks.keys.toList()) {
      await cancelDownload(id);
    }

    // Delete all files
    for (final download in _downloads) {
      try {
        final file = File(download.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        Logger.w('Failed to delete file', tag: _tag);
      }
    }

    // Clear database
    await _dao.clearAll();
  }
}
