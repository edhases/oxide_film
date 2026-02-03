import 'package:flutter/material.dart';

/// Application locale
enum AppLocale {
  uk,
  en;

  String get displayName {
    switch (this) {
      case AppLocale.uk:
        return 'Українська';
      case AppLocale.en:
        return 'English';
    }
  }

  String get code => name;

  Locale get locale => Locale(name);

  static AppLocale fromCode(String? code) {
    return AppLocale.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLocale.uk,
    );
  }
}

/// Localization strings
class AppStrings {
  final AppLocale locale;

  AppStrings(this.locale);

  // Factory for getting localized instance
  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        AppStrings(AppLocale.uk);
  }

  // ============================================================================
  // GENERAL
  // ============================================================================

  String get appName => 'Oxide Film';
  String get loading => _t('Завантаження...', 'Loading...');
  String get error => _t('Помилка', 'Error');
  String get retry => _t('Спробувати знову', 'Try again');
  String get cancel => _t('Скасувати', 'Cancel');
  String get save => _t('Зберегти', 'Save');
  String get delete => _t('Видалити', 'Delete');
  String get confirm => _t('Підтвердити', 'Confirm');
  String get back => _t('Назад', 'Back');
  String get close => _t('Закрити', 'Close');
  String get search => _t('Пошук', 'Search');
  String get settings => _t('Налаштування', 'Settings');
  String get language => _t('Мова', 'Language');

  // ============================================================================
  // HOME
  // ============================================================================

  String get home => _t('Головна', 'Home');
  String get popular => _t('Популярне', 'Popular');
  String get favorites => _t('Обране', 'Favorites');
  String get history => _t('Історія', 'History');
  String get noContent => _t('Немає контенту', 'No content');
  String get loadingError => _t('Помилка завантаження', 'Loading error');

  // ============================================================================
  // CONTENT TYPES
  // ============================================================================

  String get movie => _t('Фільм', 'Movie');
  String get movies => _t('Фільми', 'Movies');
  String get series => _t('Серіал', 'Series');
  String get seriesPlural => _t('Серіали', 'Series');
  String get cartoon => _t('Мультфільм', 'Cartoon');
  String get cartoons => _t('Мультфільми', 'Cartoons');
  String get anime => _t('Аніме', 'Anime');
  String get animePlural => _t('Аніме', 'Anime');

  // ============================================================================
  // PLAYER
  // ============================================================================

  String get player => _t('Плеєр', 'Player');
  String get builtIn => _t('Вбудований', 'Built-in');
  String get external => _t('Зовнішній', 'External');
  String get quality => _t('Якість', 'Quality');
  String get defaultQuality => _t('Якість за замовчуванням', 'Default quality');
  String get speed => _t('Швидкість', 'Speed');
  String get voiceover => _t('Озвучка', 'Voiceover');
  String get subtitles => _t('Субтитри', 'Subtitles');
  String get autoPlayNext => _t('Автовідтворення наступного', 'Auto-play next');
  String get autoPlayNextDesc => _t(
    'Автоматично запускати наступну серію',
    'Automatically play next episode',
  );
  String get rememberPosition =>
      _t('Запам\'ятовувати позицію', 'Remember position');
  String get rememberPositionDesc =>
      _t('Продовжувати з місця зупинки', 'Continue from where you left off');
  String get playbackSettings =>
      _t('Налаштування відтворення', 'Playback settings');
  String get watch => _t('Дивитися', 'Watch');
  String get noSources => _t('Немає джерел', 'No sources');
  String resumedFrom(String time) =>
      _t('Продовжено з $time', 'Resumed from $time');

  // ============================================================================
  // DETAILS
  // ============================================================================

  String get description => _t('Опис', 'Description');
  String get actors => _t('Актори', 'Actors');
  String get seasonsAndEpisodes => _t('Сезони та серії', 'Seasons & Episodes');
  String season(int n) => _t('Сезон $n', 'Season $n');
  String episode(int n) => _t('Серія $n', 'Episode $n');
  String get availableSources => _t('Доступні джерела', 'Available sources');
  String get addToFavorites => _t('Додати до обраного', 'Add to favorites');
  String get removeFromFavorites =>
      _t('Видалити з обраного', 'Remove from favorites');
  String get addedToFavorites => _t('Додано до обраного', 'Added to favorites');
  String get removedFromFavorites =>
      _t('Видалено з обраного', 'Removed from favorites');
  String get watchParty => _t('Спільний перегляд', 'Watch party');

  // ============================================================================
  // SETTINGS
  // ============================================================================

  String get contentSources => _t('Джерела контенту', 'Content sources');
  String get playback => _t('Відтворення', 'Playback');
  String get appearance => _t('Зовнішній вигляд', 'Appearance');
  String get theme => _t('Тема', 'Theme');
  String get dark => _t('Темна', 'Dark');
  String get amoled => _t('AMOLED', 'AMOLED');
  String get light => _t('Світла', 'Light');
  String get system => _t('Системна', 'System');
  String get customization => _t('Кастомізація', 'Customization');
  String get customizationDesc =>
      _t('Розмір постерів, кольори, сітка', 'Poster size, colors, grid');
  String get data => _t('Дані', 'Data');
  String get sync => _t('Синхронізація', 'Sync');
  String get export => _t('Експорт даних', 'Export data');
  String get exportDesc =>
      _t('Зберегти обране та історію', 'Save favorites and history');
  String get import => _t('Імпорт даних', 'Import data');
  String get importDesc => _t('Відновити з файлу', 'Restore from file');
  String get share => _t('Поділитись даними', 'Share data');
  String get shareDesc => _t('Надіслати копію', 'Send a copy');
  String get downloads => _t('Завантаження', 'Downloads');
  String get offlineContent => _t('Офлайн контент', 'Offline content');
  String get clearCache => _t('Очистити кеш', 'Clear cache');
  String get clearCacheDesc =>
      _t('Видалити тимчасові файли', 'Delete temporary files');
  String get statistics => _t('Статистика', 'Statistics');
  String get statsDesc =>
      _t('Переглянуті фільми, час, жанри', 'Watched movies, time, genres');
  String get about => _t('Про додаток', 'About');
  String get version => _t('Версія', 'Version');
  String get sourceCode => _t('Вихідний код', 'Source code');
  String get sourceCodeDesc =>
      _t('Вихідний код проєкту', 'Project source code');
  String get historyDesc => _t('Переглянути або очистити', 'View or clear');
  String get favoritesDesc => _t('Керування списком', 'Manage list');

  // Settings dialogs
  String get selectLanguage => _t('Оберіть мову', 'Select language');
  String get selectTheme => _t('Оберіть тему', 'Select theme');
  String get selectPlayer => _t('Оберіть плеєр', 'Select player');
  String get builtInPlayer =>
      _t('Вбудований media_kit плеєр', 'Built-in media_kit player');
  String get externalPlayerDesc =>
      _t('VLC, MX Player, тощо', 'VLC, MX Player, etc.');
  String get confirmClearCache => _t('Очистити кеш?', 'Clear cache?');
  String get clearCacheConfirmText => _t(
    'Це видалить всі тимчасові файли та кешовані зображення. Історія та обране залишаться.',
    'This will delete all temporary files and cached images. History and favorites will remain.',
  );
  String get cacheCleared => _t('Кеш очищено', 'Cache cleared');
  String get noProviders => _t('Немає провайдерів', 'No providers');
  String get addContentSources =>
      _t('Додайте джерела контенту', 'Add content sources');
  String exportSuccess(String path) => _t('Збережено: $path', 'Saved: $path');
  String get importSuccess =>
      _t('Дані успішно імпортовано!', 'Data imported successfully!');
  String importError(String error) =>
      _t('Помилка імпорту: $error', 'Import error: $error');
  String get willExport => _t('Буде експортовано:', 'Will export:');
  String favoritesCount(int n) =>
      _t('Обране: $n елементів', 'Favorites: $n items');
  String historyCount(int n) =>
      _t('Історія: $n записів', 'History: $n entries');
  String get settingsLabel => _t('Налаштування', 'Settings');
  String get exportWillSaveAsJson =>
      _t('Файл буде збережено у форматі JSON.', 'File will be saved as JSON.');
  String get exportButton => _t('Експортувати', 'Export');
  String get clearButton => _t('Очистити', 'Clear');
  String get openLinkError =>
      _t('Не вдалося відкрити посилання', 'Failed to open link');

  // ============================================================================
  // FILTERS
  // ============================================================================

  String get filters => _t('Фільтри', 'Filters');
  String get sort => _t('Сортування', 'Sort');
  String get sortBy => _t('Сортувати за', 'Sort by');
  String get ascending => _t('За зростанням', 'Ascending');
  String get descending => _t('За спаданням', 'Descending');
  String get title => _t('Назва', 'Title');
  String get year => _t('Рік', 'Year');
  String get rating => _t('Рейтинг', 'Rating');
  String get type => _t('Тип', 'Type');
  String get genre => _t('Жанр', 'Genre');
  String get country => _t('Країна', 'Country');
  String get clearFilters => _t('Скинути фільтри', 'Clear filters');
  String get apply => _t('Застосувати', 'Apply');
  String get noResults => _t('Нічого не знайдено', 'Nothing found');
  String get tryChangingFilters =>
      _t('Спробуйте змінити фільтри', 'Try changing filters');
  String results(int count) => _t('Результати ($count)', 'Results ($count)');

  // ============================================================================
  // WATCH PARTY
  // ============================================================================

  String get createRoom => _t('Створити кімнату', 'Create room');
  String get joinRoom => _t('Приєднатися до кімнати', 'Join room');
  String get yourName => _t('Ваше ім\'я', 'Your name');
  String get enterYourName => _t('Введіть ваше ім\'я', 'Enter your name');
  String get ipAddress => _t('IP адреса', 'IP address');
  String get port => _t('Порт', 'Port');
  String get connecting => _t('Підключення...', 'Connecting...');
  String get connected => _t('Підключено', 'Connected');
  String get youAreHost => _t('Ви хост', 'You are the host');
  String get connectedToHost => _t('Підключено до хоста', 'Connected to host');
  String get connectionCode => _t('Код підключення', 'Connection code');
  String get copyCode => _t('Копіювати код', 'Copy code');
  String get codeCopied => _t('Код скопійовано', 'Code copied');
  String get participants => _t('Учасники', 'Participants');
  String get chat => _t('Чат', 'Chat');
  String get writeFirstMessage =>
      _t('Напишіть перше повідомлення!', 'Write the first message!');
  String get sendMessage =>
      _t('Написати повідомлення...', 'Write a message...');
  String get leaveRoom => _t('Вийти з кімнати', 'Leave room');
  String get leaveRoomConfirm => _t(
    'Ви покинете спільний перегляд. Продовжити?',
    'You will leave the watch party. Continue?',
  );
  String get connectionError => _t('Помилка підключення', 'Connection error');
  String get host => _t('Хост', 'Host');

  // ============================================================================
  // NOTIFICATIONS
  // ============================================================================

  String get newEpisodes => _t('Нові серії', 'New episodes');
  String get noNewEpisodes => _t('Немає нових серій', 'No new episodes');
  String newEpisodesAvailable(int count) =>
      _t('Доступно $count нових серій', '$count new episodes available');

  // ============================================================================
  // STATISTICS
  // ============================================================================

  String get totalWatched => _t('Всього переглянуто', 'Total watched');
  String get totalTime => _t('Загальний час', 'Total time');
  String get favoriteType => _t('Улюблений тип', 'Favorite type');
  String get topProvider => _t('Топ провайдер', 'Top provider');
  String get weeklyActivity => _t('Активність за тиждень', 'Weekly activity');
  String get byType => _t('За типом', 'By type');
  String get byProvider => _t('За провайдером', 'By provider');
  String get monthly => _t('По місяцях', 'Monthly');
  String hours(int h) => _t('$h год', '${h}h');

  // ============================================================================
  // PRIVATE HELPER
  // ============================================================================

  String _t(String uk, String en) {
    switch (locale) {
      case AppLocale.uk:
        return uk;
      case AppLocale.en:
        return en;
    }
  }
}

/// Localization delegate
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  final AppLocale locale;

  const AppStringsDelegate({this.locale = AppLocale.uk});

  @override
  bool isSupported(Locale locale) {
    return ['uk', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(AppLocale.fromCode(locale.languageCode));
  }

  @override
  bool shouldReload(AppStringsDelegate old) => old.locale != locale;
}
