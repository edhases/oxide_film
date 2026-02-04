/// Service for transliterating text between Ukrainian and Latin scripts
///
/// Supports bidirectional conversion and automatic script detection.
/// Uses Ukrainian transliteration standard (Passport/ISO 9).
class TransliterationService {
  // Ukrainian to Latin mapping (Passport standard)
  static const Map<String, String> _ukToLat = {
    'а': 'a',
    'б': 'b',
    'в': 'v',
    'г': 'h',
    'ґ': 'g',
    'д': 'd',
    'е': 'e',
    'є': 'ie',
    'ж': 'zh',
    'з': 'z',
    'и': 'y',
    'і': 'i',
    'ї': 'i',
    'й': 'i',
    'к': 'k',
    'л': 'l',
    'м': 'm',
    'н': 'n',
    'о': 'o',
    'п': 'p',
    'р': 'r',
    'с': 's',
    'т': 't',
    'у': 'u',
    'ф': 'f',
    'х': 'kh',
    'ц': 'ts',
    'ч': 'ch',
    'ш': 'sh',
    'щ': 'shch',
    'ь': '',
    'ю': 'iu',
    'я': 'ia',
    // Russian letters that might appear
    'ы': 'y',
    'э': 'e',
    'ё': 'io',
    'ъ': '',
  };

  // Latin to Ukrainian mapping (reverse, simplified)
  // Note: This is lossy - multiple Latin combinations map to same Ukrainian
  static const Map<String, String> _latToUk = {
    'shch': 'щ',
    'sch': 'щ',
    'zh': 'ж',
    'kh': 'х',
    'ts': 'ц',
    'ch': 'ч',
    'sh': 'ш',
    'ia': 'я',
    'ya': 'я',
    'ie': 'є',
    'ye': 'є',
    'iu': 'ю',
    'yu': 'ю',
    'yi': 'ї',
    'io': 'йо',
    'yo': 'йо',
    'a': 'а',
    'b': 'б',
    'c': 'ц',
    'd': 'д',
    'e': 'е',
    'f': 'ф',
    'g': 'ґ',
    'h': 'г',
    'i': 'і',
    'j': 'й',
    'k': 'к',
    'l': 'л',
    'm': 'м',
    'n': 'н',
    'o': 'о',
    'p': 'п',
    'q': 'к',
    'r': 'р',
    's': 'с',
    't': 'т',
    'u': 'у',
    'v': 'в',
    'w': 'в',
    'x': 'кс',
    'y': 'и',
    'z': 'з',
  };

  // Common English movie/TV terms to Ukrainian
  static const Map<String, String> _englishToUkrainian = {
    'vampire': 'вампір',
    'vampires': 'вампіри',
    'diaries': 'щоденники',
    'diary': 'щоденник',
    'originals': 'первородні',
    'game': 'гра',
    'thrones': 'престоли',
    'house': 'дім',
    'dragon': 'дракон',
    'dragons': 'дракони',
    'ring': 'кільце',
    'rings': 'кільця',
    'lord': 'володар',
    'king': 'король',
    'queen': 'королева',
    'war': 'війна',
    'wars': 'війни',
    'star': 'зоря',
    'stars': 'зорі',
    'love': 'кохання',
    'death': 'смерть',
    'life': 'життя',
    'dark': 'темний',
    'light': 'світло',
    'night': 'ніч',
    'day': 'день',
    'stranger': 'незнайомець',
    'things': 'речі',
    'breaking': 'пуститися',
    'bad': 'берега',
    'walking': 'ходячі',
    'dead': 'мерці',
    'prison': 'в\'язниця',
    'break': 'втеча',
    'friends': 'друзі',
    'family': 'сім\'я',
    'money': 'гроші',
    'heist': 'пограбування',
    'squid': 'кальмар',
    'wednesday': 'венздей',
    'bridgerton': 'бріджертон',
    'bridgertons': 'бріджертони',
    'witcher': 'відьмак',
    'mandalorian': 'мандалорець',
    'peaky': 'гострі',
    'blinders': 'козирки',
    'euphoria': 'ейфорія',
    'arcane': 'аркейн',
    'avatar': 'аватар',
    'spider': 'павук',
    'man': 'людина',
    'iron': 'залізна',
    'batman': 'бетмен',
    'superman': 'супермен',
    'avengers': 'месники',
    'guardians': 'вартові',
    'galaxy': 'галактика',
    'fast': 'форсаж',
    'furious': 'скажений',
    'mission': 'місія',
    'impossible': 'неможлива',
    'matrix': 'матриця',
    'inception': 'початок',
    'interstellar': 'інтерстеллар',
    'titanic': 'титанік',
    'frozen': 'крижане',
    'heart': 'серце',
    'lion': 'лев',
    'beauty': 'красуня',
    'beast': 'чудовисько',
  };

  /// Detect if text is primarily Cyrillic (Ukrainian/Russian)
  bool isCyrillic(String text) {
    if (text.isEmpty) return false;

    final cyrillicPattern = RegExp(r'[\u0400-\u04FF]');
    final latinPattern = RegExp(r'[a-zA-Z]');

    final cyrillicCount = cyrillicPattern.allMatches(text.toLowerCase()).length;
    final latinCount = latinPattern.allMatches(text.toLowerCase()).length;

    return cyrillicCount > latinCount;
  }

  /// Detect if text is primarily Latin
  bool isLatin(String text) {
    return !isCyrillic(text) && RegExp(r'[a-zA-Z]').hasMatch(text);
  }

  /// Transliterate Ukrainian text to Latin
  String ukrainianToLatin(String text) {
    final buffer = StringBuffer();
    final lower = text.toLowerCase();

    for (var i = 0; i < lower.length; i++) {
      final char = lower[i];
      buffer.write(_ukToLat[char] ?? char);
    }

    return buffer.toString();
  }

  /// Transliterate Latin text to Ukrainian
  String latinToUkrainian(String text) {
    var result = text.toLowerCase();

    // First, replace multi-character sequences (longest first)
    final sortedKeys = _latToUk.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      result = result.replaceAll(key, _latToUk[key]!);
    }

    return result;
  }

  /// Translate common English words to Ukrainian equivalents
  String translateEnglishTerms(String text) {
    var result = text.toLowerCase();

    // Sort by length (longest first) to avoid partial replacements
    final sortedKeys = _englishToUkrainian.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      // Use word boundaries to avoid partial matches
      final pattern = RegExp(r'\b' + RegExp.escape(key) + r'\b');
      result = result.replaceAll(pattern, _englishToUkrainian[key]!);
    }

    return result;
  }

  /// Generate search variants for a query
  ///
  /// Returns list of possible interpretations of the query:
  /// - Original (normalized)
  /// - Transliterated version
  /// - English terms translated
  List<String> generateSearchVariants(String query) {
    final normalized = query.toLowerCase().trim();
    final variants = <String>{normalized};

    if (isLatin(normalized)) {
      // Latin input - try to convert to Ukrainian
      variants.add(latinToUkrainian(normalized));

      // Also try translating English terms
      final translated = translateEnglishTerms(normalized);
      if (translated != normalized) {
        variants.add(translated);
      }

      // Try both: translate then transliterate remaining
      final mixed = latinToUkrainian(translateEnglishTerms(normalized));
      variants.add(mixed);
    } else if (isCyrillic(normalized)) {
      // Cyrillic input - also try Latin version for some providers
      variants.add(ukrainianToLatin(normalized));
    }

    // Remove empty and duplicate variants
    return variants.where((v) => v.isNotEmpty).toList();
  }

  /// Normalize query for consistent comparison
  ///
  /// - Lowercase
  /// - Trim whitespace
  /// - Collapse multiple spaces
  /// - Remove special characters (keep alphanumeric and spaces)
  String normalizeQuery(String query) {
    return query
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\s\u0400-\u04FF]'), '');
  }

  /// Check if two strings are likely the same after normalization
  bool areSimilarQueries(String a, String b) {
    final normalA = normalizeQuery(a);
    final normalB = normalizeQuery(b);

    if (normalA == normalB) return true;

    // Check if one is transliteration of another
    if (isLatin(a) && isCyrillic(b)) {
      return normalizeQuery(latinToUkrainian(a)) == normalB;
    }
    if (isCyrillic(a) && isLatin(b)) {
      return normalA == normalizeQuery(latinToUkrainian(b));
    }

    return false;
  }
}
