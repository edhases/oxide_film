import 'package:get_it/get_it.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/repositories/content_provider.dart';
import '../../core/utils/logger.dart';
import '../services/settings_service.dart';
import '../services/url_resolver_service.dart';

/// Registry for managing content providers
///
/// Provides access to all registered providers and allows
/// enabling/disabling them at runtime.
///
/// Includes automatic URL resolution for providers whose domains change.
class ProviderRegistry {
  static const String _tag = 'ProviderRegistry';

  final List<ContentProvider> _providers = [];

  /// Map of provider ID to resolved base URL
  final Map<String, String> _resolvedUrls = {};

  /// Whether URL resolution has been performed
  bool _urlsResolved = false;

  /// Get settings service (lazy to avoid circular dependency)
  SettingsService? get _settings {
    try {
      return GetIt.instance<SettingsService>();
    } catch (_) {
      return null;
    }
  }

  /// Get URL resolver service
  UrlResolverService? get _urlResolver {
    try {
      return GetIt.instance<UrlResolverService>();
    } catch (_) {
      return null;
    }
  }

  /// Register a new provider
  void register(ContentProvider provider) {
    if (_providers.any((p) => p.id == provider.id)) {
      Logger.w('Provider ${provider.id} already registered', tag: _tag);
      return;
    }
    _providers.add(provider);
    Logger.i('Registered provider: ${provider.name}', tag: _tag);
  }

  /// Unregister a provider by ID
  void unregister(String providerId) {
    _providers.removeWhere((p) => p.id == providerId);
    _resolvedUrls.remove(providerId);
  }

  /// Get all registered providers
  List<ContentProvider> get all => List.unmodifiable(_providers);

  /// Get only enabled providers (checks SettingsService)
  List<ContentProvider> get enabled {
    final settings = _settings;
    if (settings == null) {
      return _providers.where((p) => p.isEnabled).toList();
    }
    return _providers.where((p) => settings.isProviderEnabled(p.id)).toList();
  }

  /// Get provider by ID
  ContentProvider? getById(String id) {
    try {
      return _providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get providers that support a specific content type
  List<ContentProvider> getByContentType(ContentType type) {
    return enabled.where((p) => p.supportedTypes.contains(type)).toList();
  }

  /// Get resolved URL for a provider (or default if not resolved)
  String getResolvedUrl(String providerId) {
    return _resolvedUrls[providerId] ?? getById(providerId)?.baseUrl ?? '';
  }

  /// Initialize URL resolution for all providers
  ///
  /// This should be called once at app startup to detect domain changes.
  /// It runs in background and doesn't block the UI.
  Future<void> resolveProviderUrls() async {
    if (_urlsResolved) return;

    final resolver = _urlResolver;
    if (resolver == null) {
      Logger.w('URL resolver not available', tag: _tag);
      return;
    }

    Logger.i('Resolving provider URLs...', tag: _tag);

    for (final provider in _providers) {
      try {
        final resolvedUrl = await resolver.resolveUrl(provider.baseUrl);
        _resolvedUrls[provider.id] = resolvedUrl;

        if (resolvedUrl != provider.baseUrl) {
          Logger.i(
            '${provider.name}: ${provider.baseUrl} -> $resolvedUrl',
            tag: _tag,
          );
        }
      } catch (e) {
        Logger.w('Failed to resolve URL for ${provider.name}: $e', tag: _tag);
        _resolvedUrls[provider.id] = provider.baseUrl;
      }
    }

    _urlsResolved = true;
    Logger.i('Provider URLs resolved', tag: _tag);
  }

  /// Force refresh URLs for all providers
  Future<void> refreshProviderUrls() async {
    _urlsResolved = false;
    _resolvedUrls.clear();

    final resolver = _urlResolver;
    if (resolver != null) {
      await resolver.clearCache();
    }

    await resolveProviderUrls();
  }

  /// Clear all registered providers
  void clear() {
    _providers.clear();
    _resolvedUrls.clear();
    _urlsResolved = false;
  }
}
