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
      String? ratingSource;
      final ratingEl = card.find('span', class_: 'rating');
      if (ratingEl != null) {
        rating = double.tryParse(ratingEl.text.trim());
        ratingSource = 'Site';
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
    var titleEl = soup.find('h1', class_: 'full_title');
    // Fallback: any h1
    titleEl ??= soup.find('h1');

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
      final src =
          img.attributes['src'] ??
          img.attributes['data-src'] ??
          img.attributes['data-original'];
      if (src != null &&
          (src.contains('/uploads/posts/') || src.contains('/posters/'))) {
        posterUrl = src;
        break;
      }
    }

    // Info
    final infoBlock = soup.find('div', class_: 'full_info');
    String? director;
    List<String>? actors;
    List<String>? genres;
    List<String>? countries;
    int? year;
    Duration? duration;
    double? siteRating;
    double? imdbRating;

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

    final dateMeta = soup.find('meta', attrs: {'itemprop': 'dateCreated'});
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

    // Original Title from Schema.org or page
    final originTitleEl =
        soup.find('div', class_: 'full_orig-title') ??
        soup.find('meta', attrs: {'itemprop': 'alternateName'});
    originalTitle =
        originTitleEl?.text.trim() ??
        originTitleEl?.attributes['content']?.trim();
    if (originalTitle != null) {
      originalTitle = originalTitle
          .replaceFirst(RegExp(r'\d+\s+season.*$', caseSensitive: false), '')
          .trim();
    }

    if (infoBlock != null) {
      for (final row in infoBlock.findAll('div', class_: 'full_info-item')) {
        final label =
            row.find('span', class_: 'fi-label')?.text.toLowerCase() ?? '';
        final value = row.find('span', class_: 'fi-value');

        if (label.contains('режис')) {
          director ??= value?.text.trim();
        } else if (label.contains('актор')) {
          if (actors == null || actors.isEmpty) {
            actors = value?.findAll('a').map((a) => a.text.trim()).toList();
            if (actors?.isEmpty ?? true) {
              actors = value?.text.split(',').map((s) => s.trim()).toList();
            }
          }
        } else if (label.contains('жанр')) {
          genres ??= value?.findAll('a').map((a) => a.text.trim()).toList();
        } else if (label.contains('країн')) {
          countries ??= value?.findAll('a').map((a) => a.text.trim()).toList();
          if (countries == null || countries.isEmpty) {
            final text = value?.text.trim();
            if (text != null && text.isNotEmpty) {
              countries = text.split(',').map((s) => s.trim()).toList();
            }
          }
        } else if (label.contains('рік')) {
          year ??= int.tryParse(value?.text.trim() ?? '');
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
      if (yearMatch != null) year = int.tryParse(yearMatch.group(1) ?? '');
    }

    // Improve genres parsing - split by •separator (from Python analyzer findings)
    if (genres != null && genres.isNotEmpty) {
      final improvedGenres = <String>[];
      for (final genre in genres) {
        // Split by bullet points or other separators
        final parts = genre
            .split(RegExp(r'[•]'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty);
        improvedGenres.addAll(parts);
      }
      if (improvedGenres.isNotEmpty) {
        genres = improvedGenres;
      }
    }

    // Regex fallbacks for missing metadata (from Python analyzer findings)
    final bodyText = soup.text;

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
            .take(10)
            .toList();
      }
    }

    // Description
    final descEl = soup.find('div', class_: 'full_text');
    var description = descEl?.text.trim();
    if (description == null || description.isEmpty) {
      final metaDesc =
          soup.find('meta', attrs: {'property': 'og:description'}) ??
          soup.find('meta', attrs: {'name': 'description'});
      description = metaDesc?.attributes['content']?.trim();
    }

    // Rating
    final ratingEl = soup.find('span', class_: 'full_rating');
    if (ratingEl != null) {
      final ratingMatch = RegExp(r'([\d.]+)').firstMatch(ratingEl.text);
      if (ratingMatch != null) {
        final val = double.tryParse(ratingMatch.group(1) ?? '');
        if (ratingEl.text.toLowerCase().contains('imdb')) {
          imdbRating = val;
        } else {
          siteRating = val;
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
        final ratingMatch = RegExp(
          r'"ratingValue":\s*"([\d.]+)"',
        ).firstMatch(jsonLd.text);
        if (ratingMatch != null) {
          imdbRating = double.tryParse(ratingMatch.group(1)!);
        }
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
        rating: imdbRating ?? siteRating,
        ratingSource: imdbRating != null
            ? 'IMDb'
            : (siteRating != null ? 'Сайт' : null),
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

        // Check if dataFile contains multiple qualities in format: [480p]url1,[720p]url2
        if (dataFile.contains('[') && dataFile.contains(']')) {
          final qualityPattern = RegExp(r'\[(\d+p?)\]([^,\[]+)');
          final matches = qualityPattern.allMatches(dataFile);

          if (matches.isNotEmpty) {
            for (final match in matches) {
              final qLabel = match.group(1);
              final qUrl = match.group(2)?.trim();
              if (qUrl != null && qUrl.isNotEmpty) {
                sources.add(
                  StreamSource(
                    url: qUrl,
                    quality: _detectQuality(qLabel ?? qUrl),
                    voiceover: voiceover,
                    type: qUrl.contains('.m3u8')
                        ? StreamType.hls
                        : StreamType.direct,
                    season: itemSeason,
                    episode: itemEpisode,
                  ),
                );
              }
            }
            continue; // Move to next item
          }
        }

        // Direct fallback
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
          sources.add(
            StreamSource(
              url: dataFile,
              quality: StreamQuality.unknown,
              voiceover: voiceover,
              type: StreamType.direct,
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
    if (clean.contains('eneyida.tv/eneyida.tv/')) {
      clean = clean.replaceAll('eneyida.tv/eneyida.tv/', 'eneyida.tv/');
    }

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
      if (path.contains('eneyida.tv/')) {
        path = path.replaceAll('eneyida.tv/', '');
      }
      if (path.endsWith('.html')) path = path.substring(0, path.length - 5);
      if (path.startsWith('/')) path = path.substring(1);
      return path;
    }
    return '';
  }

  static ContentType _detectContentType(String url) {
    final urlLower = url.toLowerCase();

    // Check URL patterns
    if (urlLower.contains('/films/') ||
        urlLower.contains('films/') ||
        urlLower.contains('/filmy/') ||
        urlLower.contains('film')) {
      return ContentType.movie;
    }
    if (urlLower.contains('/series/') ||
        urlLower.contains('series/') ||
        urlLower.contains('/serialy/') ||
        urlLower.contains('serial')) {
      return ContentType.series;
    }
    if (urlLower.contains('/cartoon/') ||
        urlLower.contains('cartoon/') ||
        urlLower.contains('/multfilmy/') ||
        urlLower.contains('multfilm')) {
      return ContentType.cartoon;
    }
    if (urlLower.contains('/anime/') || urlLower.contains('anime/')) {
      return ContentType.anime;
    }

    // Default to movie for Eneyida as most content is movies
    return ContentType.movie;
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
        if (href.contains('/films/') || text.contains('фільм')) {
          return ContentType.movie;
        }
        if (href.contains('/series/') || text.contains('серіал')) {
          return ContentType.series;
        }
        if (href.contains('/cartoon/') || text.contains('мультфільм')) {
          return ContentType.cartoon;
        }
        if (href.contains('/anime/') || text.contains('аніме')) {
          return ContentType.anime;
        }
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
