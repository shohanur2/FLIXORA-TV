/// Small, deterministic rules used by the Home Trending Movies feed.
class TrendingMovieEligibility {
  TrendingMovieEligibility._();

  /// MovieBox stream labels are also used by the player language selector.
  /// Accept explicit Hindi names/codes only; subtitles do not count as audio.
  static bool hasHindiAudioVariant(Iterable<String> labels) {
    return labels.any((raw) {
      final value = raw
          .split('·')
          .first
          .trim()
          .toLowerCase();
      if (value.contains('subtitle') || value.contains('caption')) {
        return false;
      }
      return value == 'hi' ||
          value.contains('hindi') ||
          value == 'हिन्दी' ||
          value == 'हिंदी';
    });
  }

  /// Restrict this rail to recent releases, using a rolling two-year window.
  static bool isRecentRelease({
    required String releaseDate,
    required String year,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final cutoff = reference.subtract(const Duration(days: 730));
    final parsedDate = DateTime.tryParse(releaseDate.trim());
    if (parsedDate != null) {
      return !parsedDate.isAfter(reference) && !parsedDate.isBefore(cutoff);
    }

    final parsedYear = int.tryParse(year.trim());
    return parsedYear != null &&
        parsedYear >= cutoff.year &&
        parsedYear <= reference.year;
  }

  /// Use TMDB regional catalogue membership first, then reliable language
  /// and country metadata. Do not guess a category from a title's wording.
  static String category({
    required String originalLanguage,
    required String originCountry,
    required bool inBollywoodCatalogue,
    required bool inHollywoodCatalogue,
    bool inSouthIndianCatalogue = false,
    bool inBengaliCatalogue = false,
  }) {
    final language = originalLanguage.trim().toLowerCase();
    final country = originCountry.trim().toLowerCase();

    final isIndia = country == 'in' ||
        country == 'india' ||
        country.contains('india');
    final isBangladesh = country == 'bd' ||
        country == 'bangladesh' ||
        country.contains('bangladesh');
    final isHollywoodCountry = country == 'us' ||
        country == 'usa' ||
        country == 'united states' ||
        country == 'uk' ||
        country == 'gb' ||
        country == 'united kingdom' ||
        country == 'canada' ||
        country == 'australia';

    if (inSouthIndianCatalogue ||
        (isIndia && const {'ta', 'te', 'ml', 'kn'}.contains(language))) {
      return 'South Indian';
    }
    if (inBengaliCatalogue || language == 'bn' || isBangladesh) {
      return 'Bengali';
    }
    if (inBollywoodCatalogue ||
        (language == 'hi' && (country.isEmpty || isIndia))) {
      return 'Bollywood';
    }
    if (inHollywoodCatalogue ||
        (language == 'en' && isHollywoodCountry)) {
      return 'Hollywood';
    }
    if (language == 'ko' || country == 'kr' || country.contains('korea')) {
      return 'Korean';
    }
    if (const {'zh', 'ja', 'th', 'vi', 'id', 'tl'}.contains(language)) {
      return 'Asian';
    }
    return 'International';
  }
}
