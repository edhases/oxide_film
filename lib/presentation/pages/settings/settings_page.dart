import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../data/providers/provider_registry.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_titlebar.dart';
import '../../widgets/settings_widgets.dart';

/// Settings page with full functionality and localization
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _registry = GetIt.instance<ProviderRegistry>();
  final _settings = GetIt.instance<SettingsService>();
  final _syncService = GetIt.instance<SyncService>();

  AppStrings get _s => AppStrings.of(context);

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (_isDesktop) const CustomTitleBar(),
          _buildAppBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                const SizedBox(height: 8),

                // Providers section
                SettingsSection(
                  title: _s.contentSources,
                  icon: Icons.source,
                  children: _buildProvidersList(),
                ),

                // Playback section
                SettingsSection(
                  title: _s.playback,
                  icon: Icons.play_circle_outline,
                  children: [
                    SettingsTile(
                      icon: Icons.smart_display,
                      title: _s.player,
                      value: _settings.state.playerType.displayName,
                      onTap: () => _showPlayerTypeDialog(),
                    ),
                    SettingsTile(
                      icon: Icons.high_quality,
                      title: _s.defaultQuality,
                      value: _settings.state.defaultQuality.displayName,
                      onTap: () => _showQualityDialog(),
                    ),
                    SettingsSwitch(
                      icon: Icons.skip_next,
                      title: _s.autoPlayNext,
                      subtitle: _s.autoPlayNextDesc,
                      value: _settings.state.autoPlayNext,
                      onChanged: (value) => _settings.setAutoPlayNext(value),
                    ),
                    SettingsSwitch(
                      icon: Icons.bookmark,
                      title: _s.rememberPosition,
                      subtitle: _s.rememberPositionDesc,
                      value: _settings.state.rememberPosition,
                      onChanged: (value) =>
                          _settings.setRememberPosition(value),
                    ),
                  ],
                ),

                // Appearance section
                SettingsSection(
                  title: _s.appearance,
                  icon: Icons.palette,
                  children: [
                    SettingsTile(
                      icon: Icons.language,
                      title: _s.language,
                      value: _settings.state.locale.displayName,
                      onTap: () => _showLanguageDialog(),
                    ),
                    SettingsTile(
                      icon: Icons.dark_mode,
                      title: _s.theme,
                      value: _settings.state.theme.displayName,
                      onTap: () => _showThemeDialog(),
                    ),
                    SettingsTile(
                      icon: Icons.tune,
                      title: _s.customization,
                      value: _s.customizationDesc,
                      onTap: () => context.push('/appearance'),
                    ),
                  ],
                ),

                // Data section
                SettingsSection(
                  title: _s.data,
                  icon: Icons.storage,
                  children: [
                    SettingsTile(
                      icon: Icons.history,
                      title: _s.history,
                      value: _s.historyDesc,
                      onTap: () => context.push('/history'),
                    ),
                    SettingsTile(
                      icon: Icons.favorite,
                      title: _s.favorites,
                      value: _s.favoritesDesc,
                      onTap: () => context.push('/favorites'),
                    ),
                    SettingsTile(
                      icon: Icons.bar_chart,
                      title: _s.statistics,
                      value: _s.statsDesc,
                      onTap: () => context.push('/stats'),
                    ),
                    SettingsTile(
                      icon: Icons.download_for_offline,
                      title: _s.downloads,
                      value: _s.offlineContent,
                      onTap: () => context.push('/downloads'),
                    ),
                    SettingsTile(
                      icon: Icons.delete_sweep,
                      title: _s.clearCache,
                      value: _s.clearCacheDesc,
                      onTap: () => _showClearCacheDialog(),
                      destructive: true,
                    ),
                  ],
                ),

                // Sync section
                SettingsSection(
                  title: _s.sync,
                  icon: Icons.sync,
                  children: [
                    SettingsTile(
                      icon: Icons.upload,
                      title: _s.export,
                      value: _s.exportDesc,
                      onTap: () => _showExportDialog(),
                    ),
                    SettingsTile(
                      icon: Icons.download,
                      title: _s.import,
                      value: _s.importDesc,
                      onTap: () => _importData(),
                    ),
                    SettingsTile(
                      icon: Icons.share,
                      title: _s.share,
                      value: _s.shareDesc,
                      onTap: () => _shareData(),
                    ),
                  ],
                ),

                // About section
                SettingsSection(
                  title: _s.about,
                  icon: Icons.info_outline,
                  children: [
                    SettingsTile(
                      icon: Icons.movie_filter,
                      title: _s.appName,
                      value: '${_s.version} 1.0.0',
                      onTap: () => _showAboutDialog(),
                    ),
                    SettingsTile(
                      icon: Icons.code,
                      title: 'GitHub',
                      value: _s.sourceCodeDesc,
                      onTap: () => _openGitHub(),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
              ],
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
            tooltip: _s.back,
          ),
          const SizedBox(width: 8),
          Text(
            _s.settings,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProvidersList() {
    final providers = _registry.all;

    if (providers.isEmpty) {
      return [const EmptyProviders()];
    }

    return providers.map((provider) {
      final isEnabled = _settings.isProviderEnabled(provider.id);
      return ProviderTile(
        name: provider.name,
        url: provider.baseUrl,
        iconUrl: provider.iconUrl,
        isEnabled: isEnabled,
        onChanged: (value) {
          _settings.setProviderEnabled(provider.id, value);
        },
      );
    }).toList();
  }

  // ============================================================================
  // DIALOGS
  // ============================================================================

  void _showLanguageDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SelectionSheet<AppLocale>(
        title: _s.selectLanguage,
        items: AppLocale.values,
        selectedItem: _settings.state.locale,
        itemBuilder: (item) => SelectionItem(
          icon: Icons.language,
          title: item.displayName,
          isSelected: item == _settings.state.locale,
        ),
        onSelected: (item) {
          _settings.setLocale(item);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showThemeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SelectionSheet<AppThemeMode>(
        title: _s.selectTheme,
        items: AppThemeMode.values,
        selectedItem: _settings.state.theme,
        itemBuilder: (item) => SelectionItem(
          icon: _getThemeIcon(item),
          title: item.displayName,
          isSelected: item == _settings.state.theme,
        ),
        onSelected: (item) {
          _settings.setTheme(item);
          Navigator.pop(context);
        },
      ),
    );
  }

  IconData _getThemeIcon(AppThemeMode theme) {
    switch (theme) {
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.amoled:
        return Icons.brightness_1;
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  void _showQualityDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SelectionSheet<DefaultQuality>(
        title: _s.defaultQuality,
        items: DefaultQuality.values,
        selectedItem: _settings.state.defaultQuality,
        itemBuilder: (item) => SelectionItem(
          icon: Icons.hd,
          title: item.displayName,
          isSelected: item == _settings.state.defaultQuality,
        ),
        onSelected: (item) {
          _settings.setDefaultQuality(item);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showPlayerTypeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SelectionSheet<PlayerType>(
        title: _s.selectPlayer,
        items: PlayerType.values,
        selectedItem: _settings.state.playerType,
        itemBuilder: (item) => SelectionItem(
          icon: item == PlayerType.internal
              ? Icons.play_circle_filled
              : Icons.open_in_new,
          title: item.displayName,
          subtitle: item == PlayerType.internal
              ? _s.builtInPlayer
              : _s.externalPlayerDesc,
          isSelected: item == _settings.state.playerType,
        ),
        onSelected: (item) {
          _settings.setPlayerType(item);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(_s.confirmClearCache),
        content: Text(_s.clearCacheConfirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearCache();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_s.cacheCleared)));
              }
            },
            child: Text(
              _s.clearButton,
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: _s.appName,
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 Open Source',
      applicationIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppTheme.primaryColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.movie_filter, size: 40, color: Colors.white),
      ),
    );
  }

  void _openGitHub() async {
    const url = 'https://github.com/oxide-film/oxide-film';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_s.openLinkError)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${_s.error}: $e')));
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      await CachedNetworkImage.evictFromCache('');
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      debugPrint('Cache cleared successfully');
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(_s.export),
        content: FutureBuilder<Map<String, int>>(
          future: _syncService.getDataStats(),
          builder: (context, snapshot) {
            final stats = snapshot.data ?? {'favorites': 0, 'history': 0};
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s.willExport),
                const SizedBox(height: 8),
                Text('• ${_s.favoritesCount(stats['favorites'] ?? 0)}'),
                Text('• ${_s.historyCount(stats['history'] ?? 0)}'),
                Text('• ${_s.settingsLabel}'),
                const SizedBox(height: 16),
                Text(
                  _s.exportWillSaveAsJson,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final path = await _syncService.exportData();
              if (path != null && mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_s.exportSuccess(path))));
              }
            },
            child: Text(_s.exportButton),
          ),
        ],
      ),
    );
  }

  Future<void> _importData() async {
    final result = await _syncService.importData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result
                ? _s.importSuccess
                : _s.importError(_syncService.lastError ?? ''),
          ),
        ),
      );
    }
  }

  Future<void> _shareData() async {
    await _syncService.exportAndShare();
  }
}
