import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

// ============================================================================
// ENUMS & TYPE CONVERTERS
// ============================================================================

/// Download status enum for type-safe status handling
/// Using int values for efficient storage and comparison
enum DownloadStatus {
  pending(0),
  downloading(1),
  paused(2),
  completed(3),
  failed(4);

  const DownloadStatus(this.value);
  final int value;

  /// Convert from database int value
  static DownloadStatus fromValue(int value) {
    return DownloadStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => DownloadStatus.pending,
    );
  }
}

/// Type converter for DownloadStatus enum
class DownloadStatusConverter extends TypeConverter<DownloadStatus, int> {
  const DownloadStatusConverter();

  @override
  DownloadStatus fromSql(int fromDb) => DownloadStatus.fromValue(fromDb);

  @override
  int toSql(DownloadStatus value) => value.value;
}

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
  RealColumn get rating => real().nullable()();
  TextColumn get ratingSource => text().nullable()();
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
  RealColumn get rating => real().nullable()();
  TextColumn get ratingSource => text().nullable()();
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
  RealColumn get rating => real().nullable()();
  TextColumn get ratingSource => text().nullable()();
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

  // Status: uses int for efficient storage and comparison
  // Maps to DownloadStatus enum via TypeConverter
  IntColumn get status => integer()
      .withDefault(const Constant(0))
      .map(const DownloadStatusConverter())();
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

/// Search history table for autocomplete and typo learning
class SearchHistoryTable extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Original query as typed by user
  TextColumn get query => text()();

  /// Normalized query for comparison (lowercase, trimmed)
  TextColumn get normalizedQuery => text()();

  /// Number of results found for this query
  IntColumn get resultCount => integer().withDefault(const Constant(0))();

  /// Whether search returned any results
  BoolColumn get wasSuccessful => boolean().withDefault(const Constant(true))();

  /// Number of times this query was searched
  IntColumn get searchCount => integer().withDefault(const Constant(1))();

  /// When query was first searched
  DateTimeColumn get firstSearchedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// When query was last searched
  DateTimeColumn get lastSearchedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {normalizedQuery},
  ];
}

/// Metadata cache for all encountered media items
class StoredMediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get providerId => text()();
  TextColumn get title => text()();
  TextColumn get originalTitle => text().nullable()();
  TextColumn get posterUrl => text().nullable()();
  IntColumn get year => integer().nullable()();
  RealColumn get rating => real().nullable()();
  TextColumn get mediaType => text()(); // movie, series, cartoon, anime
  TextColumn get description => text().nullable()();
  TextColumn get genres => text().nullable()(); // Comma-separated
  TextColumn get country => text().nullable()();
  TextColumn get ratingSource => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {providerId, id};
}

// ============================================================================
// DATABASE
// ============================================================================

@DriftDatabase(
  tables: [
    AppSettings,
    EnabledProviders,
    Favorites,
    WatchHistory,
    Downloads,
    SearchHistoryTable,
    StoredMediaItems,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 7;

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
        // Migration: convert status from TEXT to INTEGER
        if (from < 3) {
          // Create a temporary table with the new schema
          await customStatement('''
            CREATE TABLE downloads_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              media_id TEXT NOT NULL,
              provider_id TEXT NOT NULL,
              title TEXT NOT NULL,
              poster_url TEXT,
              year INTEGER,
              media_type TEXT NOT NULL,
              season INTEGER,
              episode INTEGER,
              episode_title TEXT,
              stream_url TEXT NOT NULL,
              local_path TEXT NOT NULL,
              quality TEXT NOT NULL,
              voiceover TEXT,
              status INTEGER NOT NULL DEFAULT 0,
              progress REAL NOT NULL DEFAULT 0.0,
              file_size_bytes INTEGER NOT NULL DEFAULT 0,
              downloaded_bytes INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now') * 1000),
              completed_at INTEGER,
              UNIQUE(media_id, provider_id, season, episode)
            )
          ''');

          // Copy data with status conversion
          await customStatement('''
            INSERT INTO downloads_new 
            SELECT id, media_id, provider_id, title, poster_url, year, media_type,
                   season, episode, episode_title, stream_url, local_path, quality, voiceover,
                   CASE status
                     WHEN 'pending' THEN 0
                     WHEN 'downloading' THEN 1
                     WHEN 'paused' THEN 2
                     WHEN 'completed' THEN 3
                     WHEN 'failed' THEN 4
                     ELSE 0
                   END,
                   progress, file_size_bytes, downloaded_bytes, created_at, completed_at
            FROM downloads
          ''');

          // Drop old table and rename new one
          await customStatement('DROP TABLE downloads');
          await customStatement(
            'ALTER TABLE downloads_new RENAME TO downloads',
          );
        }
        // Migration: add SearchHistoryTable
        if (from < 4) {
          await m.createTable(searchHistoryTable);
        }
        // Migration: remove all filmix provider data (provider removed)
        if (from < 5) {
          await customStatement(
            "DELETE FROM favorites WHERE provider_id = 'filmix'",
          );
          await customStatement(
            "DELETE FROM watch_history WHERE provider_id = 'filmix'",
          );
          await customStatement(
            "DELETE FROM downloads WHERE provider_id = 'filmix'",
          );
          await customStatement(
            "DELETE FROM enabled_providers WHERE provider_id = 'filmix'",
          );
        }
        // Migration: add MediaItems table
        if (from < 6) {
          await m.createTable(storedMediaItems);
        }
        // Migration: add ratingSource/rating to various tables
        if (from < 7) {
          await customStatement('ALTER TABLE favorites ADD COLUMN rating REAL');
          await customStatement(
            'ALTER TABLE favorites ADD COLUMN rating_source TEXT',
          );
          await customStatement(
            'ALTER TABLE watch_history ADD COLUMN rating REAL',
          );
          await customStatement(
            'ALTER TABLE watch_history ADD COLUMN rating_source TEXT',
          );
          await customStatement('ALTER TABLE downloads ADD COLUMN rating REAL');
          await customStatement(
            'ALTER TABLE downloads ADD COLUMN rating_source TEXT',
          );
          await customStatement(
            'ALTER TABLE stored_media_items ADD COLUMN rating_source TEXT',
          );
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
