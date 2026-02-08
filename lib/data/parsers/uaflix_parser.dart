import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../domain/entities/entities.dart';

class UaflixParser {
  static const String baseUrl = 'https://uafix.net';

  static List<MediaItem> parseSearchResults(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // UAFlix search results use a.sres-wrap
    final searchCards = soup.findAll('a', class_: 'sres-wrap');

    if (searchCards.isNotEmpty) {
      for (final card in searchCards) {
        final item = _parseSearchCard(card);
        if (item != null) items.add(item);
      }
    } else {
      // Fallback to list page format (div.video-item)
      final listCards = soup.findAll('div', class_: 'video-item');
      for (final card in listCards) {
        final item = _parseCard(card);
        if (item != null) items.add(item);
      }
    }

    return items;
  }

  static MediaItem? _parseSearchCard(dynamic card) {
    try {
      final href = card.attributes['href'] ?? '';
      if (href.isEmpty) return null;

      final mediaId = extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      // Image is in div.sres-img > img
      final imgDiv = card.find('div', class_: 'sres-img');
      final img = imgDiv?.find('img');
      final posterUrl = img?.attributes['src'];
      final title = img?.attributes['alt']?.trim() ?? '';

      if (title.isEmpty) return null;

      // Extract year from title (format: "Title (Year)" or "Title / English Title")
      int? year;
      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }

      // Fallback: try to find year in URL
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})/?$').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      // Clean title - remove English part after / and (Year)
      var cleanTitle = title.replaceAll(RegExp(r'\(\d{4}\)'), '').trim();
      if (cleanTitle.contains(' / ')) {
        cleanTitle = cleanTitle.split(' / ').first.trim();
      }

      // Determine content type from URL
      ContentType type = ContentType.movie;
      if (href.contains('/serials/')) {
        type = ContentType.series;
      } else if (href.contains('/anime/')) {
        type = ContentType.anime;
      } else if (href.contains('/dorama/')) {
        type = ContentType.dorama;
      } else if (href.contains('/cartoons/') || href.contains('/mult')) {
        type = ContentType.cartoon;
      }

      return MediaItem(
        id: mediaId,
        title: cleanTitle,
        originalTitle: title.contains(' / ')
            ? title.split(' / ').last.trim()
            : null,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        type: type,
        providerId: 'uaflix',
      );
    } catch (e) {
      return null;
    }
  }

  static MediaItem? _parseCard(dynamic card) {
    try {
      // UAFlix: link is a.vi-img
      final link = card.find('a', class_: 'vi-img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      // UAFlix: title is in div.vi-title
      final titleEl =
          card.find('div', class_: 'vi-title') ??
          card.find('h3') ??
          card.find('h4');
      var title = titleEl?.text.trim() ?? link.attributes['alt'] ?? '';

      // Often title contains " / English Name", take first part
      if (title.contains(' / ')) {
        title = title.split(' / ').first.trim();
      }

      int? year;
      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(card.text);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }

      // Fallback: search in card text matching 19xx or 20xx
      if (year == null) {
        final yearFallback = RegExp(
          r'\b(19\d{2}|20\d{2})\b',
        ).firstMatch(card.text);
        if (yearFallback != null) {
          year = int.tryParse(yearFallback.group(1) ?? '');
        }
      }

      // Fallback: extract year from URL
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})/?$').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      double? rating;
      String? ratingSource;
      final ratingEl =
          card.find('span', class_: 'rating') ??
          card.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim().replaceAll(',', '.'));
        ratingSource = 'Site';
      }

      // Parse genres
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'vi-genre') ??
          card.find('span', class_: 'genre') ??
          card.find('div', class_: 'genres');
      if (genreEl != null) {
        final genreLinks = genreEl.findAll('a');
        if (genreLinks.isNotEmpty) {
          genres = genreLinks
              .map((a) => a.text.trim())
              .where((g) => g.isNotEmpty)
              .toList();
        } else {
          final genreText = genreEl.text.trim();
          if (genreText.isNotEmpty) {
            genres = genreText
                .split(RegExp(r'[,/]'))
                .map((g) => g.trim())
                .where((g) => g.isNotEmpty)
                .toList();
          }
        }
      }

      // Parse country
      String? country;
      final countryEl =
          card.find('div', class_: 'vi-country') ??
          card.find('span', class_: 'country');
      if (countryEl != null) {
        country = countryEl.text.trim().split(',').first.trim();
      }

      final type = _detectContentType(href);

      return MediaItem(
        id: mediaId,
        providerId: 'uaflix',
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        ratingSource: ratingSource,
        type: type,
        genres: genres,
        country: country,
      );
    } catch (e) {
      return null;
    }
  }

  static MediaDetails parseDetails(String html, String mediaId) {
    final soup = BeautifulSoup(html);

    // Title
    final titleEl = soup.find('h1');
    var title = titleEl?.text.trim() ?? '';

    // Clean Title SEO suffixes
    final seoSuffixes = [
      'дивитись онлайн',
      'смотреть онлайн',
      'подивитися онлайн',
      'онлайн українською',
      'українською мовою',
      'в хорошій якості',
      'безкоштовно',
    ];

    for (final suffix in seoSuffixes) {
      final pattern = RegExp(
        r'\s*[-–—]?\s*' + RegExp.escape(suffix) + r'.*$',
        caseSensitive: false,
      );
      title = title.replaceAll(pattern, '');
    }
    title = title.trim();

    // Poster detection
    String? posterUrl;
    final posterEl =
        soup.find('div', class_: 'fposter2') ??
        soup.find('div', class_: 'fposter3') ??
        soup.find('div', class_: 'fposter') ??
        soup.find('div', class_: 'full-poster') ??
        soup.find('div', class_: 'poster') ??
        soup.find('div', class_: 'fimg');

    if (posterEl != null) {
      final img = posterEl.find('img');
      posterUrl = img?.attributes['data-src'] ?? img?.attributes['src'];
    }

    if (posterUrl == null) {
      // Fallback
      final images = soup.findAll('img');
      for (final img in images) {
        final src = img.attributes['data-src'] ?? img.attributes['src'];
        if (src != null &&
            (src.contains('/uploads/posts/') || src.contains('/posters/'))) {
          posterUrl = src;
          break;
        }
      }
    }

    // Description cleaning
    final descEl =
        soup.find('div', class_: 'fdesc') ??
        soup.find('div', class_: 'full-desc') ??
        soup.find('div', class_: 'description');

    String? description;
    if (descEl != null) {
      // Remove scripts and styles
      final scripts = descEl.findAll('script');
      for (final script in scripts) {
        script.extract();
      }
      final styles = descEl.findAll('style');
      for (final style in styles) {
        style.extract();
      }

      // Remove pagination/rating/bookmarks leaked text
      // Common garbage classes in UAFlix description
      final garbageClasses = [
        'rating',
        'vote-num',
        'unit-rating',
        'ignore-select',
        'full-rat',
        'ppagin',
      ];
      for (final cls in garbageClasses) {
        final garbage = descEl.findAll('*', class_: cls);
        for (final g in garbage) {
          g.extract();
        }
      }

      // Also remove any elements with specific IDs or known garbage tags
      // Sometimes raw numbers appear at the end (pagination)

      description = descEl.text.trim();

      // Post-process regex cleaning for leaked JS or Pagination
      description = description.replaceAll(
        RegExp(r'\(function\(\).*?\}\)\(\)', multiLine: true, dotAll: true),
        '',
      );
      description = description.replaceAll(
        RegExp(r'var\s+[a-zA-Z0-9_]+\s*=.*?;', multiLine: true),
        '',
      );
      // Remove trailing numbers (often pagination 1 2 3...)
      description = description.replaceAll(RegExp(r'\n\s*\d+\s*\n'), '\n');
      description = description.replaceAll(RegExp(r'\s+\d{1,3}\s*$'), '');
    }

    // Info extraction
    int? year;
    List<String>? genres;
    List<String>? countries;
    String? director;
    List<String>? actors;
    Duration? duration;
    double? siteRating;
    double? imdbRating;
    String? originalTitle;

    // Try Schema.org first (accurate and structured)
    final directorMeta = soup.find('meta', attrs: {'itemprop': 'director'});
    if (directorMeta != null) director = directorMeta.attributes['content'];

    final genreMeta = soup.find('meta', attrs: {'itemprop': 'genre'});
    if (genreMeta != null) {
      genres = genreMeta.attributes['content']
          ?.split(',')
          .map((e) => e.trim())
          .toList();
    }

    final dateMeta =
        soup.find('meta', attrs: {'itemprop': 'dateCreated'}) ??
        soup.find('meta', attrs: {'itemprop': 'datePublished'});
    if (dateMeta != null) {
      final dateStr = dateMeta.attributes['content'];
      if (dateStr != null && dateStr.length >= 4) {
        year = int.tryParse(dateStr.substring(0, 4));
      }
    }

    final actorsMeta = soup.find('meta', attrs: {'itemprop': 'actors'});
    if (actorsMeta != null) {
      actors = actorsMeta.attributes['content']
          ?.split(',')
          .map((e) => e.trim())
          .toList();
    }

    final countryMeta =
        soup.find('meta', attrs: {'itemprop': 'contentLocation'}) ??
        soup.find('meta', attrs: {'itemprop': 'countryOfOrigin'});
    if (countryMeta != null) {
      countries = countryMeta.attributes['content']
          ?.split(',')
          .map((e) => e.trim())
          .toList();
    }

    // Original Title
    final originTitleEl = soup.find(
      'meta',
      attrs: {'itemprop': 'alternateName'},
    );
    originalTitle = originTitleEl?.attributes['content']?.trim();

    final infoBlocks =
        soup.findAll('li', class_: 'full-info__item') +
        soup.findAll('div', class_: 'finfo-item');

    for (final block in infoBlocks) {
      final label = block.find('span')?.text.toLowerCase() ?? '';
      final valueLinks = block.findAll('a').map((a) => a.text.trim()).toList();
      final textValue = block.text
          .replaceFirst(block.find('span')?.text ?? '', '')
          .trim();
      RegExpMatch? rMatch;

      if (label.contains('imdb')) {
        rMatch = RegExp(r'([\d.]+)').firstMatch(textValue);
        if (rMatch != null) imdbRating = double.tryParse(rMatch.group(1)!);
      } else if (label.contains('tmdb')) {
        rMatch = RegExp(r'([\d.]+)').firstMatch(textValue);
        // Map TMDB to site rating or similar if needed, or just prioritize IMDb
      } else if (label.contains('рік')) {
        year ??= int.tryParse(textValue.replaceAll(RegExp(r'[^\d]'), ''));
      } else if (label.contains('жанр')) {
        genres ??= valueLinks.isNotEmpty ? valueLinks : [textValue];
      } else if (label.contains('країн')) {
        countries ??= valueLinks.isNotEmpty ? valueLinks : [textValue];
      } else if (label.contains('режис')) {
        director ??= valueLinks.isNotEmpty ? valueLinks.first : textValue;
      } else if (label.contains('актор')) {
        if (actors == null || actors.isEmpty) {
          actors = valueLinks.isNotEmpty
              ? valueLinks
              : textValue.split(',').map((s) => s.trim()).toList();
        }
      } else if (label.contains('трива')) {
        final durMatch = RegExp(r'(\d+)').firstMatch(textValue);
        if (durMatch != null) {
          duration = Duration(minutes: int.parse(durMatch.group(1)!));
        }
      }
    }

    // Generic site rating fallback
    final siteRatingEl =
        soup.find('div', class_: 'rating') ??
        soup.find('span', class_: 'rating');
    if (siteRatingEl != null) {
      final text = siteRatingEl.text.toLowerCase();
      if (!text.contains('imdb')) {
        final rawRating = siteRatingEl.text
            .replaceAll(',', '.')
            .replaceAll(RegExp(r'[^\d.]'), '');
        if (rawRating.isNotEmpty) {
          siteRating = double.tryParse(rawRating);
        }
      }
    }

    // JSON-LD Rating Fallback
    if (imdbRating == null) {
      final jsonLd = soup.find(
        'script',
        attrs: {'type': 'application/ld+json'},
      );
      if (jsonLd != null) {
        final rMatch = RegExp(
          r'"ratingValue":\s*"([\d.]+)"',
        ).firstMatch(jsonLd.text);
        if (rMatch != null) imdbRating = double.tryParse(rMatch.group(1)!);
      }
    }

    // Regex fallbacks for missing metadata (from Python analyzer findings)
    final bodyText = soup.text;

    // Year fallback via regex
    if (year == null) {
      final yearMatch = RegExp(
        r'(?:Рік виходу|Год выпуска|Year)[:\s]+(\d{4})',
        caseSensitive: false,
      ).firstMatch(bodyText);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1)!);
      }
    }

    // Countries fallback via regex
    if (countries == null || countries.isEmpty) {
      final countriesMatch = RegExp(
        r'(?:Країн[аи]|Стран[аы]|Country)[:\s]+([^\n]+)',
        caseSensitive: false,
      ).firstMatch(bodyText);
      if (countriesMatch != null) {
        final countriesText = countriesMatch.group(1)!.trim();
        // Clean up and split
        countries = countriesText
            .split(RegExp(r'[,]'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty && c.length < 50)
            .toList();
      }
    }

    // Director fallback via regex
    if (director == null || director.isEmpty) {
      final directorMatch = RegExp(
        r'(?:Режисер|Режиссёр|Director)[:\s]+([А-ЯЁA-Zа-яёa-z\s\.]+?)(?=\n|Актор|В ролях|$)',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(bodyText);
      if (directorMatch != null) {
        director = directorMatch.group(1)!.trim();
        // Limit length for sanity
        if (director.length > 100) director = null;
      }
    }

    // Actors fallback via regex
    if (actors == null || actors.isEmpty) {
      final actorsMatch = RegExp(
        r'(?:Актор[иы]|Актёр[иы]|В ролях|Actors?)[:\s]+([^\n]+)',
        caseSensitive: false,
      ).firstMatch(bodyText);
      if (actorsMatch != null) {
        final actorsText = actorsMatch.group(1)!.trim();
        actors = actorsText
            .split(RegExp(r'[,]'))
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty && a.length < 50)
            .take(10) // Limit to first 10 actors
            .toList();
      }
    }

    // Type detection fallback
    var type = _detectContentType('/$mediaId');
    if (type == ContentType.unknown) {
      // Guess based on breadcrumbs or category if needed, for now stick to ID check
    }

    final item = MediaItem(
      id: mediaId,
      providerId: 'uaflix',
      title: title,
      originalTitle: originalTitle,
      posterUrl: _absoluteUrl(posterUrl),
      year: year,
      rating: imdbRating ?? siteRating,
      ratingSource: imdbRating != null
          ? 'IMDb'
          : (siteRating != null ? 'Сайт' : null),
      type: type,
    );

    return MediaDetails(
      item: item,
      fullDescription: description,
      genres: genres,
      countries: countries,
      director: director,
      actors: actors,
      duration: duration,
    );
  }

  static List<String> extractIframeSrcs(String html) {
    final soup = BeautifulSoup(html);
    final srcs = <String>[];

    // 1. Standard iframes
    final iframes = soup.findAll('iframe');
    for (final iframe in iframes) {
      var src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
      if (src != null && src.isNotEmpty) {
        // Fix relative protocol
        if (src.startsWith('//')) src = 'https:$src';
        srcs.add(_absoluteUrl(src)!);
      }
    }

    // 2. Scripts with Ashdi/PlayerJS
    final scripts = soup.findAll('script');
    for (final script in scripts) {
      final text = script.text;

      // Ashdi
      if (text.contains('ashdi')) {
        final match = RegExp(
          r'src=["\x27](https?://[^"\x27]*ashdi[^"\x27]*)["\x27]',
        ).firstMatch(text);
        if (match != null) {
          srcs.add(match.group(1)!);
        }
      }

      // Generic window.location or player logic?
      // Sometimes player is inserted via JS
    }

    return srcs;
  }

  static List<String> extractVideoSrcs(String html) {
    final soup = BeautifulSoup(html);
    final srcs = <String>[];
    final videoEls = soup.findAll('video');
    for (final video in videoEls) {
      final src =
          video.attributes['src'] ?? video.find('source')?.attributes['src'];
      if (src != null && src.isNotEmpty) {
        srcs.add(_absoluteUrl(src)!);
      }
    }
    return srcs;
  }

  static String extractIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.isNotEmpty) {
      var path = uri.path;
      // Remove .html extension if present
      if (path.endsWith('.html')) {
        path = path.substring(0, path.length - 5);
      }
      // Remove trailing slash
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      return path;
    }
    return '';
  }

  static ContentType _detectContentType(String url) {
    if (url.contains('/film/') || url.contains('/films/')) {
      return ContentType.movie;
    }
    if (url.contains('/serial/') || url.contains('/serials/')) {
      return ContentType.series;
    }
    if (url.contains('/cartoon/') || url.contains('/cartoons/')) {
      return ContentType.cartoon;
    }
    if (url.contains('/anime/')) {
      return ContentType.anime;
    }
    if (url.contains('/dorama/')) {
      return ContentType.dorama;
    }
    return ContentType.unknown;
  }

  static String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }
}
