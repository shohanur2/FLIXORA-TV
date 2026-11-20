import '../native/sparkbox_core.dart';
import 'moviebox_stream_policy.dart';

/// Single entry point for FLIXORA's MovieBox/WeFeed content system.
///
/// The native Rust core owns request signing, guest tokens, mobile/H5
/// fallback, parsing, stream resolution and subtitle discovery. Flutter
/// receives normalized JSON maps and remains responsible for UI, playback,
/// caching and downloads.
class MovieBoxService {
  MovieBoxService._();

  static Future<Map<String, dynamic>> version() => SparkBoxCore.version();

  static Future<void> enableSafeContentFilter() =>
      SparkBoxCore.setBlockAdult(true);

  static final Map<String, _MovieBoxCacheEntry<List<Map<String, dynamic>>>>
      _homeCache = {};

  static Future<List<Map<String, dynamic>>> home({bool forceRefresh = false}) {
    if (forceRefresh) _homeCache.remove('home');
    return _remember(
      _homeCache,
      'home',
      const Duration(minutes: 5),
      () => _retry(
        SparkBoxCore.home,
        isUsable: (items) => items.isNotEmpty,
      ),
    );
  }

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _shortsCache = {};

  static Future<Map<String, dynamic>> shorts({
    bool forceRefresh = false,
    int perPage = 24,
    int maxPages = 10,
  }) {
    final key = '$perPage:$maxPages';
    if (forceRefresh) _shortsCache.remove(key);
    return _remember(
      _shortsCache,
      key,
      const Duration(minutes: 10),
      () => _retry(
        () => SparkBoxCore.shorts(perPage: perPage, maxPages: maxPages),
        isUsable: (value) =>
            (value['items'] as List? ?? const <dynamic>[]).isNotEmpty,
      ),
    );
  }

  static Future<List<String>> suggest(String query) =>
      SparkBoxCore.suggest(query);

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _searchCache = {};

  static Future<Map<String, dynamic>> search(
    String query, {
    int page = 1,
    int perPage = 20,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Future<Map<String, dynamic>>.value(
        <String, dynamic>{'items': <dynamic>[]},
      );
    }
    final key = '${normalizedQuery.toLowerCase()}:$page:$perPage';
    return _remember(
      _searchCache,
      key,
      const Duration(minutes: 2),
      () => _retry(
        () => SparkBoxCore.search(
          normalizedQuery,
          page: page,
          perPage: perPage,
        ),
      ),
    );
  }

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _detailCache = {};

  static Future<Map<String, dynamic>> detail(
    Map<String, dynamic> item,
  ) {
    final id = _subjectId(item);
    if (id.isEmpty) {
      return _retry(
        () => SparkBoxCore.detailRich(item),
        isUsable: (value) => value.isNotEmpty,
      );
    }
    return _remember(
      _detailCache,
      id,
      const Duration(minutes: 5),
      () => _retry(
        () => SparkBoxCore.detailRich(item),
        isUsable: (value) => value.isNotEmpty,
      ),
    );
  }

  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _playDetailCache = {};
  static final Map<String, _MovieBoxCacheEntry<List<Map<String, dynamic>>>>
      _seasonsCache = {};
  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _streamsCache = {};
  static final Map<String, _MovieBoxCacheEntry<Map<String, dynamic>>>
      _fastStreamsCache = {};

  static String _subjectId(Map<String, dynamic> item) =>
      (item['id'] ?? item['subjectId'] ?? item['subject_id'] ?? '')
          .toString()
          .trim();

  static Future<T> _retry<T>(
    Future<T> Function() load, {
    bool Function(T value)? isUsable,
    int? maxAttempts,
  }) async {
    Object? lastError;
    final attempts = maxAttempts ?? MovieBoxStreamPolicy.maxAttempts;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final value = await load();
        if (isUsable == null || isUsable(value)) return value;
        lastError = StateError('MovieBox returned no usable playback data.');
      } catch (error) {
        lastError = error;
      }
      if (attempt + 1 < attempts) {
        await Future.delayed(MovieBoxStreamPolicy.retryDelay);
      }
    }
    throw lastError ?? StateError('MovieBox request failed.');
  }

  static Future<T> _remember<T>(
    Map<String, _MovieBoxCacheEntry<T>> cache,
    String key,
    Duration ttl,
    Future<T> Function() load,
  ) {
    final now = DateTime.now();

    // Bound every in-memory MovieBox cache. Search and stream keys are
    // user-driven, so without pruning they can grow for the lifetime of the
    // TV app process. Expired entries are removed first; when the cache is
    // still full, evict the oldest entry while preserving the requested key.
    cache.removeWhere(
      (_, entry) => now.difference(entry.createdAt) >= ttl,
    );

    final existing = cache[key];
    if (existing != null) return existing.future;

    const maxEntries = 80;
    if (cache.length >= maxEntries) {
      final oldestEntries = cache.entries.toList()
        ..sort(
          (a, b) => a.value.createdAt.compareTo(b.value.createdAt),
        );
      final removeCount = cache.length - maxEntries + 1;
      for (final entry in oldestEntries.take(removeCount)) {
        if (entry.key != key) cache.remove(entry.key);
      }
    }

    final future = load();
    final entry = _MovieBoxCacheEntry<T>(
      createdAt: now,
      future: future,
    );
    cache[key] = entry;
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        if (identical(cache[key], entry)) cache.remove(key);
      },
    );
    return future;
  }

  static Future<Map<String, dynamic>> playDetail(
    Map<String, dynamic> item, {
    bool forceRefresh = false,
  }) {
    final id = _subjectId(item);
    if (id.isEmpty) {
      return _retry(
        () => SparkBoxCore.playDetail(item),
        isUsable: (value) => value.isNotEmpty,
        maxAttempts: 1,
      );
    }
    if (forceRefresh) _playDetailCache.remove(id);
    return _remember(
      _playDetailCache,
      id,
      const Duration(minutes: 2),
      () => _retry(
        () => SparkBoxCore.playDetail(item),
        isUsable: (value) => value.isNotEmpty,
        maxAttempts: 1,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> seasons(String subjectId) =>
      _remember(
        _seasonsCache,
        subjectId,
        const Duration(minutes: 5),
        () => _retry(
          () => SparkBoxCore.seasons(subjectId),
          isUsable: (items) => items.isNotEmpty,
          maxAttempts: 2,
        ),
      );

  static Future<Map<String, dynamic>> streams(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
    bool forceRefresh = false,
  }) {
    final subject = (detail['subjectId'] ??
            detail['subject_id'] ??
            detail['id'] ??
            detail['detailPath'] ??
            detail.toString())
        .toString();
    final key = '$subject:$season:$episode:$isSeries';
    if (forceRefresh) _streamsCache.remove(key);
    return _remember(
      _streamsCache,
      key,
      const Duration(seconds: 30),
      () => _retry(
        () => SparkBoxCore.streams(
          detail,
          season: season,
          episode: episode,
          isSeries: isSeries,
        ),
        isUsable: MovieBoxStreamPolicy.hasPlayableLinks,
        maxAttempts: 1,
      ),
    );
  }

  /// Fast playback request: Original stream only; full language/subtitle
  /// enrichment remains available through [streams] after playback starts.
  static Future<Map<String, dynamic>> streamsFast(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required bool isSeries,
    bool forceRefresh = false,
  }) {
    final subject = (detail['subjectId'] ??
            detail['subject_id'] ??
            detail['id'] ??
            detail['detailPath'] ??
            detail.toString())
        .toString();
    final key = '$subject:$season:$episode:$isSeries';
    if (forceRefresh) _fastStreamsCache.remove(key);
    return _remember(
      _fastStreamsCache,
      key,
      const Duration(seconds: 30),
      () => _retry(
        () => SparkBoxCore.streamsFast(
          detail,
          season: season,
          episode: episode,
          isSeries: isSeries,
        ),
        isUsable: MovieBoxStreamPolicy.hasPlayableLinks,
        maxAttempts: 1,
      ),
    );
  }

  /// Resolve the first playable item while the movie details screen is open.
  /// The player and download actions reuse these short-lived requests.
  static Future<Map<String, dynamic>?> prewarmStreams(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) async {
    final id = _subjectId(item);
    if (id.isEmpty) return null;

    try {
      final requests = <Future<dynamic>>[playDetail(item)];
      if (isSeries) requests.add(seasons(id));
      final resolved = await Future.wait<dynamic>(requests);
      final detail = Map<String, dynamic>.from(resolved.first as Map);
      if (detail.isEmpty) return null;

      var season = 0;
      var episode = 0;
      if (isSeries) {
        final availableSeasons =
            resolved[1] as List<Map<String, dynamic>>;
        if (availableSeasons.isEmpty) return null;
        final firstSeason = availableSeasons.first;
        season = int.tryParse(
              (firstSeason['se'] ??
                      firstSeason['season'] ??
                      firstSeason['seasonNumber'] ??
                      '')
                  .toString(),
            ) ??
            0;
        final episodes = firstSeason['episodes'] as List? ??
            firstSeason['episodeList'] as List? ??
            const [];
        if (episodes.isNotEmpty) {
          final firstEpisode = episodes.first;
          final episodeValue = firstEpisode is Map
              ? (firstEpisode['ep'] ??
                  firstEpisode['episode'] ??
                  firstEpisode['episodeNumber'] ??
                  firstEpisode['number'])
              : firstEpisode;
          episode = int.tryParse(episodeValue.toString()) ?? 0;
        }
        if (season <= 0) return null;
      }

      final resolvedStreams = await streamsFast(
        detail,
        season: season,
        episode: episode,
        isSeries: isSeries,
      );
      return MovieBoxStreamPolicy.hasPlayableLinks(resolvedStreams)
          ? resolvedStreams
          : null;
    } catch (_) {
      // Prefetch is opportunistic; the player still reports real failures.
      return null;
    }
  }

  static Future<void> prewarm(
    Map<String, dynamic> item, {
    required bool isSeries,
  }) async {
    await prewarmStreams(item, isSeries: isSeries);
  }
}

class _MovieBoxCacheEntry<T> {
  const _MovieBoxCacheEntry({
    required this.createdAt,
    required this.future,
  });

  final DateTime createdAt;
  final Future<T> future;
}
