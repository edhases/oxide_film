/// Application configuration constants
class AppConfig {
  AppConfig._();

  static const String appName = 'Oxide Film';
  static const String appVersion = '1.0.0';

  // TMDB API (user should set their own key)
  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String tmdbImageBaseUrl = 'https://image.tmdb.org/t/p';
  static String? tmdbApiKey;

  // User-Agent for web scraping
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Cache settings
  static const Duration cacheMaxAge = Duration(hours: 24);
}
