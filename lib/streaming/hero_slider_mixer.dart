/// Builds a balanced Home hero feed without letting one catalogue crowd out
/// every other type. Trending Movies and Web Series receive the strongest
/// weighting, with Web Series appearing slightly more often.
class HeroSliderMixer {
  HeroSliderMixer._();

  static const List<int> _schedule = <int>[
    0, 0, 1, 1, 0, 1, 1, 2, 3, 4,
  ];

  static List<T> mix<T>({
    required List<T> movies,
    required List<T> webSeries,
    required List<T> dramas,
    required List<T> anime,
    required List<T> tvShows,
    required String Function(T item) keyOf,
    int limit = 18,
  }) {
    if (limit <= 0) return <T>[];

    final sources = <List<T>>[movies, webSeries, dramas, anime, tvShows];
    final cursors = List<int>.filled(sources.length, 0);
    final seen = <String>{};
    final result = <T>[];

    bool addNext(int sourceIndex) {
      final source = sources[sourceIndex];
      while (cursors[sourceIndex] < source.length) {
        final item = source[cursors[sourceIndex]++];
        final key = keyOf(item).trim();
        if (key.isEmpty || !seen.add(key)) continue;
        result.add(item);
        return true;
      }
      return false;
    }

    while (result.length < limit) {
      var addedAny = false;
      for (final sourceIndex in _schedule) {
        if (result.length >= limit) break;
        addedAny = addNext(sourceIndex) || addedAny;
      }
      if (!addedAny) break;
    }

    return List<T>.unmodifiable(result);
  }
}
