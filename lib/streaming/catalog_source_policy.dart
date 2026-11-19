/// Shared source-priority and Admin-visibility rules for the FLIXORA catalogue.
class CatalogSourcePolicy {
  CatalogSourcePolicy._();

  /// MovieBox is canonical. A published Admin row is used only when no
  /// matching MovieBox title exists.
  static T? preferMovieBox<T>({
    required T? movieBoxMatch,
    required T? publishedAdminFallback,
  }) {
    return movieBoxMatch ?? publishedAdminFallback;
  }

  /// Remove duplicate Admin/TMDB cards when the same title is present in
  /// MovieBox, while preserving the order of every unrelated catalogue item.
  static List<T> preferMovieBoxDuplicates<T>(
    Iterable<T> items, {
    required bool Function(T item) isMovieBox,
    required bool Function(T movieBoxItem, T candidate) matches,
  }) {
    final values = items.toList(growable: false);
    final movieBoxItems = values.where(isMovieBox).toList(growable: false);
    return values.where((item) {
      if (isMovieBox(item)) return true;
      return !movieBoxItems.any((movieBoxItem) => matches(movieBoxItem, item));
    }).toList(growable: false);
  }

  /// Remove MovieBox duplicates using precomputed keys in linear time.
  ///
  /// [movieBoxKeys] emits keys indexed from canonical MovieBox records;
  /// [candidateKeys] emits keys a non-MovieBox record can match against.
  static List<T> preferMovieBoxDuplicatesByKey<T>(
    Iterable<T> items, {
    required bool Function(T item) isMovieBox,
    required Iterable<String> Function(T movieBoxItem) movieBoxKeys,
    required Iterable<String> Function(T candidate) candidateKeys,
  }) {
    final values = items.toList(growable: false);
    final indexedKeys = <String>{};
    for (final item in values) {
      if (isMovieBox(item)) indexedKeys.addAll(movieBoxKeys(item));
    }

    return values.where((item) {
      if (isMovieBox(item)) return true;
      return !candidateKeys(item).any(indexedKeys.contains);
    }).toList(growable: false);
  }

  /// Admin publication status must never be applied to MovieBox or TMDB rows.
  static List<T> adminCandidates<T>(
    Iterable<T> items, {
    required bool Function(T item) isAdmin,
  }) {
    return items.where(isAdmin).toList(growable: false);
  }

  /// Scope publication state to one Admin database row, not a shared TMDB ID
  /// or title/year key that could also identify a MovieBox catalogue item.
  static String? adminVisibilityKey({
    required bool isAdmin,
    required int sourceId,
  }) {
    if (!isAdmin || sourceId <= 0) return null;
    return 'admin:id:$sourceId';
  }

  /// A visibility response may only affect exact Admin row keys that were
  /// requested. Legacy TMDB/title-year keys from an older function are ignored.
  static Set<String> filterBlockedAdminKeys({
    required Iterable<String> requestedKeys,
    required Iterable<String> blockedKeys,
  }) {
    final validRequested = requestedKeys.where((key) {
      if (!key.startsWith('admin:id:')) return false;
      final id = int.tryParse(key.substring('admin:id:'.length));
      return id != null && id > 0;
    }).toSet();
    return blockedKeys
        .map((key) => key.trim())
        .where(validRequested.contains)
        .toSet();
  }

  static bool isAdminBlocked({
    required bool isAdmin,
    required String? visibilityKey,
    required Set<String> blockedKeys,
  }) {
    return isAdmin &&
        visibilityKey != null &&
        visibilityKey.isNotEmpty &&
        blockedKeys.contains(visibilityKey);
  }
}
