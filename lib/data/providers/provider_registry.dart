import 'package:get_it/get_it.dart';

import '../../domain/entities/media_item.dart';
import '../../domain/repositories/content_provider.dart';
import '../../core/utils/logger.dart';
import '../services/settings_service.dart';

/// Registry for managing content providers
///
/// Provides access to all registered providers and allows
/// enabling/disabling them at runtime
class ProviderRegistry {
  static const String _tag = 'ProviderRegistry';

  final List<ContentProvider> _providers = [];

  /// Get settings service (lazy to avoid circular dependency)
  SettingsService? get _settings {
    try {
      return GetIt.instance<SettingsService>();
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

  /// Clear all registered providers
  void clear() {
    _providers.clear();
  }
}
