import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../data/providers/provider_registry.dart';
import '../../../data/services/settings_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/data_transfer_service.dart';
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
  final _authService = GetIt.instance<AuthService>();
  final _dataTransferService = GetIt.instance<DataTransferService>();

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

                // Account section
                _buildAccountSection(),

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
                    SettingsTile(
                      icon: Icons.speed,
                      title: _s.defaultSpeed,
                      value: '${_settings.state.defaultSpeed}x',
                      onTap: () => _showSpeedDialog(),
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
                    SettingsSwitch(
                      icon: Icons.swipe,
                      title: _s.gestureControls,
                      subtitle: _s.gestureControlsDesc,
                      value: _settings.state.gestureControls,
                      onChanged: (value) => _settings.setGestureControls(value),
                    ),
                    SettingsSwitch(
                      icon: Icons.fast_forward,
                      title: _s.skipIntro,
                      subtitle: _s.skipIntroDesc,
                      value: _settings.state.skipIntro,
                      onChanged: (value) => _settings.setSkipIntro(value),
                    ),
                    SettingsTile(
                      icon: Icons.timer,
                      title: _s.nextEpisodeDelay,
                      value:
                          '${_settings.state.nextEpisodeDelay} ${_s.nextEpisodeDelayDesc}',
                      onTap: () => _showNextEpisodeDelayDialog(),
                    ),
                  ],
                ),

                // Watch Party section
                SettingsSection(
                  title: _s.watchParty,
                  icon: Icons.groups,
                  children: [
                    SettingsTile(
                      icon: Icons.person,
                      title: _s.watchPartyName,
                      value: _settings.state.watchPartyName,
                      onTap: () => _showWatchPartyNameDialog(),
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

                // Notifications section
                SettingsSection(
                  title: _s.notifications,
                  icon: Icons.notifications_outlined,
                  children: [
                    SettingsSwitch(
                      icon: Icons.new_releases,
                      title: _s.newEpisodeNotify,
                      subtitle: _s.newEpisodeNotifyDesc,
                      value: _settings.state.newEpisodeNotify,
                      onChanged: (value) =>
                          _settings.setNewEpisodeNotify(value),
                    ),
                    SettingsSwitch(
                      icon: Icons.system_update,
                      title: _s.updateNotify,
                      subtitle: _s.updateNotifyDesc,
                      value: _settings.state.updateNotify,
                      onChanged: (value) => _settings.setUpdateNotify(value),
                    ),
                  ],
                ),

                // Advanced section
                SettingsSection(
                  title: _s.advanced,
                  icon: Icons.settings_applications,
                  children: [
                    SettingsTile(
                      icon: Icons.devices,
                      title: _s.deviceTypeOverride,
                      value: _getDeviceTypeDisplayName(
                        _settings.state.deviceTypeOverride,
                      ),
                      onTap: () => _showDeviceTypeDialog(),
                    ),
                    SettingsSwitch(
                      icon: Icons.bug_report,
                      title: _s.debugMode,
                      subtitle: _s.debugModeDesc,
                      value: _settings.state.debugMode,
                      onChanged: (value) => _settings.setDebugMode(value),
                    ),
                    SettingsTile(
                      icon: Icons.restore,
                      title: _s.resetSettings,
                      value: _s.resetSettingsDesc,
                      onTap: () => _showResetSettingsDialog(),
                      destructive: true,
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

  Widget _buildAccountSection() {
    return ListenableBuilder(
      listenable: _authService,
      builder: (context, _) {
        if (_authService.isAuthenticated) {
          return SettingsSection(
            title: 'Акаунт',
            icon: Icons.account_circle,
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                  backgroundImage: _authService.avatarUrl != null
                      ? NetworkImage(_authService.avatarUrl!)
                      : null,
                  child: _authService.avatarUrl == null
                      ? Text(
                          _authService.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(_authService.displayName),
                subtitle: Text(
                  _authService.userEmail ?? '',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppTheme.textMuted,
                ),
                onTap: () => context.push('/profile'),
              ),
              SettingsTile(
                icon: Icons.sync,
                title: 'Синхронізація',
                value: 'Історія та обране в хмарі',
                onTap: () => _showSyncInfo(),
              ),
            ],
          );
        } else {
          return SettingsSection(
            title: 'Акаунт',
            icon: Icons.account_circle,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppTheme.primaryColor.withValues(
                        alpha: 0.2,
                      ),
                      child: const Icon(
                        Icons.person_outline,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Увійдіть в акаунт',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Синхронізуйте дані між пристроями',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => context.push('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: const Text('Увійти'),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
      },
    );
  }

  void _showSyncInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        title: const Text('Синхронізація'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ваші дані автоматично синхронізуються:'),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Історія переглядів'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Обране'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text('Позиція перегляду'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Зрозуміло'),
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

    // Separate home providers from dedicated providers
    final homeProviders = providers
        .where((p) => ProviderRegistry.showOnHome(p))
        .toList();

    final separateProviders = providers
        .where((p) => !ProviderRegistry.showOnHome(p))
        .toList();

    return [
      // Home providers section
      if (homeProviders.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
          child: Text(
            'Основні провайдери',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ...homeProviders.map((provider) {
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
        }),
      ],

      // Separate providers section (HDRezka, YouTube)
      if (separateProviders.isNotEmpty) ...[
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
          child: Text(
            'Окремі провайдери',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Ці провайдери мають власні розділи в каталозі та за замовчуванням вимкнені в загальному пошуку',
            style: TextStyle(
              color: AppTheme.textMuted.withOpacity(0.7),
              fontSize: 11,
            ),
          ),
        ),
        ...separateProviders.map((provider) {
          final isEnabled = _settings.isProviderEnabled(provider.id);
          final isSearchEnabled = _settings.isSearchEnabledForProvider(
            provider.id,
          );
          return _SeparateProviderTile(
            name: provider.name,
            url: provider.baseUrl,
            iconUrl: provider.iconUrl,
            providerId: provider.id,
            isEnabled: isEnabled,
            isSearchEnabled: isSearchEnabled,
            hasFixedStreams: ProviderRegistry.hasFixedStreams(provider),
            onEnabledChanged: (value) {
              _settings.setProviderEnabled(provider.id, value);
            },
            onSearchEnabledChanged: (value) {
              _settings.setSearchEnabledForProvider(provider.id, value);
            },
          );
        }),
      ],
    ];
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

  Future<void> _showExportDialog() async {
    try {
      await _dataTransferService.exportData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Резервну копію збережено')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Помилка експорту: $e')));
      }
    }
  }

  Future<void> _importData() async {
    try {
      await _dataTransferService.importData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Дані успішно відновлено')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Помилка імпорту: $e')));
      }
    }
  }

  Future<void> _shareData() async {
    await _showExportDialog();
  }

  String _getDeviceTypeDisplayName(String type) {
    switch (type) {
      case 'phone':
        return _s.devicePhone;
      case 'tablet':
        return _s.deviceTablet;
      case 'desktop':
        return _s.deviceDesktop;
      case 'tv':
        return _s.deviceTV;
      default:
        return _s.deviceAuto;
    }
  }

  void _showSpeedDialog() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _s.defaultSpeed,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...speeds.map((speed) {
              final isSelected = speed == _settings.state.defaultSpeed;
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : AppTheme.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.speed,
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                  ),
                ),
                title: Text(
                  '${speed}x',
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.primaryColor : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
                    : null,
                onTap: () {
                  _settings.setDefaultSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNextEpisodeDelayDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SelectionSheet<int>(
        title: _s.nextEpisodeDelay,
        items: const [0, 5, 10, 15, 30],
        selectedItem: _settings.state.nextEpisodeDelay,
        itemBuilder: (item) => SelectionItem(
          icon: Icons.timer,
          title: '$item сек',
          isSelected: item == _settings.state.nextEpisodeDelay,
        ),
        onSelected: (item) {
          _settings.setNextEpisodeDelay(item);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showWatchPartyNameDialog() {
    final controller = TextEditingController(
      text: _settings.state.watchPartyName,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(_s.watchPartyName),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: _s.enterYourName,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLength: 20,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                _settings.setWatchPartyName(name);
              }
              Navigator.pop(ctx);
            },
            child: Text(_s.save),
          ),
        ],
      ),
    );
  }

  void _showDeviceTypeDialog() {
    final types = ['auto', 'phone', 'tablet', 'desktop', 'tv'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _s.deviceTypeOverride,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...types.map((type) {
              final isSelected = type == _settings.state.deviceTypeOverride;
              return ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor.withValues(alpha: 0.15)
                        : AppTheme.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getDeviceIcon(type),
                    color: isSelected
                        ? AppTheme.primaryColor
                        : AppTheme.textSecondary,
                  ),
                ),
                title: Text(
                  _getDeviceTypeDisplayName(type),
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? AppTheme.primaryColor : null,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: AppTheme.primaryColor)
                    : null,
                onTap: () {
                  _settings.setDeviceTypeOverride(type);
                  Navigator.pop(context);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    switch (type) {
      case 'phone':
        return Icons.phone_android;
      case 'tablet':
        return Icons.tablet_android;
      case 'desktop':
        return Icons.computer;
      case 'tv':
        return Icons.tv;
      default:
        return Icons.auto_awesome;
    }
  }

  void _showResetSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(_s.resetSettings),
        content: Text(_s.resetSettingsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_s.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _settings.resetAllSettings();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(_s.settingsReset)));
              }
            },
            child: Text(
              _s.confirm,
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile for separate providers (HDRezka, YouTube) with additional settings
class _SeparateProviderTile extends StatelessWidget {
  final String name;
  final String url;
  final String? iconUrl;
  final String providerId;
  final bool isEnabled;
  final bool isSearchEnabled;
  final bool hasFixedStreams;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<bool> onSearchEnabledChanged;

  const _SeparateProviderTile({
    required this.name,
    required this.url,
    this.iconUrl,
    required this.providerId,
    required this.isEnabled,
    required this.isSearchEnabled,
    required this.hasFixedStreams,
    required this.onEnabledChanged,
    required this.onSearchEnabledChanged,
  });

  Color get _providerColor {
    switch (providerId) {
      case 'hdrezka':
        return Colors.orange;
      case 'youtube':
        return Colors.red;
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData get _providerIcon {
    switch (providerId) {
      case 'hdrezka':
        return Icons.play_circle_filled;
      case 'youtube':
        return Icons.play_arrow;
      default:
        return Icons.video_library;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? _providerColor.withOpacity(0.3)
              : AppTheme.borderColor,
        ),
      ),
      child: Column(
        children: [
          // Main toggle
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _providerColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(_providerIcon, color: _providerColor, size: 22),
            ),
            title: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isEnabled ? _providerColor : AppTheme.textMuted,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  url,
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                if (hasFixedStreams)
                  Text(
                    '⚠️ Якість/дубляж фіксуються при запуску',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade700,
                    ),
                  ),
              ],
            ),
            trailing: Switch(
              value: isEnabled,
              onChanged: onEnabledChanged,
              activeThumbColor: _providerColor,
            ),
          ),

          // Search toggle (only if provider is enabled)
          if (isEnabled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Включити в загальний пошук',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Switch(
                    value: isSearchEnabled,
                    onChanged: onSearchEnabledChanged,
                    activeThumbColor: _providerColor,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
