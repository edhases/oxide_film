import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../domain/entities/entities.dart';

class UaserialsParser {
  static const String baseUrl = 'https://uaserials.my';

  static List<MediaItem> parseList(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // UaSerials uses div.short-item for cards
    final cardDivs = soup.findAll('div', class_: 'short-item');

    if (cardDivs.isNotEmpty) {
      for (final cardDiv in cardDivs) {
        final item = _parseCardDiv(cardDiv);
        if (item != null) items.add(item);
      }
    } else {
      // Fallback: try a.short-img directly
      final links = soup.findAll('a', class_: 'short-img');
      for (final link in links) {
        final item = _parseCard(link);
        if (item != null) items.add(item);
      }
    }

    return items;
  }

  static MediaItem? _parseCardDiv(Bs4Element cardDiv) {
    try {
      final link = cardDiv.find('a', class_: 'short-img');
      if (link == null) return null;

      final href = link.attributes['href'];
      if (href == null) return null;

      final id = extractId(href);
      if (id.isEmpty) return null;

      // Get poster from img - check data-src first for lazy loading
      final img = link.find('img');
      final rawPosterUrl =
          img?.attributes['data-src'] ?? img?.attributes['src'];
      // Convert relative URL to absolute
      final posterUrl = _absoluteUrl(rawPosterUrl);

      // Get title from div.th-title
      final titleEl = cardDiv.find('div', class_: 'th-title');
      final title =
          titleEl?.text.trim() ?? img?.attributes['alt']?.trim() ?? '';

      if (title.isEmpty) return null;

      // Get original title from div.th-title-oname
      final oTitleEl = cardDiv.find('div', class_: 'th-title-oname');
      final originalTitle = oTitleEl?.text.trim();

      int? year;
      double? rating;
      String? ratingSource;
      final ratingEl =
          cardDiv.find('span', class_: 'rating') ??
          cardDiv.find('div', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(
          ratingEl.text
              .trim()
              .replaceAll(',', '.')
              .replaceAll(RegExp(r'[^\d.]'), ''),
        );
        ratingSource =
            ratingEl.attributes['class']?.contains('imdb') == true ||
                ratingEl.text.toLowerCase().contains('imdb')
            ? 'IMDb'
            : 'Site';
      }

      // Determine type from URL
      ContentType type = ContentType.series; // Default
      if (href.contains('/films/') ||
          href.contains('/filmss/') ||
          href.contains('/fcartoon/')) {
        type = ContentType.movie;
      }
      if (href.contains('/cartoons/')) type = ContentType.cartoon;
      if (href.contains('/anime/')) type = ContentType.anime;

      return MediaItem(
        id: id,
        title: title,
        originalTitle: originalTitle,
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        ratingSource: ratingSource,
        type: type,
        providerId: 'uaserials',
      );
    } catch (e) {
      return null;
    }
  }

  static MediaItem? _parseCard(Bs4Element link) {
    try {
      final href = link.attributes['href'];
      if (href == null) return null;

      final id = extractId(href);
      if (id.isEmpty) return null;

      // Robust poster finder
      String? posterUrl;
      final images = link.findAll('img');
      for (final img in images) {
        final src = img.attributes['src'];
        final dataSrc = img.attributes['data-src'];

        if (src != null &&
            (src.contains('/posters/') || src.contains('/uploads/'))) {
          posterUrl = src;
          break;
        }
        if (dataSrc != null &&
            (dataSrc.contains('/posters/') || dataSrc.contains('/uploads/'))) {
          posterUrl = dataSrc;
          break;
        }
      }
      // Fallback to first image
      if (posterUrl == null && images.isNotEmpty) {
        posterUrl =
            images.first.attributes['src'] ??
            images.first.attributes['data-src'];
      }

      final title = images.isNotEmpty
          ? (images.first.attributes['alt']?.trim() ??
                link.attributes['title']?.trim() ??
                '')
          : link.text.trim();

      // Try to extract year from title or nearby elements
      int? year;
      final parent = link.parent;
      if (parent != null) {
        // Look for year in parent container
        final yearEl =
            parent.find('span', class_: 'year') ??
            parent.find('div', class_: 'year') ??
            parent.find('span', class_: 'serial-year');
        if (yearEl != null) {
          year = int.tryParse(
            yearEl.text.trim().replaceAll(RegExp(r'[^\d]'), ''),
          );
        }
        // Try to find year in text like (2024) or 2024
        if (year == null) {
          final yearMatch = RegExp(
            r'\b(19\d{2}|20\d{2})\b',
          ).firstMatch(parent.text);
          if (yearMatch != null) {
            year = int.tryParse(yearMatch.group(1) ?? '');
          }
        }
      }

      // Fallback: extract year from URL (common in UaSerials)
      if (year == null) {
        final urlYearMatch = RegExp(r'-(\d{4})\.html').firstMatch(href);
        if (urlYearMatch != null) {
          year = int.tryParse(urlYearMatch.group(1) ?? '');
        }
      }

      // Try to extract rating
      double? rating;
      String? ratingSource;
      if (parent != null) {
        final ratingEl =
            parent.find('span', class_: 'rating') ??
            parent.find('div', class_: 'rating') ??
            parent.find('span', class_: 'imdb') ??
            parent.find('span', class_: 'serial-rating');
        if (ratingEl != null) {
          rating = double.tryParse(
            ratingEl.text
                .trim()
                .replaceAll(',', '.')
                .replaceAll(RegExp(r'[^\d.]'), ''),
          );
          ratingSource =
              ratingEl.attributes['class']?.contains('imdb') == true ||
                  ratingEl.text.toLowerCase().contains('imdb') ||
                  ratingEl.find('span', class_: 'imdb') != null
              ? 'IMDb'
              : 'Site';
        }
      }

      // Determine type
      ContentType type = ContentType.series; // Default
      if (href.contains('/films/') ||
          href.contains('/filmss/') ||
          href.contains('movies')) {
        type = ContentType.movie;
      }
      if (href.contains('cartoons')) type = ContentType.cartoon;

      // Try to extract genres
      List<String>? genres;
      if (parent != null) {
        final genreEl =
            parent.find('div', class_: 'serial-genre') ??
            parent.find('span', class_: 'genre') ??
            parent.find('div', class_: 'genres');
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
      }

      // Try to extract country
      String? country;
      if (parent != null) {
        final countryEl =
            parent.find('div', class_: 'serial-country') ??
            parent.find('span', class_: 'country');
        if (countryEl != null) {
          country = countryEl.text.trim().split(',').first.trim();
        }
      }

      return MediaItem(
        id: id,
        providerId: 'uaserials',
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

  static MediaDetails parseDetails(String html, String id) {
    final soup = BeautifulSoup(html);

    final titleEl = soup.find('h1');
    final title = titleEl?.text.trim() ?? '';

    String? description;
    // UaSerials uses 'ftext full-text' or 'full-text' class for description
    final descEl =
        soup.find('div', class_: 'full-text') ??
        soup.find('div', class_: 'ftext') ??
        soup.find('div', class_: 'full-desc') ??
        soup.find('div', class_: 'fdesc');
    description = descEl?.text.trim();

    // Poster extraction
    // Using robust finding: /posters/ or /uploads/
    String? posterUrl;
    final images = soup.findAll('img');
    for (final img in images) {
      final src = img.attributes['src'];
      final dataSrc = img.attributes['data-src'];

      if (src != null &&
          (src.contains('/posters/') || src.contains('/uploads/'))) {
        posterUrl = src;
        break;
      }
      if (dataSrc != null &&
          (dataSrc.contains('/posters/') || dataSrc.contains('/uploads/'))) {
        posterUrl = dataSrc;
        break;
      }
    }

    // Fallback: first image in .full-img
    if (posterUrl == null) {
      final posterDiv = soup.find('div', class_: 'full-img');
      posterUrl = posterDiv?.find('img')?.attributes['src'];
    }

    // Info parsing
    int? year;
    List<String>? genres;
    double? rating;
    String? originalTitle;

    final infoList = soup.findAll('ul', class_: 'full-list');
    for (final list in infoList) {
      for (final li in list.findAll('li')) {
        final text = li.text.toLowerCase();
        if (text.contains('рік')) {
          final match = RegExp(r'\d{4}').firstMatch(text);
          if (match != null) year = int.tryParse(match.group(0)!);
        } else if (text.contains('жанр')) {
          final links = li.findAll('a');
          if (links.isNotEmpty) {
            genres = links.map((a) => a.text.trim()).toList();
          } else {
            // remove label "Жанр:"
            genres = li.text
                .replaceAll(RegExp(r'жанр:?', caseSensitive: false), '')
                .split(',')
                .map((s) => s.trim())
                .toList();
          }
        } else if (text.contains('оригінал')) {
          originalTitle = li.text
              .replaceAll(RegExp(r'оригінал.*:?', caseSensitive: false), '')
              .trim();
        }
      }
    }

    String? ratingSource;
    // Rating
    final ratingEl =
        soup.find('div', class_: 'rating') ??
        soup.find('span', class_: 'rating');
    if (ratingEl != null) {
      rating = double.tryParse(
        ratingEl.text.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.]'), ''),
      );
      ratingSource =
          ratingEl.attributes['class']?.contains('imdb') == true ||
              ratingEl.text.toLowerCase().contains('imdb')
          ? 'IMDb'
          : 'Site';
    }

    // Determine type from id or breadcrumbs
    var type = ContentType.series;

    // Breadcrumbs check
    final bc =
        soup.find('ul', class_: 'breadcrumb') ??
        soup.find('div', class_: 'breadcrumb');
    if (bc != null) {
      final bcText = bc.text.toLowerCase();
      if (bcText.contains('фільм')) type = ContentType.movie;
      if (bcText.contains('серіал')) type = ContentType.series;
      if (bcText.contains('мультфільм'))
        type = ContentType.movie; // Single films
      if (bcText.contains('мультсеріал')) type = ContentType.series;
    } else {
      // Fallback to URL-based guess if breadcrumbs missing
      if (id.contains('/films/') || id.contains('/filmss/')) {
        type = ContentType.movie;
      }
    }

    final item = MediaItem(
      id: id,
      providerId: 'uaserials',
      title: title,
      originalTitle: originalTitle,
      posterUrl: _absoluteUrl(posterUrl),
      year: year,
      rating: rating,
      ratingSource: ratingSource,
      type: type,
    );

    return MediaDetails(
      item: item,
      fullDescription: description,
      genres: genres,
    );
  }

  static List<String> extractIframeSrcs(String html) {
    final soup = BeautifulSoup(html);
    final srcs = <String>[];

    // 1. Standard iframes
    final iframes = soup.findAll('iframe');
    for (final iframe in iframes) {
      var src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
      if (src != null) {
        // Skip YouTube/Vimeo trailers
        if (src.contains('youtube.com') ||
            src.contains('youtu.be') ||
            src.contains('vimeo.com')) {
          continue;
        }

        // Fix relative protocol
        if (src.startsWith('//'))
          src = 'https:$src';
        else if (src.startsWith('/'))
          src = '$baseUrl$src';

        srcs.add(src);
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
    }

    return srcs;
  }

  static String extractId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';

    var path = uri.path;
    if (path.endsWith('.html')) {
      path = path.substring(0, path.length - 5);
    }
    if (path.startsWith('/')) path = path.substring(1);

    return path;
  }

  static String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }
}
