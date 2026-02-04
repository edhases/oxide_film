import 'package:beautiful_soup_dart/beautiful_soup.dart';
import '../../domain/entities/entities.dart';

class EneyidaParser {
  static const String baseUrl = 'https://eneyida.tv';

  static List<MediaItem> parseCatalog(String html) {
    final soup = BeautifulSoup(html);
    final items = <MediaItem>[];

    // Main content cards
    final cards = soup.findAll('article', class_: 'short');
    if (cards.isEmpty) {
      // Try alternative
      final altCards = soup.findAll('div', class_: 'short-item');
      for (final card in altCards) {
        final item = _parseCard(card);
        if (item != null) items.add(item);
      }
    }

    for (final card in cards) {
      final item = _parseCard(card);
      if (item != null) items.add(item);
    }

    return items;
  }

  static MediaItem? _parseCard(dynamic card) {
    try {
      final link = card.find('a', class_: 'short_img') ?? card.find('a');
      if (link == null) return null;

      final href = link.attributes['href'] ?? '';
      final mediaId = _extractIdFromUrl(href);
      if (mediaId.isEmpty) return null;

      final img = card.find('img');
      final posterUrl = img?.attributes['src'] ?? img?.attributes['data-src'];

      final titleEl =
          card.find('a', class_: 'short_title') ??
          card.find('div', class_: 'short_title');
      final title = titleEl?.text.trim() ?? link.attributes['title'] ?? '';

      int? year;
      final infoEl = card.find('div', class_: 'short_info');
      if (infoEl != null) {
        final yearMatch = RegExp(r'(\d{4})').firstMatch(infoEl.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      // Fallback: search in card text
      if (year == null) {
        final yearMatch = RegExp(
          r'\b(19\d{2}|20\d{2})\b',
        ).firstMatch(card.text);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1) ?? '');
        }
      }

      double? rating;
      final ratingEl = card.find('span', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
      }

      // Parse genres from card
      List<String>? genres;
      final genreEl =
          card.find('div', class_: 'short_genre') ??
          card.find('span', class_: 'genre');
      if (genreEl != null) {
        final genreLinks = genreEl.findAll('a');
        if (genreLinks.isNotEmpty) {
          genres = genreLinks
              .map((a) => a.text.trim())
              .where((g) => g.isNotEmpty)
              .toList();
        } else {
          // Try parsing comma-separated text
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

      // Parse country if available
      String? country;
      final countryEl =
          card.find('span', class_: 'country') ??
          card.find('div', class_: 'short_country');
      if (countryEl != null) {
        country = countryEl.text.trim();
      }

      final type = _detectContentType(href);

      return MediaItem(
        id: mediaId,
        providerId: 'eneyida',
        title: title,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
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
    var titleEl = soup.find('h1', class_: 'full_title');
    // Fallback: any h1
    if (titleEl == null) {
      titleEl = soup.find('h1');
    }

    var title = titleEl?.text.trim() ?? '';

    // Fallback: Meta title
    if (title.isEmpty) {
      final metaTitle = soup.find('meta', attrs: {'property': 'og:title'});
      title = metaTitle?.attributes['content']?.trim() ?? '';
    }

    // Fallback: title tag
    if (title.isEmpty) {
      final headTitle = soup.find('title');
      title =
          headTitle?.text
              .replaceAll('дивитися онлайн', '')
              .replaceAll('Eneyida.tv', '')
              .trim() ??
          '';
    }

    String? originalTitle;
    final origEl = soup.find('div', class_: 'full_orig-title');
    if (origEl != null) {
      originalTitle = origEl.text.trim();
    }

    // Fast robust poster finder
    String? posterUrl;
    final images = soup.findAll('img');
    for (final img in images) {
      final src = img.attributes['src'];
      final dataSrc = img.attributes['data-src'];
      final dataOrig = img.attributes['data-original'];

      if (src != null && src.contains('/uploads/posts/')) {
        posterUrl = src;
        break;
      }
      if (dataSrc != null && dataSrc.contains('/uploads/posts/')) {
        posterUrl = dataSrc;
        break;
      }
      if (dataOrig != null && dataOrig.contains('/uploads/posts/')) {
        posterUrl = dataOrig;
        break;
      }
    }

    // Fallback
    if (posterUrl == null) {
      final posterEl = soup.find('div', class_: 'full_poster');
      final posterImg = posterEl?.find('img');
      posterUrl =
          posterImg?.attributes['src'] ?? posterImg?.attributes['data-src'];
      posterUrl ??= posterImg?.attributes['data-original'];
    }

    // Info
    final infoBlock = soup.find('div', class_: 'full_info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    Duration? duration;

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('div', class_: 'full_info-item')) {
        final label =
            row.find('span', class_: 'fi-label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'fi-value');

        if (label.contains('режис')) {
          director = value?.text.trim();
        } else if (label.contains('актор')) {
          actors = value?.findAll('a').map((a) => a.text.trim()).toList();
          if (actors?.isEmpty ?? true) {
            actors = value?.text.split(',').map((s) => s.trim()).toList();
          }
        } else if (label.contains('жанр')) {
          genres = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('країн')) {
          countries = value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('рік')) {
          year = int.tryParse(value?.text.trim() ?? '');
        } else if (label.contains('трива')) {
          final durMatch = RegExp(r'(\d+)').firstMatch(value?.text ?? '');
          if (durMatch != null) {
            duration = Duration(minutes: int.parse(durMatch.group(1)!));
          }
        }
      }
    }

    // Fallback year
    if (year == null) {
      final yearMatch = RegExp(r'Рік:\s*(\d{4})').firstMatch(soup.text);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1) ?? '');
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'full_text');
    var description = descEl?.text.trim();

    if (description == null || description.isEmpty) {
      final metaDesc = soup.find('meta', attrs: {'property': 'og:description'});
      description = metaDesc?.attributes['content']?.trim();
    }

    if (description == null || description.isEmpty) {
      final metaDesc = soup.find('meta', attrs: {'name': 'description'});
      description = metaDesc?.attributes['content']?.trim();
    }

    // Rating
    double? rating;
    final ratingEl = soup.find('span', class_: 'full_rating');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        rating = double.tryParse(ratingMatch.group(1) ?? '');
      }
    }

    // Seasons
    List<Season>? seasons;
    final playlistBlock = soup.find('div', class_: 'playlists-ajax');
    if (playlistBlock != null) {
      seasons = _parseSeasons(soup);
    }

    final type = _detectContentTypeFromHtml(soup, mediaId);

    return MediaDetails(
      item: MediaItem(
        id: mediaId,
        providerId: 'eneyida',
        title: title,
        originalTitle: originalTitle,
        posterUrl: _absoluteUrl(posterUrl),
        year: year,
        rating: rating,
        type: type,
      ),
      fullDescription: description,
      genres: genres,
      countries: countries,
      director: director,
      actors: actors,
      duration: duration,
      seasons: seasons,
    );
  }

  static String? extractNewsId(String html, String id) {
    final soup = BeautifulSoup(html);
    // Try hidden input
    final input =
        soup.find('input', attrs: {'name': 'news_id'}) ??
        soup.find('input', attrs: {'name': 'post_id'});
    if (input != null) {
      final value = input.attributes['value'];
      if (value != null && value.isNotEmpty) return value;
    }

    // Try from article id
    final article = soup.find('article', attrs: {'id': true});
    if (article != null) {
      final artId = article.attributes['id'];
      final match = RegExp(r'(\d+)').firstMatch(artId ?? '');
      if (match != null) return match.group(1);
    }

    // Try from media ID
    final match = RegExp(r'(\d+)-').firstMatch(id);
    if (match != null) return match.group(1);

    // Try from data-news_id attribute
    final newsIdEl = soup.find('*', attrs: {'data-news_id': true});
    if (newsIdEl != null) {
      return newsIdEl.attributes['data-news_id'];
    }

    return null;
  }

  static List<String> extractIframeSrcs(String html) {
    final soup = BeautifulSoup(html);
    final srcs = <String>[];
    final iframes = soup.findAll('iframe');
    for (final iframe in iframes) {
      final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
      if (src != null && src.isNotEmpty) {
        srcs.add(src);
      }
    }
    return srcs;
  }

  static List<StreamSource> parseAjaxPlaylist(String html) {
    final soup = BeautifulSoup(html);
    final sources = <StreamSource>[];
    final items = soup.findAll('li');

    for (final item in items) {
      var dataFile = item.attributes['data-file'];
      final voiceover = item.attributes['data-voice'] ?? item.text.trim();

      final itemSeason = int.tryParse(item.attributes['data-season'] ?? '');
      final itemEpisode = int.tryParse(item.attributes['data-episode'] ?? '');

      if (dataFile != null && dataFile.isNotEmpty) {
        dataFile = _cleanUrl(dataFile);

        // Check direct
        if (dataFile.contains('.m3u8') || dataFile.contains('.mp4')) {
          sources.add(
            StreamSource(
              url: dataFile,
              quality: _detectQuality(dataFile),
              voiceover: voiceover,
              type: dataFile.contains('.m3u8')
                  ? StreamType.hls
                  : StreamType.direct,
              season: itemSeason,
              episode: itemEpisode,
            ),
          );
        } else {
          // Player link - add as direct for now, repo will resolve
          // We add a marker or just treat as direct?
          // Let's treat as direct but repo needs to know to resolve it if it's not a video file.
          // Actually, StreamSource can hold the player URL.
          sources.add(
            StreamSource(
              url: dataFile,
              quality: StreamQuality.unknown, // Need resolution
              voiceover: voiceover,
              type: StreamType.direct, // Mark as direct, verify logic in repo
              season: itemSeason,
              episode: itemEpisode,
            ),
          );
        }
      }
    }
    return sources;
  }

  // Helpers

  static String _cleanUrl(String url) {
    var clean = url.trim();
    if (clean.startsWith('//')) clean = 'https:$clean';
    if (clean.contains('eneyida.tv/eneyida.tv/'))
      clean = clean.replaceAll('eneyida.tv/eneyida.tv/', 'eneyida.tv/');

    if (!clean.startsWith('http')) {
      if (clean.startsWith('/')) {
        clean = '$baseUrl$clean';
      } else if (clean.contains('eneyida.tv')) {
        clean = 'https://$clean';
      }
    }
    return clean;
  }

  static String? _absoluteUrl(String? url) {
    if (url == null) return null;
    if (url.startsWith('http')) return url;
    if (url.startsWith('//')) return 'https:$url';
    if (url.startsWith('/')) return '$baseUrl$url';
    return '$baseUrl/$url';
  }

  static String _extractIdFromUrl(String url) {
    if (url.startsWith('/')) {
      return url.substring(1).replaceAll('.html', '');
    }
    final match = RegExp(
      r'/([^/]+(?:/[^/]+)?)/(\d+-[^/]+)\.html',
    ).firstMatch(url);
    if (match != null) {
      return '${match.group(1)}/${match.group(2)}';
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.path.isNotEmpty) {
      var path = uri.path;
      if (path.contains('eneyida.tv/'))
        path = path.replaceAll('eneyida.tv/', '');
      if (path.endsWith('.html')) path = path.substring(0, path.length - 5);
      if (path.startsWith('/')) path = path.substring(1);
      return path;
    }
    return '';
  }

  static ContentType _detectContentType(String url) {
    if (url.contains('/films/') || url.contains('films/'))
      return ContentType.movie;
    if (url.contains('/series/') || url.contains('series/'))
      return ContentType.series;
    if (url.contains('/cartoon/') || url.contains('cartoon/'))
      return ContentType.cartoon;
    if (url.contains('/anime/') || url.contains('anime/'))
      return ContentType.anime;
    return ContentType.unknown;
  }

  static ContentType _detectContentTypeFromHtml(
    BeautifulSoup soup,
    String mediaId,
  ) {
    final urlType = _detectContentType(mediaId);
    if (urlType != ContentType.unknown) return urlType;

    // Breadcrumbs
    final breadcrumbs =
        soup.find('ul', class_: 'bread-crumbs') ??
        soup.find('div', class_: 'breadcrumb');
    if (breadcrumbs != null) {
      final links = breadcrumbs.findAll('a');
      for (final link in links) {
        final href = link.attributes['href'] ?? '';
        final text = link.text.toLowerCase();
        if (href.contains('/films/') || text.contains('фільм'))
          return ContentType.movie;
        if (href.contains('/series/') || text.contains('серіал'))
          return ContentType.series;
        if (href.contains('/cartoon/') || text.contains('мультфільм'))
          return ContentType.cartoon;
        if (href.contains('/anime/') || text.contains('аніме'))
          return ContentType.anime;
      }
    }

    // Seasons check
    final hasSeasons = soup.find('div', class_: 'playlists-ajax') != null;
    if (hasSeasons) return ContentType.series;

    return ContentType.unknown;
  }

  static List<Season> _parseSeasons(BeautifulSoup soup) {
    final seasons = <Season>[];
    final seasonTabs = soup.findAll('li', class_: 'season-tab');

    for (final tab in seasonTabs) {
      final seasonNum =
          int.tryParse(tab.attributes['data-season'] ?? '') ??
          seasons.length + 1;
      final episodes = <Episode>[];
      final episodeItems = soup.findAll(
        'li',
        attrs: {'data-season': seasonNum.toString()},
      );

      for (final epItem in episodeItems) {
        if (epItem.attributes['data-episode'] != null) {
          final epNum =
              int.tryParse(epItem.attributes['data-episode'] ?? '') ??
              episodes.length + 1;
          final epTitle = epItem.text.trim();
          episodes.add(Episode(number: epNum, title: epTitle));
        }
      }

      if (episodes.isNotEmpty) {
        seasons.add(Season(number: seasonNum, episodes: episodes));
      }
    }
    return seasons;
  }

  static StreamQuality _detectQuality(String url) {
    if (url.contains('1080')) return StreamQuality.q1080p;
    if (url.contains('720')) return StreamQuality.q720p;
    if (url.contains('480')) return StreamQuality.q480p;
    if (url.contains('360')) return StreamQuality.q360p;
    return StreamQuality.unknown;
  }

  static String categoryToSlug(String category) {
    final map = {
      'Бойовик': 'boyovik',
      'Детектив': 'detektyv',
      'Драма': 'drama',
      'Комедія': 'komediya',
      'Мелодрама': 'melodrama',
      'Пригоди': 'pryhody',
      'Трилер': 'tryler',
      'Фантастика': 'fantastyka',
      'Фентезі': 'fentezi',
      'Жахи': 'zhakhy',
      'Історичний': 'istorychnyy',
    };
    return map[category] ?? category.toLowerCase();
  }
}
