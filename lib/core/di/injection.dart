import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import '../network/api_client.dart';
import '../../data/providers/provider_registry.dart';
import '../../data/providers/uakino_provider.dart';
// import '../../data/providers/hdrezka_provider.dart';
import '../../data/providers/filmix_provider.dart';
import '../../data/providers/eneyida_provider.dart';
import '../../data/providers/yummyanime_provider.dart';
import '../../data/providers/uaflix_provider.dart';
import '../../data/providers/uaserials_provider.dart';
import '../../data/database/app_database.dart';
import '../../data/services/settings_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/history_service.dart';
import '../../data/services/sync_service.dart';
import '../../data/services/download_service.dart';
import '../../data/services/stats_service.dart';
import '../../data/services/episode_update_service.dart';
import '../../data/services/watch_party_service.dart';
import '../../data/services/auth_service.dart';
// External API services
import '../../data/services/tmdb_service.dart';
import '../../data/services/jikan_service.dart';
import '../../data/services/tvmaze_service.dart';

/// Service locator instance
final getIt = GetIt.instance;

/// Initialize all dependencies
@InjectableInit()
Future<void> configureDependencies() async {
  // Database (must be first)
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);

  // Core services - register ApiClient first
  getIt.registerLazySingleton<ApiClient>(() => ApiClient());

  // Auth service (must be early as others may depend on it)
  getIt.registerLazySingleton<AuthService>(() => AuthService());

  // Services
  getIt.registerLazySingleton<SettingsService>(() => SettingsService(database));
  getIt.registerLazySingleton<FavoritesService>(
    () => FavoritesService(database),
  );
  getIt.registerLazySingleton<HistoryService>(() => HistoryService(database));
  getIt.registerLazySingleton<SyncService>(() => SyncService(database));
  getIt.registerLazySingleton<DownloadService>(
    () => DownloadService(database, getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<StatsService>(() => StatsService(database));
  getIt.registerLazySingleton<WatchPartyService>(() => WatchPartyService());

  // External API services
  getIt.registerLazySingleton<TMDbService>(
    () => TMDbService(getIt<ApiClient>(), getIt<SettingsService>()),
  );
  getIt.registerLazySingleton<JikanService>(
    () => JikanService(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<TVMazeService>(
    () => TVMazeService(getIt<ApiClient>()),
  );

  // Provider registry
  getIt.registerLazySingleton<ProviderRegistry>(() => ProviderRegistry());

  // Register content providers
  _registerProviders();

  // Episode update service (depends on registry)
  getIt.registerLazySingleton<EpisodeUpdateService>(
    () => EpisodeUpdateService(database, getIt<ProviderRegistry>()),
  );
}

void _registerProviders() {
  final registry = getIt<ProviderRegistry>();
  final apiClient = getIt<ApiClient>();

  // Ukrainian providers
  registry.register(UakinoProvider(apiClient));
  registry.register(EneyidaProvider(apiClient));
  registry.register(UaflixProvider(apiClient));
  registry.register(UaserialsProvider(apiClient));

  // Multi-language providers
  // registry.register(HdrezkaProvider(apiClient));
  registry.register(FilmixProvider(apiClient));

  // Anime providers
  registry.register(YummyAnimeProvider(apiClient));
}
