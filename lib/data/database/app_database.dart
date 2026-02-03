import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ============================================================================
// TABLES
// ============================================================================

/// Application settings table
class AppSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Enabled providers table
class EnabledProviders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get providerId => text().unique()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Favorites table for saved media
class Favorites extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaId => text()();
  TextColumn get providerId => text()();
  TextColumn get title => text()();
  TextColumn get posterUrl => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get mediaType => text()(); // movie, series, cartoon, anime
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {mediaId, providerId},
  ];
}

/// Watch history table
class WatchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaId => text()();
  TextColumn get providerId => text()();
  TextColumn get title => text()();
  TextColumn get posterUrl => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get mediaType => text()();

  // Playback position
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();

  // For series - track episode
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  TextColumn get episodeTitle => text().nullable()();

  // Stream info
  TextColumn get lastStreamUrl => text().nullable()();
  TextColumn get voiceover => text().nullable()();

  DateTimeColumn get watchedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {mediaId, providerId, season, episode},
  ];
}

/// Downloads table for offline viewing
class Downloads extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaId => text()();
  TextColumn get providerId => text()();
  TextColumn get title => text()();
  TextColumn get posterUrl => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get mediaType => text()();

  // Episode info (for series)
  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();
  TextColumn get episodeTitle => text().nullable()();

  // Download info
  TextColumn get streamUrl => text()();
  TextColumn get localPath => text()();
  TextColumn get quality => text()();
  TextColumn get voiceover => text().nullable()();

  // Status: pending, downloading, paused, completed, failed
  TextColumn get status => text().withDefault(const Constant('pending'))();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  IntColumn get fileSizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {mediaId, providerId, season, episode},
  ];
}

// ============================================================================
// DATABASE
// ============================================================================

@DriftDatabase(
  tables: [AppSettings, EnabledProviders, Favorites, WatchHistory, Downloads],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 2;

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'oxide_film',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationDocumentsDirectory,
      ),
    );
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Insert default settings
        await _insertDefaultSettings();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Migration for Downloads table
        if (from < 2) {
          await m.createTable(downloads);
        }
      },
    );
  }

  Future<void> _insertDefaultSettings() async {
    final defaults = {
      'theme': 'dark',
      'default_quality': 'auto',
      'player_type': 'internal',
      'auto_play_next': 'true',
      'remember_position': 'true',
      'subtitle_language': 'uk',
    };

    for (final entry in defaults.entries) {
      await into(appSettings).insert(
        AppSettingsCompanion.insert(key: entry.key, value: entry.value),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }
}
