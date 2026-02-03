import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/database/app_database.dart';
import '../../../data/services/download_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_titlebar.dart';

/// Downloads page for offline content
class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>
    with SingleTickerProviderStateMixin {
  final _downloadService = GetIt.instance<DownloadService>();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _downloadService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _downloadService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    if (!_downloadService.canDownload) {
      return Scaffold(
        body: Column(
          children: [
            if (_isDesktop) const CustomTitleBar(),
            _buildAppBar(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'Завантаження недоступне',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('Ця функція недоступна у веб-версії'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          if (_isDesktop) const CustomTitleBar(),
          _buildAppBar(),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Завантажено'),
              Tab(text: 'В черзі'),
            ],
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
            unselectedLabelColor: AppTheme.textMuted,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildCompletedList(), _buildActiveList()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
            tooltip: 'Назад',
          ),
          const SizedBox(width: 8),
          const Icon(Icons.download_done),
          const SizedBox(width: 8),
          const Text(
            'Завантаження',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          FutureBuilder<int>(
            future: _downloadService.getTotalSize(),
            builder: (context, snapshot) {
              final size = snapshot.data ?? 0;
              return Text(
                _downloadService.formatSize(size),
                style: TextStyle(color: AppTheme.textMuted),
              );
            },
          ),
          if (_downloadService.completed.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _showClearDialog,
              tooltip: 'Очистити все',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedList() {
    final items = _downloadService.completed;

    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.download_done,
        title: 'Немає завантажень',
        subtitle: 'Завантажте фільми для офлайн перегляду',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _DownloadCard(
          download: item,
          formatSize: _downloadService.formatSize,
          onPlay: () => _playDownload(item),
          onDelete: () => _deleteDownload(item),
        );
      },
    );
  }

  Widget _buildActiveList() {
    final items = _downloadService.active;

    if (items.isEmpty) {
      return _buildEmptyState(
        icon: Icons.cloud_download,
        title: 'Немає активних завантажень',
        subtitle: 'Додайте контент для завантаження',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ActiveDownloadCard(
          download: item,
          formatSize: _downloadService.formatSize,
          onPause: item.status == 'downloading'
              ? () => _downloadService.pauseDownload(item.id)
              : null,
          onResume: item.status == 'paused'
              ? () => _downloadService.resumeDownload(item.id)
              : null,
          onCancel: () => _downloadService.cancelDownload(item.id),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  void _playDownload(Download download) {
    // Check if file exists
    final file = File(download.localPath);
    if (!file.existsSync()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Файл не знайдено')));
      return;
    }

    String title = download.title;
    if (download.season != null && download.episode != null) {
      title += ' - S${download.season}E${download.episode}';
    }

    context.push(
      '/player',
      extra: {
        'url': download.localPath,
        'title': title,
        'subtitle': download.voiceover ?? download.quality,
        'mediaId': download.mediaId,
        'providerId': download.providerId,
        'posterUrl': download.posterUrl,
        'isOffline': true,
      },
    );
  }

  void _deleteDownload(Download download) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Видалити завантаження?'),
        content: Text('Ви впевнені, що хочете видалити "${download.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadService.deleteDownload(download.id);
            },
            child: Text(
              'Видалити',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Очистити всі завантаження?'),
        content: const Text(
          'Ви впевнені, що хочете видалити всі завантажені файли? '
          'Цю дію неможливо відмінити.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadService.clearAll();
            },
            child: Text(
              'Очистити',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card for completed downloads
class _DownloadCard extends StatelessWidget {
  final Download download;
  final String Function(int) formatSize;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _DownloadCard({
    required this.download,
    required this.formatSize,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: download.posterUrl != null
                    ? CachedNetworkImage(
                        imageUrl: download.posterUrl!,
                        width: 60,
                        height: 90,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 60,
                        height: 90,
                        color: AppTheme.darkCard,
                        child: const Icon(Icons.movie, size: 32),
                      ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (download.season != null && download.episode != null)
                      Text(
                        'Сезон ${download.season}, Серія ${download.episode}',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.high_quality,
                          label: download.quality,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          icon: Icons.storage,
                          label: formatSize(download.fileSizeBytes),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Actions
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.play_circle_filled, size: 40),
                    color: AppTheme.primaryColor,
                    onPressed: onPlay,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card for active downloads
class _ActiveDownloadCard extends StatelessWidget {
  final Download download;
  final String Function(int) formatSize;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback onCancel;

  const _ActiveDownloadCard({
    required this.download,
    required this.formatSize,
    this.onPause,
    this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isPaused = download.status == 'paused';
    final isFailed = download.status == 'failed';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: download.posterUrl != null
                      ? CachedNetworkImage(
                          imageUrl: download.posterUrl!,
                          width: 50,
                          height: 75,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 50,
                          height: 75,
                          color: AppTheme.darkCard,
                          child: const Icon(Icons.movie),
                        ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getStatusText(),
                        style: TextStyle(
                          color: isFailed
                              ? AppTheme.errorColor
                              : AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Actions
                if (isPaused && onResume != null)
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: onResume,
                  )
                else if (!isFailed && onPause != null)
                  IconButton(icon: const Icon(Icons.pause), onPressed: onPause),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onCancel,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Progress bar
            LinearProgressIndicator(
              value: download.progress,
              backgroundColor: AppTheme.darkCard,
              color: isFailed
                  ? AppTheme.errorColor
                  : isPaused
                  ? Colors.orange
                  : AppTheme.primaryColor,
            ),
            const SizedBox(height: 4),

            // Progress text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(download.progress * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                Text(
                  '${formatSize(download.downloadedBytes)} / ${formatSize(download.fileSizeBytes)}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    switch (download.status) {
      case 'pending':
        return 'Очікування...';
      case 'downloading':
        return 'Завантаження...';
      case 'paused':
        return 'Призупинено';
      case 'failed':
        return 'Помилка завантаження';
      default:
        return download.status;
    }
  }
}

/// Info chip widget
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
