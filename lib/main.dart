import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:app_settings/app_settings.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as cache_manager;
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/notification_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'video_quality_service.dart';
import 'streaming/featured_carousel_layout.dart';
import 'streaming/hero_slider_mixer.dart';
import 'streaming/catalog_source_policy.dart';
import 'streaming/tmdb_media_type.dart';
import 'archive_service.dart';
import 'archive_screen.dart';
import 'downloads/resumable_download_service.dart';
import 'native/rust_playback_core.dart';
import 'streaming/moviebox_service.dart';
import 'streaming/moviebox_stream_policy.dart';
import 'streaming/trending_movie_eligibility.dart';
import 'player/picture_in_picture_service.dart';
import 'player/playback_error_policy.dart';
import 'services/catalog_visibility_service.dart';

SupabaseClient? supabaseClient;

const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY');
const String authRedirectUrl =
    'com.flixora.flixora://login-callback/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep remote-control focus indicators visible on Android TV / Google TV.
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.always;
  MediaKit.ensureInitialized();

  unawaited(
    FlixoraNotificationService.initialize().catchError((Object error) {
      debugPrint('FLIXORA notification initialization failed: $error');
    }),
  );

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        publishableKey: supabaseAnonKey,
      );
      supabaseClient = Supabase.instance.client;
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
    }
  }

  runApp(const FlixoraApp());
}

// FLIXORA cinematic surfaces: deep black, white typography and warm gold.
const Color bg = Color(0xFF080808);
const Color panel = Color(0xFF181818);
const Color gold = Color(0xFFD6AD45);
const Color goldLight = Color(0xFFF2CF75);
const Color premiumGold = Color(0xFFE8C15A);
const Color white = Color(0xFFFFFFFF);
const Color ink = Color(0xFFFFFFFF);
const Color ink70 = Color(0xB3FFFFFF);
const Color ink60 = Color(0x99FFFFFF);
const Color ink58 = Color(0x94FFFFFF);
const Color ink54 = Color(0x8AFFFFFF);
const Color ink38 = Color(0x61FFFFFF);
const Color ink24 = Color(0x3DFFFFFF);
const Color ink12 = Color(0x1FFFFFFF);
const Color ink10 = Color(0x1AFFFFFF);
const Color playerBg = Color(0xFF080808);
const Color playerPanel = Color(0xFF191919);
const Color playerGold = Color(0xFFD6AD45);
const Color playerGoldLight = Color(0xFFF2CF75);
const Color playerWhite = Colors.white;

const String imageBase = 'https://image.tmdb.org/t/p/';
const String apiKey = String.fromEnvironment('TMDB_API_KEY');

int _toInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _tmdbGenreNames(dynamic raw) {
  const names = <int, String>{
    28: 'Action', 12: 'Adventure', 16: 'Animation', 35: 'Comedy',
    80: 'Crime', 99: 'Documentary', 18: 'Drama', 10751: 'Family',
    14: 'Fantasy', 36: 'History', 27: 'Horror', 10402: 'Music',
    9648: 'Mystery', 10749: 'Romance', 878: 'Sci-Fi', 10770: 'TV Movie',
    53: 'Thriller', 10752: 'War', 37: 'Western', 10759: 'Action & Adventure',
    10762: 'Kids', 10763: 'News', 10764: 'Reality', 10765: 'Sci-Fi & Fantasy',
    10766: 'Soap', 10767: 'Talk', 10768: 'War & Politics',
  };
  if (raw is List) {
    return raw.map((item) {
      if (item is Map) return (item['name'] ?? '').toString();
      return names[_toInt(item)] ?? '';
    }).where((name) => name.isNotEmpty).toList();
  }
  return [];
}

/// Legacy model name retained for compatibility; this represents any FLIXORA
/// catalogue title, including movies, TV shows, web series, dramas and anime.
class Movie {
  final int id;
  final int tmdbId;
  final int sourceId;
  final String source;
  final String title;
  final String year;
  final String overview;
  final String poster;
  final String backdrop;
  final double rating;
  final String releaseDate;
  final List<String> genres;
  final double? runtime;
  final String videoUrl;
  final String downloadUrl;
  final String mediaType;
  final String originalLanguage;
  final String originCountry;
  final List<String> audioLanguages;
  final String movieBoxId;
  final String movieBoxDetailPath;
  final bool movieBoxIsSeries;
  final int movieBoxSubjectType;

  const Movie({
    required this.id,
    this.tmdbId = 0,
    this.sourceId = 0,
    this.source = 'tmdb',
    required this.title,
    required this.year,
    required this.overview,
    required this.poster,
    required this.backdrop,
    required this.rating,
    required this.releaseDate,
    this.genres = const [],
    this.runtime,
    this.videoUrl = '',
    this.downloadUrl = '',
    this.mediaType = 'movie',
    this.originalLanguage = '',
    this.originCountry = '',
    this.audioLanguages = const [],
    this.movieBoxId = '',
    this.movieBoxDetailPath = '',
    this.movieBoxIsSeries = false,
    this.movieBoxSubjectType = 1,
  });

  bool get isFlixora => source == 'flixora';
  bool get isMovieBox => source == 'moviebox' && movieBoxId.isNotEmpty;

  bool get hasPlayableVideoUrl {
    final uri = Uri.tryParse(videoUrl.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Only Admin-managed direct media and MovieBox/WeFeed-resolved titles
  /// are playable. A TMDB ID alone is metadata, not a video source.
  bool get canAttemptPlayback => hasPlayableVideoUrl || isMovieBox;

  Movie withFallbackMetadata(Movie fallback) => Movie(
        id: id,
        tmdbId: tmdbId > 0 ? tmdbId : fallback.tmdbId,
        sourceId: sourceId > 0 ? sourceId : fallback.sourceId,
        source: source,
        title: title.trim().isNotEmpty && title != 'Unknown Title'
            ? title
            : fallback.title,
        year: year != 'N/A' ? year : fallback.year,
        overview: overview.trim().isNotEmpty &&
                overview != 'No description available.'
            ? overview
            : fallback.overview,
        poster: poster.isNotEmpty ? poster : fallback.poster,
        backdrop: backdrop.isNotEmpty ? backdrop : fallback.backdrop,
        rating: rating > 0 ? rating : fallback.rating,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : fallback.releaseDate,
        genres: genres.isNotEmpty ? genres : fallback.genres,
        runtime: runtime ?? fallback.runtime,
        videoUrl: videoUrl.isNotEmpty ? videoUrl : fallback.videoUrl,
        downloadUrl: downloadUrl.isNotEmpty ? downloadUrl : fallback.downloadUrl,
        mediaType: mediaType,
        originalLanguage: originalLanguage.isNotEmpty ? originalLanguage : fallback.originalLanguage,
        originCountry: originCountry.isNotEmpty ? originCountry : fallback.originCountry,
        audioLanguages: audioLanguages.isNotEmpty ? audioLanguages : fallback.audioLanguages,
        movieBoxId: movieBoxId.isNotEmpty ? movieBoxId : fallback.movieBoxId,
        movieBoxDetailPath: movieBoxDetailPath.isNotEmpty ? movieBoxDetailPath : fallback.movieBoxDetailPath,
        movieBoxIsSeries: movieBoxId.isNotEmpty ? movieBoxIsSeries : fallback.movieBoxIsSeries,
        movieBoxSubjectType: movieBoxId.isNotEmpty ? movieBoxSubjectType : fallback.movieBoxSubjectType,
      );

  factory Movie.fromMovieBox(Map<String, dynamic> json) {
    final subjectId = (json['id'] ?? '').toString().trim();
    var stableId = 0;
    for (final unit in subjectId.codeUnits) {
      stableId = ((stableId * 31) + unit) & 0x7fffffff;
    }
    if (stableId == 0) stableId = 1;

    final subjectType = _toInt(json['subjectType']);
    final tmdbRaw = json['tmdbId'] ??
        json['tmdb_id'] ??
        json['tmdbID'] ??
        (json['tmdb'] is Map ? (json['tmdb'] as Map)['id'] : null);
    final tmdbId = _toInt(tmdbRaw);
    final isSeries = json['isSeries'] == true || subjectType == 2 || subjectType == 3 || subjectType == 7;
    final rawYear = (json['year'] ?? '').toString().trim();
    final genreText = (json['genre'] ?? '').toString();
    final genres = genreText
        .split(',')
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .toList(growable: false);

    return Movie(
      id: -stableId,
      tmdbId: tmdbId,
      source: 'moviebox',
      title: (json['title'] ?? 'Unknown Title').toString(),
      year: rawYear.length >= 4 ? rawYear.substring(0, 4) : 'N/A',
      overview: (json['description'] ?? 'No description available.').toString(),
      poster: (json['cover'] ?? '').toString(),
      backdrop: (json['backdrop'] ?? '').toString(),
      rating: double.tryParse((json['rating'] ?? '').toString()) ?? 0,
      releaseDate: '',
      genres: genres,
      runtime: _toInt(json['durationMin']) > 0
          ? _toInt(json['durationMin']).toDouble()
          : null,
      mediaType: isSeries ? 'tv' : 'movie',
      originCountry: (json['country'] ?? '').toString(),
      movieBoxId: subjectId,
      movieBoxDetailPath: (json['detailPath'] ?? '').toString(),
      movieBoxIsSeries: isSeries,
      movieBoxSubjectType: subjectType > 0 ? subjectType : (isSeries ? 2 : 1),
    );
  }

  Map<String, dynamic> toMovieBoxMap() => {
        'id': movieBoxId,
        'tmdbId': tmdbId,
        'title': title,
        'isSeries': movieBoxIsSeries,
        'detailPath': movieBoxDetailPath,
        'cover': poster,
        'backdrop': backdrop,
        'rating': rating.toString(),
        'year': year,
        'genre': genres.join(', '),
        'country': originCountry,
        'description': overview,
        'durationMin': runtime?.round() ?? 0,
        'subjectType': movieBoxSubjectType,
      };

  factory Movie.fromJson(Map<String, dynamic> json, {String? mediaType}) {
    final date = (json['release_date'] ?? json['first_air_date'] ?? '').toString();
    final movieId = _toInt(json['id']);

    return Movie(
      id: movieId,
      tmdbId: movieId,
      title: (json['title'] ?? json['name'] ?? 'Unknown Title').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : 'N/A',
      releaseDate: date,
      overview: (json['overview'] ?? 'No description available.').toString(),
      poster: (json['poster_path'] ?? '').toString(),
      backdrop: (json['backdrop_path'] ?? '').toString(),
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
      genres: _tmdbGenreNames(json['genre_ids'] ?? json['genres']),
      mediaType: mediaType ?? (json['media_type'] ?? 'movie').toString(),
      originalLanguage: (json['original_language'] ?? '').toString(),
      originCountry: ((json['origin_country'] is List && (json['origin_country'] as List).isNotEmpty)
              ? (json['origin_country'] as List).first
              : '').toString(),
    );
  }

  factory Movie.fromSupabase(Map<String, dynamic> json) {
    final dbId = _toInt(json['id']);
    final tmdbId = _toInt(json['tmdb_id']);
    final date = (json['release_date'] ?? '').toString();
    final rawGenres = json['genre'];

    final genreList = rawGenres is List
        ? rawGenres.map((item) => item.toString()).toList()
        : <String>[];

    return Movie(
      id: -dbId.abs(),
      sourceId: dbId,
      tmdbId: tmdbId,
      source: 'flixora',
      title: (json['title'] ?? 'Unknown Title').toString(),
      year: date.length >= 4 ? date.substring(0, 4) : 'N/A',
      releaseDate: date,
      overview: (json['description'] ?? 'No description available.').toString(),
      poster: (json['poster_url'] ?? '').toString(),
      backdrop: (json['backdrop_url'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      genres: genreList,
      runtime: (json['runtime'] as num?)?.toDouble(),
      videoUrl: (json['video_url'] ?? '').toString(),
      downloadUrl: (json['download_url'] ?? '').toString(),
      mediaType: (json['media_type'] ?? 'movie').toString() == 'tv'
          ? 'tv'
          : 'movie',
    );
  }

  factory Movie.fromCache(Map<String, dynamic> json) {
    final cachedId = _toInt(json['id']);
    final cachedSource = (json['source'] ?? 'tmdb').toString();
    final cachedTmdbId = _toInt(json['tmdbId']);

    return Movie(
      id: cachedId,
      tmdbId: cachedTmdbId > 0
          ? cachedTmdbId
          : (cachedSource == 'tmdb' ? cachedId : 0),
      sourceId: _toInt(json['sourceId']),
      source: cachedSource,
      title: (json['title'] ?? 'Unknown Title').toString(),
      year: (json['year'] ?? 'N/A').toString(),
      overview: (json['overview'] ?? '').toString(),
      poster: (json['poster'] ?? '').toString(),
      backdrop: (json['backdrop'] ?? '').toString(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      releaseDate: (json['releaseDate'] ?? '').toString(),
      genres: (json['genres'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      runtime: (json['runtime'] as num?)?.toDouble(),
      videoUrl: (json['videoUrl'] ?? '').toString(),
      downloadUrl: (json['downloadUrl'] ?? '').toString(),
      mediaType: (json['mediaType'] ?? 'movie').toString(),
      originalLanguage: (json['originalLanguage'] ?? '').toString(),
      originCountry: (json['originCountry'] ?? '').toString(),
      audioLanguages: (json['audioLanguages'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      movieBoxId: (json['movieBoxId'] ?? '').toString(),
      movieBoxDetailPath: (json['movieBoxDetailPath'] ?? '').toString(),
      movieBoxIsSeries: json['movieBoxIsSeries'] == true,
      movieBoxSubjectType: _toInt(json['movieBoxSubjectType']) > 0
          ? _toInt(json['movieBoxSubjectType'])
          : 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'tmdbId': tmdbId,
        'sourceId': sourceId,
        'source': source,
        'title': title,
        'year': year,
        'overview': overview,
        'poster': poster,
        'backdrop': backdrop,
        'rating': rating,
        'releaseDate': releaseDate,
        'genres': genres,
        'runtime': runtime,
        'videoUrl': videoUrl,
        'downloadUrl': downloadUrl,
        'mediaType': mediaType,
        'originalLanguage': originalLanguage,
        'originCountry': originCountry,
        'audioLanguages': audioLanguages,
        'movieBoxId': movieBoxId,
        'movieBoxDetailPath': movieBoxDetailPath,
        'movieBoxIsSeries': movieBoxIsSeries,
        'movieBoxSubjectType': movieBoxSubjectType,
      };

  bool _isFullUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  String get posterUrl {
    if (poster.isEmpty) return '';
    if (_isFullUrl(poster)) return poster;
    return '${imageBase}w500$poster';
  }

  String get backdropUrl {
    if (backdrop.isEmpty) return '';
    if (_isFullUrl(backdrop)) return backdrop;
    return '${imageBase}w1280$backdrop';
  }
}

class MovieBoxShortEpisode {
  const MovieBoxShortEpisode({
    required this.season,
    required this.episode,
  });

  final int season;
  final int episode;

  String get label => 'S$season · E$episode';

  static List<MovieBoxShortEpisode> fromSeasons(
    Iterable<Map<String, dynamic>> seasons,
  ) {
    int seasonNumberOf(Map<String, dynamic> season) => _toInt(
          season['se'] ?? season['season'] ?? season['seasonNumber'],
        );

    final orderedSeasons = seasons.toList()
      ..sort((a, b) => seasonNumberOf(a).compareTo(seasonNumberOf(b)));
    final episodes = <MovieBoxShortEpisode>[];
    final seen = <String>{};

    for (final season in orderedSeasons) {
      final seasonNumber = seasonNumberOf(season);
      if (seasonNumber <= 0) continue;

      final rawEpisodes = season['episodes'] ??
          season['episodeList'] ??
          season['eps'];
      final episodeValues = rawEpisodes is List
          ? rawEpisodes
          : (season['allEp'] is String
              ? (season['allEp'] as String)
                  .split(RegExp(r'[,; ]+'))
                  .where((value) => value.isNotEmpty)
                  .toList()
              : const <dynamic>[]);

      for (final rawEpisode in episodeValues) {
        final value = rawEpisode is Map
            ? (rawEpisode['ep'] ??
                rawEpisode['episode'] ??
                rawEpisode['episodeNumber'] ??
                rawEpisode['number'])
            : rawEpisode;
        final episodeNumber = _toInt(value);
        final key = '$seasonNumber:$episodeNumber';
        if (episodeNumber > 0 && seen.add(key)) {
          episodes.add(MovieBoxShortEpisode(
            season: seasonNumber,
            episode: episodeNumber,
          ));
        }
      }
    }

    episodes.sort((a, b) {
      final seasonOrder = a.season.compareTo(b.season);
      return seasonOrder != 0
          ? seasonOrder
          : a.episode.compareTo(b.episode);
    });
    return episodes;
  }
}

class MovieBoxHomeSection {
  final String title;
  final List<Movie> items;
  final bool ranked;
  final bool isBanner;

  const MovieBoxHomeSection({
    required this.title,
    required this.items,
    this.ranked = false,
    this.isBanner = false,
  });

  bool get isFlixoraOriginal {
    final normalizedTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return normalizedTitle.contains('flixora original');
  }

  bool get isHotShorts {
    final normalizedTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    return normalizedTitle.contains('hot short') ||
        (normalizedTitle.contains('short') && normalizedTitle.contains('tv'));
  }

  factory MovieBoxHomeSection.fromApi(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return MovieBoxHomeSection(
      title: (json['title'] ?? 'Featured').toString().replaceAll(RegExp('moviebox', caseSensitive: false), 'FLIXORA'),
      items: rawItems
          .whereType<Map>()
          .map((item) => Movie.fromMovieBox(Map<String, dynamic>.from(item)))
          .where((movie) => movie.movieBoxId.isNotEmpty)
          .toList(growable: false),
      ranked: json['ranked'] == true,
      isBanner: json['isBanner'] == true,
    );
  }

  factory MovieBoxHomeSection.fromCache(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return MovieBoxHomeSection(
      title: (json['title'] ?? 'Featured').toString().replaceAll(RegExp('moviebox', caseSensitive: false), 'FLIXORA'),
      items: rawItems
          .whereType<Map>()
          .map((item) => Movie.fromCache(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      ranked: json['ranked'] == true,
      isBanner: json['isBanner'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'ranked': ranked,
        'isBanner': isBanner,
        'items': items.map((movie) => movie.toJson()).toList(),
      };
}

/// Displays network images online, but reads disk cache only while offline.
/// A cache miss offline never starts a network request.
class FlixoraImageCacheManager {
  FlixoraImageCacheManager._();

  // Reuse DefaultCacheManager's existing cache key so already-downloaded
  // posters remain available, while allowing a larger catalogue cache.
  static final cache_manager.CacheManager instance = cache_manager.CacheManager(
    cache_manager.Config(
      'libCachedImageData',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 600,
    ),
  );
}

/// Displays network images online, but reads disk cache only while offline.
/// A cache miss offline never starts a network request.
class FlixoraCachedImage extends StatelessWidget {
  static final Map<String, Future<cache_manager.FileInfo?>> _offlineLookups = {};

  static Future<cache_manager.FileInfo?> _offlineFile(String url) {
    final existing = _offlineLookups[url];
    if (existing != null) return existing;
    final future = FlixoraImageCacheManager.instance.getFileFromCache(url);
    _offlineLookups[url] = future;
    future.then<void>((info) {
      if (info == null || !info.file.existsSync()) _offlineLookups.remove(url);
    }, onError: (Object error, StackTrace stackTrace) {
      _offlineLookups.remove(url);
    });
    return future;
  }

  final String imageUrl;
  final BoxFit fit;
  final bool isOnline;
  final Widget? placeholder;
  final Widget? fallback;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const FlixoraCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    required this.isOnline,
    this.placeholder,
    this.fallback,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  Widget _buildForSize(int? width, int? height) {
    final empty = fallback ?? Container(color: panel);
    if (isOnline) {
      return CachedNetworkImage(
        cacheManager: FlixoraImageCacheManager.instance,
        imageUrl: imageUrl,
        fit: fit,
        memCacheWidth: width,
        memCacheHeight: height,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, __) => placeholder ?? Container(color: panel),
        errorWidget: (_, __, ___) => empty,
      );
    }

    return FutureBuilder<cache_manager.FileInfo?>(
      future: _offlineFile(imageUrl),
      builder: (context, snapshot) {
        final file = snapshot.data?.file;
        if (file != null && file.existsSync()) {
          return Image.file(
            file,
            fit: fit,
            cacheWidth: width,
            cacheHeight: height,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return placeholder ?? Container(color: panel);
        }
        return empty;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) return fallback ?? Container(color: panel);

    // Most FLIXORA cards already know their decode dimensions. Skip an
    // unnecessary LayoutBuilder/MediaQuery pass for those common cases.
    if (memCacheWidth != null && memCacheHeight != null) {
      return _buildForSize(memCacheWidth, memCacheHeight);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        final resolvedWidth = memCacheWidth ??
            (constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? (constraints.maxWidth * pixelRatio)
                    .round()
                    .clamp(1, 1600)
                    .toInt()
                : null);
        final resolvedHeight = memCacheHeight ??
            (constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? (constraints.maxHeight * pixelRatio)
                    .round()
                    .clamp(1, 1600)
                    .toInt()
                : null);
        return _buildForSize(resolvedWidth, resolvedHeight);
      },
    );
  }
}

class InternetService {
  static bool? _cachedOnline;
  static DateTime? _lastCheck;
  static Future<bool>? _checkInFlight;
  static const Duration _cacheDuration = Duration(seconds: 20);

  static void invalidateCache() {
    _cachedOnline = null;
    _lastCheck = null;
  }

  static Future<bool> isOnline({bool forceRefresh = false}) async {
    final checkedAt = _lastCheck;
    if (!forceRefresh &&
        _cachedOnline != null &&
        checkedAt != null &&
        DateTime.now().difference(checkedAt) < _cacheDuration) {
      return _cachedOnline!;
    }

    final pending = _checkInFlight;
    if (pending != null) return pending;

    final request = _performCheck();
    _checkInFlight = request;
    try {
      final online = await request;
      _cachedOnline = online;
      _lastCheck = DateTime.now();
      return online;
    } finally {
      if (identical(_checkInFlight, request)) _checkInFlight = null;
    }
  }

  static Future<bool> _performCheck() async {
    // Do not tie app connectivity to the MovieBox host: its API can be
    // temporarily unavailable while the device still has internet access.
    // GET is used because some networks/CDNs reject HEAD requests.
    final endpoints = <Uri>[
      Uri.parse('https://www.google.com/generate_204'),
      Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'),
      if (apiKey.isNotEmpty)
        Uri.parse(
          'https://api.themoviedb.org/3/configuration?api_key=$apiKey',
        ),
    ];
    final completer = Completer<bool>();
    var remaining = endpoints.length;

    for (final endpoint in endpoints) {
      unawaited(() async {
        var reachable = false;
        try {
          final response = await http
              .get(
                endpoint,
                headers: const {'Cache-Control': 'no-cache'},
              )
              .timeout(const Duration(seconds: 4));
          reachable = response.statusCode >= 200 && response.statusCode < 500;
        } catch (_) {}

        if (reachable && !completer.isCompleted) {
          completer.complete(true);
        }
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.complete(false);
        }
      }());
    }

    return completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => false,
    );
  }
}
class MovieCache {
  static const String trendingKey = 'flixora_trending';
  static const String playableTrendingMoviesKey = 'flixora_playable_trending_movies';
  static const String tmdbTrendingMoviesKey = 'flixora_tmdb_trending_movies';
  static const String tmdbTrendingTvKey = 'flixora_tmdb_trending_tv_week';
  static const String pakistaniTrendingTvKey = 'flixora_pakistani_trending_tv';
  static const String koreanTrendingMoviesKey = 'flixora_korean_trending_movies';
  static const String trendingHindiDubbedKey = 'flixora_trending_hindi_dubbed';
  static const String trendingBollywoodKey = 'flixora_trending_bollywood';
  static const String trendingHollywoodKey = 'flixora_trending_hollywood';
  static const String popularKey = 'flixora_popular';
  static const String latestKey = 'flixora_latest';
  static const String topRatedKey = 'flixora_top_rated';
  static const String flixoraKey = 'flixora_published';
  static const String favouritesKey = 'flixora_favourites';
  static const String savedKey = 'flixora_saved';
  static const String historyKey = 'flixora_watch_history';
  static const String downloadsKey = 'flixora_downloads';
  static const String trendingTvKey = 'flixora_trending_tv';
  static const String popularTvKey = 'flixora_popular_tv';
  static const String topRatedTvKey = 'flixora_top_rated_tv';
  static const String animeKey = 'flixora_anime';
  static const String koreanKey = 'flixora_korean_drama';
  static const String bengaliMoviesKey = 'flixora_bengali_movies';
  static const String bengaliTvKey = 'flixora_bengali_tv';
  static const String bollywoodMoviesKey = 'flixora_bollywood_movies';
  static const String hollywoodMoviesKey = 'flixora_hollywood_movies';
  static const String southIndianMoviesKey = 'flixora_south_indian_movies';
  static const String indianDramaTvKey = 'flixora_indian_drama_tv';
  static const String movieBoxSectionsKey = 'flixora_moviebox_sections';

  static Future<void> saveDownloads(List<DownloadTask> tasks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        downloadsKey,
        jsonEncode(tasks.where((task) => task.filePath != null).map((task) => task.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<List<DownloadTask>> getDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(downloadsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      final tasks = decoded
          .whereType<Map>()
          .map(
            (item) => DownloadTask.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      final valid = <DownloadTask>[];
      for (final task in tasks) {
        if (task.filePath != null && await File(task.filePath!).exists()) {
          final partialSize = await File(task.filePath!).length();
          if (task.status == 'Downloading' || task.status == 'Waiting') {
            task.status = 'Paused';
          }
          if (task.status != 'Completed') {
            task.bytesReceived = partialSize;
            if (task.totalBytes > 0) {
              task.progress =
                  (partialSize / task.totalBytes).clamp(0.0, 1.0);
            }
          }
          valid.add(task);
        }
      }
      // Remove stale records whose local video file no longer exists.
      await prefs.setString(
        downloadsKey,
        jsonEncode(valid.map((task) => task.toJson()).toList()),
      );
      return valid;
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveList(String key, List<Movie> movies) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        movies.map((movie) => movie.toJson()).toList(),
      );
      await prefs.setString(key, encoded);
    } catch (_) {}
  }

  static Future<List<Movie>> getList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(key);

      if (value == null || value.isEmpty) return [];

      final decoded = jsonDecode(value) as List;

      return decoded
          .whereType<Map>()
          .map(
            (item) => Movie.fromCache(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMovieBoxSections(
    List<MovieBoxHomeSection> sections,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        movieBoxSectionsKey,
        jsonEncode(sections.map((section) => section.toJson()).toList()),
      );
    } catch (_) {}
  }

  static Future<List<MovieBoxHomeSection>> getMovieBoxSections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(movieBoxSectionsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((item) => MovieBoxHomeSection.fromCache(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSearch(String query, List<Movie> movies) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    await saveList(key, movies);
  }

  static Future<List<Movie>> getSearch(String query) async {
    final key = 'flixora_search_${query.trim().toLowerCase()}';
    return getList(key);
  }

  static Future<Set<int>> getFavourites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(favouritesKey) ?? [])
          .map(int.parse)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveFavourites(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        favouritesKey,
        ids.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }

  static Future<Set<int>> getSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(savedKey) ?? [])
          .map(int.parse)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveSaved(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        savedKey,
        ids.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }
}

class _TimedMovieListCacheEntry {
  const _TimedMovieListCacheEntry({
    required this.createdAt,
    required this.future,
  });

  final DateTime createdAt;
  final Future<List<Movie>> future;
}

class TmdbService {
  static const String base = 'https://api.themoviedb.org/3';
  static const Duration _catalogueCacheDuration = Duration(minutes: 5);
  static const Duration _searchCacheDuration = Duration(minutes: 2);
  static final Map<String, _TimedMovieListCacheEntry> _catalogueCache = {};
  static final Map<String, _TimedMovieListCacheEntry> _searchCache = {};

  static Future<List<Movie>> _rememberMovies(
    Map<String, _TimedMovieListCacheEntry> cache,
    String key,
    Duration ttl,
    Future<List<Movie>> Function() load, {
    bool forceRefresh = false,
  }) {
    if (forceRefresh) cache.remove(key);
    final now = DateTime.now();
    final existing = cache[key];
    if (existing != null && now.difference(existing.createdAt) < ttl) {
      return existing.future;
    }

    final future = load();
    final entry = _TimedMovieListCacheEntry(
      createdAt: now,
      future: future,
    );
    cache[key] = entry;
    future.then<void>((items) {
      if (items.isEmpty && identical(cache[key], entry)) {
        cache.remove(key);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (identical(cache[key], entry)) cache.remove(key);
    });
    return future;
  }

  /// Retries transient TMDB throttling and server errors instead of silently
  /// leaving a category with only one page of results.
  static Future<http.Response> _getWithRetry(Uri uri) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.get(uri).timeout(const Duration(seconds: 20));
        if (response.statusCode == 200 ||
            (response.statusCode != 429 && response.statusCode < 500) ||
            attempt == 2) {
          return response;
        }
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        final delay = retryAfter != null
            ? Duration(seconds: retryAfter.clamp(1, 5).toInt())
            : Duration(milliseconds: 400 * (attempt + 1));
        await Future.delayed(delay);
      } catch (_) {
        if (attempt == 2) rethrow;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    throw Exception('TMDB request failed after retries.');
  }

  static Future<List<Movie>> getMovies(
    String endpoint, {
    Map<String, String> extraParams = const {},
    int pages = 1,
    int startPage = 1,
    bool forceRefresh = false,
  }) {
    final sortedParams = extraParams.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final paramsKey = sortedParams
        .map((entry) => '${entry.key}=${entry.value}')
        .join('&');
    final key = '$endpoint|$paramsKey|$pages|$startPage';
    return _rememberMovies(
      _catalogueCache,
      key,
      _catalogueCacheDuration,
      () => _fetchMovies(
        endpoint,
        extraParams: extraParams,
        pages: pages,
        startPage: startPage,
      ),
      forceRefresh: forceRefresh,
    );
  }

  static Future<List<Movie>> _fetchMovies(
    String endpoint, {
    Map<String, String> extraParams = const {},
    int pages = 1,
    int startPage = 1,
  }) async {
    if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
    final isTv = TmdbMediaType.isTvEndpoint(endpoint);
    final pageCount = pages.clamp(1, 3).toInt();
    final firstPage = startPage.clamp(1, 500).toInt();
    final pageResults = await Future.wait<List<Movie>>(
      List<int>.generate(pageCount, (index) => index + firstPage).map((page) async {
        try {
          final uri = Uri.parse('$base/$endpoint').replace(queryParameters: {
            'api_key': apiKey,
            'language': 'en-US',
            'page': page.toString(),
            ...extraParams,
          });
          final response = await _getWithRetry(uri);
          if (response.statusCode != 200) {
            debugPrint('TMDB $endpoint page $page returned ${response.statusCode}');
            return <Movie>[];
          }
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final results = data['results'] as List? ?? [];
          return results.whereType<Map>().map((item) => Movie.fromJson(
            Map<String, dynamic>.from(item), mediaType: isTv ? 'tv' : 'movie',
          )).toList();
        } catch (error) {
          debugPrint('Catalogue page $page failed for $endpoint: $error');
          return <Movie>[];
        }
      }),
    );
    return _deduplicateCataloguePages(pageResults.expand((items) => items));
  }
  static List<Movie> _deduplicateCataloguePages(Iterable<Movie> movies) {
    final seen = <String>{};
    return movies.where((movie) {
      final key = movie.tmdbId > 0
          ? '${movie.mediaType}:${movie.tmdbId}'
          : '${movie.mediaType}:${movie.id}';
      return seen.add(key);
    }).toList();
  }

  static Future<List<Movie>> search(String query) {
    final normalized = query.trim();
    if (normalized.isEmpty) return Future<List<Movie>>.value(<Movie>[]);
    final key = normalized.toLowerCase();
    return _rememberMovies(
      _searchCache,
      key,
      _searchCacheDuration,
      () async {
        if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
        Future<List<Movie>> searchType(String type) async {
          final uri = Uri.parse('$base/search/$type').replace(queryParameters: {
            'api_key': apiKey,
            'query': normalized,
            'language': 'en-US',
            'page': '1',
            'include_adult': 'false',
          });
          final response = await _getWithRetry(uri);
          if (response.statusCode != 200) return [];
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final results = data['results'] as List? ?? [];
          return results.whereType<Map>().map((item) => Movie.fromJson(
            Map<String, dynamic>.from(item), mediaType: type,
          )).toList();
        }
        final results = await Future.wait([
          searchType('movie'),
          searchType('tv'),
        ]);
        return [...results[0], ...results[1]];
      },
    );
  }
  static Future<List<Map<String, dynamic>>> getCast(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty || id <= 0) return [];
    try {
      final uri = Uri.parse('$base/$mediaType/$id/credits').replace(
        queryParameters: {'api_key': apiKey, 'language': 'en-US'},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['cast'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .take(18)
          .toList();
    } catch (e) {
      debugPrint('Could not load cast information: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> seasonDetails(int tvId, int seasonNumber) async {
    if (apiKey.isEmpty || tvId <= 0 || seasonNumber < 0) {
      throw Exception('TV season information is not available.');
    }
    final uri = Uri.parse('$base/tv/$tvId/season/$seasonNumber').replace(
      queryParameters: {'api_key': apiKey, 'language': 'en-US'},
    );
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) {
      throw Exception("Could not load this season's episodes.");
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> details(
    int id, {String mediaType = 'movie'}
  ) async {
    if (apiKey.isEmpty) throw Exception('TMDB service is not configured.');
    final uri = Uri.parse('$base/$mediaType/$id').replace(queryParameters: {
      'api_key': apiKey, 'language': 'en-US',
      'append_to_response': 'external_ids',
    });
    final response = await _getWithRetry(uri);
    if (response.statusCode != 200) throw Exception('Could not load title details.');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class FlixoraMovieService {
  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Resolve Admin records to a real video URL before showing them as playable.
  /// Quality rows are keyed by the Supabase movies.id, not the TMDB ID.
  static Future<List<Movie>> mapPlayableRows(
    SupabaseClient client,
    List<dynamic> rawRows, {
    bool includeWithoutVideo = false,
  }) async {
    final rows = rawRows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final movieIds = rows
        .map((row) => _toInt(row['id']))
        .where((id) => id > 0)
        .toList();
    final qualityFallbacks = <int, Map<String, String>>{};
    final audioLanguagesByMovie = <int, List<String>>{};

    if (movieIds.isNotEmpty) {
      Future<void> loadAudioLanguages() async {
        try {
          final audioRows = await client
              .from('movie_languages')
              .select('movie_id, languages(name,code)')
              .inFilter('movie_id', movieIds);
          for (final item in (audioRows as List).whereType<Map>()) {
            final row = Map<String, dynamic>.from(item);
            final movieId = _toInt(row['movie_id']);
            final rawLanguage = row['languages'];
            if (movieId <= 0 || rawLanguage is! Map) continue;
            final language =
                (rawLanguage['name'] ?? rawLanguage['code'] ?? '')
                    .toString()
                    .trim();
            if (language.isNotEmpty) {
              (audioLanguagesByMovie[movieId] ??= <String>[]).add(language);
            }
          }
        } catch (error) {
          debugPrint('Could not load movie audio languages: $error');
        }
      }

      Future<void> loadQualityFallbacks() async {
        try {
          final qualityRows = await client
              .from('movie_video_qualities')
              .select('movie_id, quality, video_url')
              .inFilter('movie_id', movieIds);
          for (final item in (qualityRows as List).whereType<Map>()) {
            final row = Map<String, dynamic>.from(item);
            final movieId = _toInt(row['movie_id']);
            final quality = (row['quality'] ?? '').toString().trim();
            final url = (row['video_url'] ?? '').toString().trim();
            if (movieId <= 0 || quality.isEmpty || !_isHttpUrl(url)) continue;

            final current = qualityFallbacks[movieId];
            final currentQuality = current?['quality'] ?? '';
            final is720p = quality.toLowerCase() == '720p';
            final currentIs720p = currentQuality.toLowerCase() == '720p';
            final shouldReplace = current == null ||
                (is720p && !currentIs720p) ||
                (!currentIs720p &&
                    !is720p &&
                    VideoQualityService.rank(quality) >
                        VideoQualityService.rank(currentQuality));
            if (shouldReplace) {
              qualityFallbacks[movieId] = {
                'quality': quality,
                'video_url': url,
              };
            }
          }
        } catch (error) {
          debugPrint('Could not resolve Admin video qualities: $error');
        }
      }

      await Future.wait<void>([
        loadAudioLanguages(),
        loadQualityFallbacks(),
      ]);
    }

    return rows.map((row) {
      final movieId = _toInt(row['id']);
      final legacyUrl = (row['video_url'] ?? '').toString();
      if (!_isHttpUrl(legacyUrl)) {
        final fallbackUrl = qualityFallbacks[movieId]?['video_url'] ?? '';
        if (_isHttpUrl(fallbackUrl)) row['video_url'] = fallbackUrl;
      }
      final movie = Movie.fromSupabase(row);
      return Movie(
        id: movie.id, tmdbId: movie.tmdbId, sourceId: movie.sourceId,
        source: movie.source, title: movie.title, year: movie.year,
        overview: movie.overview, poster: movie.poster, backdrop: movie.backdrop,
        rating: movie.rating, releaseDate: movie.releaseDate, genres: movie.genres,
        runtime: movie.runtime, videoUrl: movie.videoUrl, downloadUrl: movie.downloadUrl,
        mediaType: movie.mediaType, originalLanguage: movie.originalLanguage,
        originCountry: movie.originCountry,
        audioLanguages: audioLanguagesByMovie[movieId] ?? const [],
      );
    }).where((movie) =>
        movie.sourceId > 0 &&
        (movie.hasPlayableVideoUrl ||
            (includeWithoutVideo &&
                (movie.mediaType == 'movie' || movie.mediaType == 'tv') &&
                movie.tmdbId > 0))).toList();
  }

  static Future<List<Map<String, String>>> getDownloadQualities(
    Movie movie,
  ) async {
    final client = supabaseClient;
    final options = <Map<String, String>>[];

    if (client != null && movie.sourceId > 0) {
      try {
        final rows = await client
            .from('movie_video_qualities')
            .select('quality, video_url')
            .eq('movie_id', movie.sourceId);
        for (final item in (rows as List).whereType<Map>()) {
          final quality = (item['quality'] ?? '').toString().trim();
          final url = (item['video_url'] ?? '').toString().trim();
          if (quality.isEmpty || !_isHttpUrl(url)) continue;
          final path = Uri.parse(url).path.toLowerCase();
          if (path.endsWith('.m3u8') || path.endsWith('.mpd')) continue;
          options.add({'quality': quality, 'video_url': url});
        }
      } catch (e) {
        debugPrint('Could not load download quality sources: $e');
      }
    }

    if (options.isEmpty && _isHttpUrl(movie.downloadUrl)) {
      final path = Uri.parse(movie.downloadUrl).path.toLowerCase();
      if (!path.endsWith('.m3u8') && !path.endsWith('.mpd')) {
        options.add({
          'quality': 'Original',
          'video_url': movie.downloadUrl.trim(),
        });
      }
    }

    return VideoQualityService.sort(
      options,
      (item) => item['quality'] ?? 'Original',
    );
  }

  static Future<List<Movie>> getPublishedMovies() async {
    final client = supabaseClient;
    if (client == null) return [];

    try {
      final response = await client
          .from('movies')
          .select()
          .eq('is_published', true)
          .order('created_at', ascending: false);

      return mapPlayableRows(
        client,
        response as List,
        includeWithoutVideo: true,
      );
    } catch (e) {
      debugPrint('Could not load published movies: $e');
      return [];
    }
  }

  static Future<List<Movie>> searchPublishedMovies(String query) async {
    final client = supabaseClient;
    if (client == null || query.trim().isEmpty) return [];

    try {
      final response = await client
          .from('movies')
          .select()
          .eq('is_published', true)
          .ilike('title', '%${query.trim()}%')
          .order('created_at', ascending: false);

      return mapPlayableRows(
        client,
        response as List,
        includeWithoutVideo: true,
      );
    } catch (e) {
      debugPrint('Movie search failed: $e');
      return [];
    }
  }
}

class DownloadTask {
  final int movieId;
  final int downloadId;
  final String title;
  final String poster;
  String videoUrl;
  final String quality;
  Map<String, String> headers;
  final List<Map<String, String>> sourceCandidates;
  int sourceIndex;
  final int? seasonNumber;
  final int? episodeNumber;
  double progress;
  int bytesReceived;
  int totalBytes;
  String status;
  String? filePath;
  String? errorMessage;

  DownloadTask({
    required this.movieId,
    this.downloadId = 0,
    required this.title,
    required this.poster,
    this.videoUrl = '',
    this.quality = 'Original',
    this.headers = const <String, String>{},
    this.sourceCandidates = const <Map<String, String>>[],
    this.sourceIndex = 0,
    this.seasonNumber,
    this.episodeNumber,
    this.progress = 0,
    this.bytesReceived = 0,
    this.totalBytes = 0,
    this.status = 'Waiting',
    this.filePath,
    this.errorMessage,
  });

  String get displayTitle {
    if (seasonNumber == null || episodeNumber == null) return title;
    final season = seasonNumber!.toString().padLeft(2, '0');
    final episode = episodeNumber!.toString().padLeft(2, '0');
    return '$title • S$season E$episode';
  }

  Map<String, dynamic> toJson() => {
        'movieId': movieId,
        'downloadId': downloadId,
        'title': title,
        'poster': poster,
        'videoUrl': videoUrl,
        'quality': quality,
        'headers': headers,
        'sourceCandidates': sourceCandidates,
        'sourceIndex': sourceIndex,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'progress': progress,
        'bytesReceived': bytesReceived,
        'totalBytes': totalBytes,
        'status': status,
        'filePath': filePath,
        'errorMessage': errorMessage,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        movieId: _toInt(json['movieId']),
        downloadId: _toInt(json['downloadId']) > 0
            ? _toInt(json['downloadId'])
            : _toInt(json['movieId']),
        title: (json['title'] ?? 'Downloaded Movie').toString(),
        poster: (json['poster'] ?? '').toString(),
        videoUrl: (json['videoUrl'] ?? '').toString(),
        quality: (json['quality'] ?? 'Original').toString(),
        headers: json['headers'] is Map
            ? Map<String, String>.from(
                (json['headers'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value.toString()),
                ),
              )
            : const <String, String>{},
        sourceCandidates: (json['sourceCandidates'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, String>.from(
                  item.map((key, value) =>
                      MapEntry(key.toString(), value.toString())),
                ))
            .toList(growable: false),
        sourceIndex: _toInt(json['sourceIndex']),
        seasonNumber: _toInt(json['seasonNumber']) > 0
            ? _toInt(json['seasonNumber'])
            : null,
        episodeNumber: _toInt(json['episodeNumber']) > 0
            ? _toInt(json['episodeNumber'])
            : null,
        progress: (json['progress'] as num?)?.toDouble() ?? 1,
        bytesReceived: _toInt(json['bytesReceived']),
        totalBytes: _toInt(json['totalBytes']),
        status: (json['status'] ?? 'Completed').toString(),
        filePath: json['filePath']?.toString(),
        errorMessage: json['errorMessage']?.toString(),
      );
}

class DownloadManager {
  static final Dio _dio = Dio();

  static String formatBytes(int bytes) {
    if (bytes <= 0) return 'Size unavailable';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static Future<int?> getRemoteFileSize(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: {
          ...headers,
          'Accept-Encoding': 'identity',
        }),
      ).timeout(const Duration(seconds: 10));
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (length != null && length > 0) return length;
    } catch (_) {
      // Some file hosts block HEAD requests; try a one-byte range request.
    }

    final token = CancelToken();
    try {
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            ...headers,
            'Range': 'bytes=0-0',
            'Accept-Encoding': 'identity',
          },
        ),
        cancelToken: token,
      ).timeout(const Duration(seconds: 10));
      final contentRange = response.headers.value('content-range') ?? '';
      final totalMatch = RegExp(r'/([0-9]+)$').firstMatch(contentRange);
      final total = int.tryParse(totalMatch?.group(1) ?? '');
      if (total != null && total > 0) return total;
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (response.statusCode == 200 && length != null && length > 0) {
        return length;
      }
    } catch (_) {
      // The size is unavailable when the host hides its content length.
    } finally {
      token.cancel('File size check complete');
    }
    return null;
  }

  static Future<String> partialPath({
    required String url,
    required String fileName,
    required int uniqueId,
  }) =>
      ResumableDownloadService.partialPath(
        url: url,
        fileName: fileName,
        uniqueId: uniqueId,
      );

  static void pause(int uniqueId) =>
      ResumableDownloadService.pause(uniqueId);

  static void cancel(int uniqueId) =>
      ResumableDownloadService.cancel(uniqueId);

  static Future<void> download({
    required String url,
    required String fileName,
    required int uniqueId,
    Map<String, String> headers = const <String, String>{},
    String? existingPartialPath,
    required void Function(int received, int total) onProgress,
    required void Function(String path, int offset) onQueued,
    required void Function(String path, int offset) onStarted,
    required void Function(String path, int received, int total) onPaused,
    required Future<void> Function(String path) onComplete,
    required void Function(String message) onError,
  }) =>
      ResumableDownloadService.download(
        url: url,
        fileName: fileName,
        uniqueId: uniqueId,
        headers: headers,
        existingPartialPath: existingPartialPath,
        onProgress: onProgress,
        onQueued: onQueued,
        onStarted: onStarted,
        onPaused: onPaused,
        onComplete: onComplete,
        onError: onError,
      );
}
// The active Player remains mounted while its floating mini-player is shown.
// This app-level host keeps the video above Home, Search, details and other routes.
final ValueNotifier<_MoviePlayerScreenState?> _activeMiniPlayerState =
    ValueNotifier<_MoviePlayerScreenState?>(null);
Route<void>? _activePlayerRoute;
NavigatorState? _activePlayerNavigator;

// A minimized Player must stay mounted without keeping a modal barrier over
// the app. The empty barrier lets Home, Search and other routes receive taps
// and scroll gestures while the floating mini-player remains visible.
class _NonBlockingPlayerRoute extends PageRouteBuilder<void> {
  _NonBlockingPlayerRoute({required WidgetBuilder pageBuilder})
      : super(
          opaque: false,
          barrierDismissible: false,
          pageBuilder: (routeContext, animation, secondaryAnimation) =>
              pageBuilder(routeContext),
          transitionsBuilder:
              (routeContext, animation, secondaryAnimation, child) =>
                  FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 140),
        );

  @override
  Widget buildModalBarrier() => const SizedBox.shrink();
}

class FlixoraApp extends StatelessWidget {
  const FlixoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flixora',
      theme: ThemeData(
        fontFamily: GoogleFonts.robotoSlab().fontFamily,
        textTheme: GoogleFonts.robotoSlabTextTheme(
          ThemeData.dark().textTheme,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          primary: gold,
          secondary: premiumGold,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: panel,
          indicatorColor: gold.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              color: states.contains(WidgetState.selected)
                  ? gold
                  : ink58,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      builder: (context, child) {
        // Give TV remotes a consistent directional focus traversal root.
        return FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child ?? const SizedBox.shrink(),
              ValueListenableBuilder<_MoviePlayerScreenState?>(
                valueListenable: _activeMiniPlayerState,
                builder: (context, player, _) {
                  if (player == null || !player.mounted || !player._isMiniPlayer) {
                    return const SizedBox.shrink();
                  }
                  return player._buildMiniPlayerOverlay(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CachedHomeSection {
  const _CachedHomeSection({
    required this.deduplicatedMovies,
    required this.filteredByOption,
    required this.filters,
  });

  final List<Movie> deduplicatedMovies;
  final Map<String, List<Movie>> filteredByOption;
  final List<String> filters;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const String _searchHistoryPrefsKey = 'flixora_search_history';
  final PageController _sliderController = PageController();
  final ScrollController _featuredCardsController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _timer;
  Timer? _networkTimer;
  Timer? _searchTimer;
  Timer? _catalogueRefreshTimer;
  int _searchRequestToken = 0;
  bool _homeRefreshQueued = false;
  List<Movie>? _allMoviesCache;
  int? _allMoviesCacheFingerprint;
  List<Movie>? _homeTrendingMoviesCache;
  int? _homeTrendingMoviesCacheFingerprint;
  List<Movie>? _webSeriesTitlesCache;
  int? _webSeriesTitlesCacheFingerprint;
  List<Movie>? _gemsForYouCache;
  int? _gemsForYouCacheFingerprint;
  final Map<String, _CachedHomeSection> _homeSectionCache = {};
  Future<void>? _secondaryCacheLoadFuture;
  DateTime? _lastSecondaryCataloguesRefreshAt;
  DateTime? _lastCatalogVisibilityRefreshAt;
  final Set<String> _unpublishedCatalogKeys = {};
  final Set<String> _checkedCatalogVisibilityKeys = {};
  bool _refreshingCatalogVisibility = false;
  Future<void>? _catalogVisibilityRefreshFuture;
  DateTime? _lastCarouselInteractionAt;
  DateTime? _lastHomeScrollAt;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;

  int _slide = 0;
  int _tab = 0;
  String _librarySection = 'Downloads';
  bool _showRanking = false;
  bool _searchOpen = false;
  String _searchCategory = 'All';
  bool _rankingTv = false;
  String _rankingCategory = 'Cinema';

  String _search = '';
  bool _searchLoading = false;
  String? _searchError;
  List<String> _searchHistory = [];

  bool loading = true;
  bool _online = false;
  bool _connectionKnown = false;
  bool _refreshing = false;
  bool _refreshingSecondaryCatalogues = false;
  bool _backgroundCatalogueWorkRunning = false;
  bool _backgroundCatalogueWorkPending = false;
  int _secondaryCatalogueNextIndex = 0;
  final List<List<Movie>> _secondaryCatalogueResults = <List<Movie>>[];
  DateTime? _lastHomeRefreshAt;
  bool _checkingConnection = false;
  bool _isOpeningTitle = false;
  String? _openingTitleKey;

  String? homeError;

  List<Movie> trending = [];
  List<Movie> _trendingMovies = [];
  List<Movie> _tmdbTrendingMovies = [];
  List<Movie> _tmdbTrendingTv = [];
  List<Movie> _pakistaniTrendingTv = [];
  List<Movie> _chineseTrendingTv = [];
  List<Movie> _koreanTrendingMovies = [];
  List<Movie> _trendingHindiDubbedMovies = [];
  List<Movie> _trendingBollywoodMovies = [];
  List<Movie> _trendingHollywoodMovies = [];
  bool _rankingCataloguesLoading = false;
  bool _refreshingPlayableTrendingMovies = false;
  bool _playableTrendingRefreshQueued = false;
  List<Movie> popular = [];
  List<Movie> latest = [];
  List<Movie> topRated = [];
  List<Movie> trendingTv = [];
  List<Movie> popularTv = [];
  List<Movie> topRatedTv = [];
  List<Movie> anime = [];
  List<Movie> koreanDrama = [];
  List<Movie> bengaliMovies = [];
  List<Movie> bengaliTv = [];
  List<Movie> bollywoodMovies = [];
  List<Movie> hollywoodMovies = [];
  List<Movie> southIndianMovies = [];
  List<Movie> indianDramaTv = [];
  List<Movie> flixoraMovies = [];
  List<Movie> searchResults = [];
  List<MovieBoxHomeSection> _movieBoxSections = [];
  final Map<String, Movie> _movieBoxMatchCache = {};
  final Set<String> _downloadPreparationKeys = <String>{};
  String? _expandedHotShortId;
  final Map<String, List<MovieBoxShortEpisode>> _hotShortEpisodesById = {};
  final Set<String> _hotShortEpisodeLoading = <String>{};
  final Map<String, String> _hotShortEpisodeErrors = {};

  final Set<int> _favourites = {};
  final Set<int> _saved = {};
  final List<Movie> _watchHistory = [];
  final List<DownloadTask> _downloads = [];
  static const MethodChannel _downloadBackgroundChannel =
      MethodChannel('com.flixora.flixora/download_background');
  int _activeBackgroundDownloadTasks = 0;

  Future<bool> _beginBackgroundDownloadTask() async {
    if (!_downloadInBackground) return false;
    _activeBackgroundDownloadTasks++;
    if (_activeBackgroundDownloadTasks == 1) {
      try {
        await _downloadBackgroundChannel.invokeMethod<void>('start');
      } catch (error) {
        debugPrint('Could not start Android download foreground service: $error');
      }
    }
    return true;
  }

  Future<void> _endBackgroundDownloadTask(bool started) async {
    if (!started) return;
    if (_activeBackgroundDownloadTasks > 0) {
      _activeBackgroundDownloadTasks--;
    }
    if (_activeBackgroundDownloadTasks == 0) {
      try {
        await _downloadBackgroundChannel.invokeMethod<void>('stop');
      } catch (error) {
        debugPrint('Could not stop Android download foreground service: $error');
      }
    }
  }
  String? _profileSection;
  final TextEditingController _communityPostController = TextEditingController();
  Future<bool>? _communityProfileFuture;
  String? _communityProfileUserId;
  Future<Map<String, dynamic>>? _communityFeedFuture;
  Future<Map<String, dynamic>>? _communityInboxFuture;
  bool _publishingCommunityPost = false;
  bool _studyMode = false;
  bool _notificationsEnabled = true;
  bool _familyMode = false;
  bool _downloadInBackground = false;
  bool _autoMiniPlayer = true;
  String _appLanguage = 'English';
  String _preferredQuality = 'Auto';

  Set<String> get _flixoraTmdbIds {
    return flixoraMovies
        .where((title) => title.tmdbId > 0)
        .map((title) => '${title.mediaType}:${title.tmdbId}')
        .toSet();
  }

  List<Movie> _withoutFlixoraDuplicates(List<Movie> titles) {
    final adminIds = _flixoraTmdbIds;
    return titles.where((title) {
      if (title.tmdbId <= 0) return true;
      return !adminIds.contains('${title.mediaType}:${title.tmdbId}');
    }).toList();
  }

  String _normalizedMovieTitle(String value) => value
      .toLowerCase()
      // Preserve Bengali and other non-Latin scripts while normalizing
      // common title punctuation and whitespace.
      .replaceAll(RegExp(r'[\s\-_.,:;!?()\[\]{}]+'), ' ')
      .trim();

  String _movieBoxMatchKey(Movie movie) =>
      '${movie.mediaType}:${_normalizedMovieTitle(movie.title)}:${movie.year}';

  List<Movie> _movieBoxSectionItems(MovieBoxHomeSection section) {
    final adminMatches = flixoraMovies.where((admin) {
      return section.items.any((item) {
        if (admin.mediaType != item.mediaType) return false;
        if (admin.tmdbId > 0 && item.tmdbId > 0) {
          return admin.tmdbId == item.tmdbId;
        }
        final yearMatches = admin.year == item.year ||
            admin.year == 'N/A' ||
            item.year == 'N/A';
        return yearMatches &&
            _normalizedMovieTitle(admin.title) ==
                _normalizedMovieTitle(item.title);
      });
    }).toList(growable: false);
    // MovieBox is the canonical source; Admin is appended only as fallback.
    return _deduplicateMovies([...section.items, ...adminMatches]);
  }

  int _catalogVisibilitySourceId(Movie movie) {
    if (!movie.isFlixora) return 0;
    if (movie.sourceId > 0) return movie.sourceId;
    return movie.id < 0 ? -movie.id : 0;
  }

  String _catalogVisibilityKey(Movie movie) {
    final sourceId = _catalogVisibilitySourceId(movie);
    return CatalogSourcePolicy.adminVisibilityKey(
          isAdmin: movie.isFlixora,
          sourceId: sourceId,
        ) ??
        '';
  }

  Map<String, dynamic> _catalogVisibilityPayload(Movie movie) {
    final sourceId = _catalogVisibilitySourceId(movie);
    return {
      'key': _catalogVisibilityKey(movie),
      'source': 'admin',
      'sourceId': sourceId,
    };
  }

  List<Movie> _allCatalogVisibilityCandidates() => [
        ...trending,
        ...popular,
        ...latest,
        ...topRated,
        ...trendingTv,
        ...popularTv,
        ...topRatedTv,
        ...anime,
        ...koreanDrama,
        ...bengaliMovies,
        ...bengaliTv,
        ...flixoraMovies,
        ...searchResults,
        ...bollywoodMovies,
        ...hollywoodMovies,
        ...southIndianMovies,
        ...indianDramaTv,
        ..._trendingMovies,
        ..._tmdbTrendingMovies,
        ..._trendingHindiDubbedMovies,
        ..._movieBoxSections.expand((section) => section.items),
      ];

  Future<void> _refreshCatalogVisibility({
    List<Movie>? candidates,
    bool forceRefresh = false,
  }) async {
    final client = supabaseClient;
    if (client == null || !_online || !mounted) return;

    final isFullRefresh = candidates == null;
    if (isFullRefresh &&
        !forceRefresh &&
        _lastCatalogVisibilityRefreshAt != null &&
        DateTime.now().difference(_lastCatalogVisibilityRefreshAt!) <
            const Duration(minutes: 10)) {
      return;
    }

    final requestedCandidates =
        candidates ?? _allCatalogVisibilityCandidates();
    // Publication visibility belongs only to the exact Admin row. Never send
    // MovieBox or TMDB candidates through the Admin unpublish filter.
    final adminCandidates = CatalogSourcePolicy.adminCandidates<Movie>(
      requestedCandidates,
      isAdmin: (movie) =>
          movie.isFlixora && _catalogVisibilityKey(movie).isNotEmpty,
    );

    if (_refreshingCatalogVisibility) {
      final active = _catalogVisibilityRefreshFuture;
      if (active != null) await active;
      if (!mounted || !_online) return;
      if (isFullRefresh) {
        return _refreshCatalogVisibility(forceRefresh: true);
      }
      final missing = adminCandidates
          .where((movie) => !_checkedCatalogVisibilityKeys
              .contains(_catalogVisibilityKey(movie)))
          .toList(growable: false);
      if (missing.isEmpty) return;
      return _refreshCatalogVisibility(
        candidates: missing,
        forceRefresh: true,
      );
    }

    final source = isFullRefresh
        ? adminCandidates
        : (forceRefresh
            ? adminCandidates
            : adminCandidates.where((movie) => !_checkedCatalogVisibilityKeys
                .contains(_catalogVisibilityKey(movie))));
    final payloadByKey = <String, Map<String, dynamic>>{};
    for (final movie in source) {
      if (movie.title.trim().isEmpty) continue;
      final payload = _catalogVisibilityPayload(movie);
      payloadByKey[payload['key'] as String] = payload;
    }
    if (payloadByKey.isEmpty) return;

    _refreshingCatalogVisibility = true;
    final completer = Completer<void>();
    _catalogVisibilityRefreshFuture = completer.future;
    try {
      final checked = <String>{};
      final blocked = <String>{};
      final payloads = payloadByKey.values.toList(growable: false);
      for (var start = 0; start < payloads.length; start += 200) {
        final batch = payloads.skip(start).take(200).toList(growable: false);
        final blockedBatch = await CatalogVisibilityService.blockedKeys(
          client: client,
          candidates: batch,
        );
        checked.addAll(batch.map((item) => item['key'].toString()));
        blocked.addAll(blockedBatch);
      }

      if (!mounted) return;
      final oldBlocked = Set<String>.from(_unpublishedCatalogKeys);
      if (isFullRefresh) {
        _unpublishedCatalogKeys
          ..clear()
          ..addAll(blocked);
        _checkedCatalogVisibilityKeys
          ..clear()
          ..addAll(checked);
        _lastCatalogVisibilityRefreshAt = DateTime.now();
      } else {
        // A targeted refresh can also recognize an Admin republish and clear
        // an earlier cached unpublished flag for the checked candidates.
        _unpublishedCatalogKeys
          ..removeAll(checked.difference(blocked))
          ..addAll(blocked);
        _checkedCatalogVisibilityKeys.addAll(checked);
      }

      final visibilityChanged = oldBlocked.length != _unpublishedCatalogKeys.length ||
          !oldBlocked.containsAll(_unpublishedCatalogKeys);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'flixora_unpublished_catalog_keys',
        _unpublishedCatalogKeys.toList(growable: false),
      );
      await prefs.setStringList(
        'flixora_checked_catalog_visibility_keys',
        _checkedCatalogVisibilityKeys.toList(growable: false),
      );
      if (visibilityChanged && mounted) {
        setState(() {
          searchResults = _deduplicateMovies(searchResults);
        });
      }
    } catch (error) {
      debugPrint('Admin catalogue visibility check failed: $error');
    } finally {
      _refreshingCatalogVisibility = false;
      if (!completer.isCompleted) completer.complete();
      if (identical(_catalogVisibilityRefreshFuture, completer.future)) {
        _catalogVisibilityRefreshFuture = null;
      }
    }
  }

  Iterable<String> _movieBoxDuplicateKeys(
    Movie movie, {
    required bool forMovieBoxIndex,
  }) sync* {
    final type = movie.mediaType;
    if (movie.tmdbId > 0) {
      yield 'tmdb:' + type + ':' + movie.tmdbId.toString();
    }

    final title = _normalizedMovieTitle(movie.title);
    if (title.isEmpty) return;
    final titleBase = 'title:' + type + ':' + title;
    final year = movie.year.trim();

    if (forMovieBoxIndex) {
      // N/A candidates can match any MovieBox release, as before.
      yield titleBase + ':any';
      yield titleBase + ':year:' + year;
      if (year == 'N/A') yield titleBase + ':unknown';
      return;
    }

    if (year == 'N/A') {
      yield titleBase + ':any';
    } else {
      yield titleBase + ':year:' + year;
      yield titleBase + ':unknown';
    }
  }

  List<Movie> _deduplicateMovies(List<Movie> movies) {
    final seenTmdbIds = <String>{};
    final seenTitleYears = <String>{};
    final seenTitleBasesWithYear = <String>{};
    final seenTitleBasesWithoutYear = <String>{};
    final seenFallbackIds = <String>{};

    final orderedMovies =
        CatalogSourcePolicy.preferMovieBoxDuplicatesByKey<Movie>(
      movies,
      isMovieBox: (movie) => movie.isMovieBox,
      movieBoxKeys: (movie) => _movieBoxDuplicateKeys(
        movie,
        forMovieBoxIndex: true,
      ),
      candidateKeys: (movie) => _movieBoxDuplicateKeys(
        movie,
        forMovieBoxIndex: false,
      ),
    );
    return orderedMovies.where((movie) {
      if (CatalogSourcePolicy.isAdminBlocked(
        isAdmin: movie.isFlixora,
        visibilityKey: _catalogVisibilityKey(movie),
        blockedKeys: _unpublishedCatalogKeys,
      )) {
        return false;
      }
      if (movie.tmdbId > 0 &&
          !seenTmdbIds.add(movie.mediaType + ':' + movie.tmdbId.toString())) {
        return false;
      }

      final normalizedTitle = _normalizedMovieTitle(movie.title);
      final year = movie.year.trim().length >= 4
          ? movie.year.trim().substring(0, 4)
          : '';
      if (normalizedTitle.isNotEmpty) {
        final titleBase = movie.mediaType + ':' + normalizedTitle;
        if (year.isNotEmpty && year != 'N/A') {
          if (seenTitleBasesWithoutYear.contains(titleBase)) return false;
          final titleYearKey = titleBase + ':' + year;
          if (!seenTitleYears.add(titleYearKey)) return false;
          seenTitleBasesWithYear.add(titleBase);
        } else {
          if (seenTitleBasesWithYear.contains(titleBase) ||
              !seenTitleBasesWithoutYear.add(titleBase)) {
            return false;
          }
        }
      }

      if (movie.tmdbId <= 0) {
        final fallbackKey = movie.mediaType + ':' + movie.source + ':' + movie.id.toString();
        return seenFallbackIds.add(fallbackKey);
      }
      return true;
    }).toList(growable: false);
  }

  /// Keep the Home hero and Trending Movies row populated if TMDB's
  /// trending endpoint temporarily returns an empty response. Matching
  /// MovieBox records remain canonical; published Admin rows are fallback.
  MovieBoxHomeSection? get _hotShortsSection {
    for (final section in _movieBoxSections) {
      if (section.isHotShorts && section.items.isNotEmpty) return section;
    }
    return null;
  }

  List<Movie> get _regularMovieBoxItems => _movieBoxSections
      .where((section) => !section.isHotShorts)
      .expand((section) => section.items)
      .toList(growable: false);

  /// Build a mixed hero from Trending Movies plus the strongest TV categories.
  /// Movies and Web Series lead; Drama, Anime and general TV appear regularly.
  List<Movie> _homeTrendingMovies() {
    final fingerprint = _catalogueFingerprint();
    final cached = _homeTrendingMoviesCache;
    if (cached != null && _homeTrendingMoviesCacheFingerprint == fingerprint) {
      return cached;
    }
    List<Movie> preferMovieBoxRecords(Iterable<Movie> titles) {
      return _deduplicateMovies(
        titles
            .map((title) => _cachedMovieBoxMatch(title) ?? title)
            .toList(growable: false),
      );
    }

    final movieBoxTrendingMovies = _movieBoxSections
        .where((section) =>
            !section.isHotShorts &&
            (section.isBanner ||
                section.title.toLowerCase().contains('trending')))
        .expand((section) => section.items)
        .where((title) => title.mediaType == 'movie')
        .toList(growable: false);

    final movieTitles = preferMovieBoxRecords([
      ..._trendingMovies,
      ...movieBoxTrendingMovies,
      ..._tmdbTrendingMovies,
      ...trending.where((title) => title.mediaType == 'movie'),
    ]).where((title) => title.mediaType == 'movie').toList(growable: false);

    final seriesCatalog = preferMovieBoxRecords([
      ..._regularMovieBoxItems.where((title) => title.mediaType == 'tv'),
      ...flixoraMovies.where((title) => title.mediaType == 'tv'),
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...koreanDrama,
      ...bengaliTv,
      ...indianDramaTv,
    ]).where((title) => title.mediaType == 'tv').toList(growable: false);

    final webSeries = preferMovieBoxRecords(_webSeriesTitles())
        .where((title) => title.mediaType == 'tv')
        .take(12)
        .toList(growable: false);
    final webSeriesKeys = webSeries.map(_movieBoxMatchKey).toSet();

    final dramaTitles = seriesCatalog
        .where((title) => title.genres.any(
              (genre) => genre.toLowerCase().contains('drama'),
            ))
        .toList(growable: false);

    final animeTitles = preferMovieBoxRecords([
      ...anime,
      ...seriesCatalog.where(_isAnimeTitle),
    ]);

    final tvShows = seriesCatalog
        .where((title) =>
            !webSeriesKeys.contains(_movieBoxMatchKey(title)) &&
            !_isAnimeTitle(title) &&
            !title.genres.any(
              (genre) => genre.toLowerCase().contains('drama'),
            ))
        .toList(growable: false);

    final result = HeroSliderMixer.mix<Movie>(
      movies: movieTitles,
      webSeries: webSeries,
      dramas: dramaTitles,
      anime: animeTitles,
      tvShows: tvShows,
      keyOf: _movieBoxMatchKey,
      limit: 18,
    ).where((title) =>
        title.backdropUrl.isNotEmpty || title.posterUrl.isNotEmpty)
      .toList(growable: false);
    _homeTrendingMoviesCacheFingerprint = fingerprint;
    _homeTrendingMoviesCache = result;
    return result;
  }

  String _trendingMovieCategory(Movie movie) {
    final id = movie.tmdbId;
    return TrendingMovieEligibility.category(
      originalLanguage: movie.originalLanguage,
      originCountry: movie.originCountry,
      inBollywoodCatalogue: movie.mediaType == 'movie' && id > 0 &&
          bollywoodMovies.any((item) => item.tmdbId == id),
      inHollywoodCatalogue: movie.mediaType == 'movie' && id > 0 &&
          hollywoodMovies.any((item) => item.tmdbId == id),
      inSouthIndianCatalogue: movie.mediaType == 'movie' && id > 0 &&
          southIndianMovies.any((item) => item.tmdbId == id),
      inBengaliCatalogue: movie.mediaType == 'movie' && id > 0 &&
          bengaliMovies.any((item) => item.tmdbId == id),
    );
  }

  List<Movie> _trendingMovieCandidates() {
    final regionalLists = <List<Movie>>[
      _deduplicateMovies(bollywoodMovies),
      _deduplicateMovies(hollywoodMovies),
      _deduplicateMovies(southIndianMovies),
      _deduplicateMovies(bengaliMovies),
    ];
    final regionalFallbacks = <Movie>[];
    final longestRegionalList = regionalLists
        .map((items) => items.length)
        .fold<int>(0, (longest, length) => length > longest ? length : longest);
    for (var index = 0; index < longestRegionalList; index++) {
      for (final region in regionalLists) {
        if (index < region.length) regionalFallbacks.add(region[index]);
      }
    }

    final movieBoxBanners = _movieBoxSections
        .where((section) =>
            !section.isHotShorts &&
            (section.isBanner ||
                section.title.toLowerCase().contains('trending')))
        .expand((section) => section.items)
        .where((movie) => movie.mediaType == 'movie')
        .toList(growable: false);

    return _deduplicateMovies([
      // MovieBox is canonical when the same title exists in both sources.
      ...movieBoxBanners,
      // Mix regional catalogues near the top so global titles cannot fill
      // the entire rail before South Indian, Bengali and other regions appear.
      ..._tmdbTrendingMovies.take(12),
      ...regionalFallbacks,
      ..._tmdbTrendingMovies.skip(12),
      ...popular,
      ...latest,
      ...topRated,
      ...flixoraMovies.where((movie) => movie.mediaType == 'movie'),
    ]).where((movie) =>
        movie.mediaType == 'movie' &&
        (movie.posterUrl.isNotEmpty || movie.backdropUrl.isNotEmpty))
      // Keep enough mixed catalogue entries so regional filters do not
      // look empty when one region dominates the first TMDB results.
      .take(48)
      .toList(growable: false);
  }

  List<Movie> _trendingHomeCandidates() {
    final movieBoxTrendingTv = _movieBoxSections
        .where((section) =>
            !section.isHotShorts &&
            (section.isBanner ||
                section.title.toLowerCase().contains('trending')))
        .expand((section) => section.items)
        .where((title) => title.mediaType == 'tv')
        .toList(growable: false);
    return _deduplicateMovies([
      ..._trendingMovieCandidates(),
      ..._tmdbTrendingTv,
      ...movieBoxTrendingTv,
    ]).where((title) =>
        title.mediaType == 'movie' || title.mediaType == 'tv').toList();
  }

  List<Movie> _pakistaniTrendingDramaTitles() {
    // Use FLIXORA's already-loaded catalogues. MovieBox may omit country
    // metadata, so retain the Pakistani source section label as provenance.
    bool isSeries(Movie title) =>
        title.mediaType == 'tv' ||
        title.movieBoxIsSeries ||
        const {2, 3, 7}.contains(title.movieBoxSubjectType);

    final pakistaniSectionItems = _movieBoxSections
        .where((section) {
          final sectionName = section.title.toLowerCase();
          return sectionName.contains('pakistani') ||
              sectionName.contains('pakistan');
        })
        .expand((section) => section.items)
        .where(isSeries)
        .toList(growable: false);

    final pakistaniSectionIds = pakistaniSectionItems
        .where((title) => title.tmdbId > 0)
        .map((title) => title.tmdbId)
        .toSet();
    final pakistaniSectionTitles = pakistaniSectionItems
        .map((title) => _normalizedMovieTitle(title.title))
        .where((title) => title.isNotEmpty)
        .toSet();

    // MovieBox records stay first so their playable source remains canonical.
    final candidates = _deduplicateMovies([
      ...pakistaniSectionItems,
      ..._regularMovieBoxItems.where(isSeries),
      ...flixoraMovies.where((title) => title.mediaType == 'tv'),
      ..._pakistaniTrendingTv,
      ..._tmdbTrendingTv,
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...koreanDrama,
      ...bengaliTv,
      ...indianDramaTv,
    ]);

    final pakistaniFeedIds = _pakistaniTrendingTv
        .where((title) => title.tmdbId > 0)
        .map((title) => title.tmdbId)
        .toSet();
    final pakistaniFeedTitles = _pakistaniTrendingTv
        .map((title) => _normalizedMovieTitle(title.title))
        .where((title) => title.isNotEmpty)
        .toSet();

    return candidates.where((title) {
      if (!isSeries(title)) return false;

      final country = title.originCountry.toUpperCase();
      final countryCodes = country.split(RegExp(r'[,\s]+'));
      final hasPakistaniCountry = country == 'PK' ||
          country.contains('PAKISTAN') ||
          countryCodes.contains('PK') ||
          title.originalLanguage.toLowerCase() == 'ur';
      final normalizedTitle = _normalizedMovieTitle(title.title);
      final isFromPakistaniSection =
          (title.tmdbId > 0 && pakistaniSectionIds.contains(title.tmdbId)) ||
          (normalizedTitle.isNotEmpty &&
              pakistaniSectionTitles.contains(normalizedTitle));
      final isFromPakistaniFeed =
          (title.tmdbId > 0 && pakistaniFeedIds.contains(title.tmdbId)) ||
          (normalizedTitle.isNotEmpty &&
              pakistaniFeedTitles.contains(normalizedTitle));
      final hasDramaGenre = title.genres.any(
        (genre) => genre.toLowerCase().contains('drama'),
      );

      // Keep existing Pakistani catalogue entries when MovieBox omits genre
      // metadata, but never include an explicitly non-drama title.
      final genreAllowsDrama = hasDramaGenre || title.genres.isEmpty;
      return genreAllowsDrama &&
          (hasPakistaniCountry ||
              isFromPakistaniSection ||
              isFromPakistaniFeed);
    }).toList(growable: false);
  }

  List<Movie> _chineseDramaTitles() {
    bool isSeries(Movie title) =>
        title.mediaType == 'tv' ||
        title.movieBoxIsSeries ||
        const {2, 3, 7}.contains(title.movieBoxSubjectType);

    final chineseSectionItems = _movieBoxSections
        .where((section) {
          final name = section.title.toLowerCase();
          return name.contains('chinese') ||
              name.contains('china') ||
              name.contains('c-drama') ||
              name.contains('cdrama');
        })
        .expand((section) => section.items)
        .where(isSeries)
        .toList(growable: false);

    final candidates = _deduplicateMovies([
      ...chineseSectionItems,
      ..._regularMovieBoxItems.where(isSeries),
      ...flixoraMovies.where((title) => title.mediaType == 'tv'),
      ..._chineseTrendingTv,
      ..._tmdbTrendingTv,
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...koreanDrama,
      ...bengaliTv,
      ...indianDramaTv,
    ]);

    final sectionIds = chineseSectionItems
        .where((title) => title.tmdbId > 0)
        .map((title) => title.tmdbId)
        .toSet();
    final sectionTitles = chineseSectionItems
        .map((title) => _normalizedMovieTitle(title.title))
        .where((title) => title.isNotEmpty)
        .toSet();

    return candidates.where((title) {
      if (!isSeries(title)) return false;
      final country = title.originCountry.toUpperCase();
      final countryCodes = country.split(RegExp(r'[,\\s]+'));
      final isChinese = country == 'CN' ||
          country.contains('CHINA') ||
          countryCodes.contains('CN') ||
          countryCodes.contains('CHN') ||
          title.originalLanguage.toLowerCase().startsWith('zh');
      final normalizedTitle = _normalizedMovieTitle(title.title);
      final fromChineseSection =
          (title.tmdbId > 0 && sectionIds.contains(title.tmdbId)) ||
          (normalizedTitle.isNotEmpty && sectionTitles.contains(normalizedTitle));
      final hasDramaGenre = title.genres.any(
        (genre) => genre.toLowerCase().contains('drama'),
      );
      final genreAllowsDrama = hasDramaGenre || title.genres.isEmpty;
      return genreAllowsDrama && (isChinese || fromChineseSection);
    }).toList(growable: false);
  }

  Future<void> _refreshChineseDramaCatalogue({
    bool forceRefresh = false,
  }) async {
    if (!_online) return;
    try {
      var titles = await TmdbService.getMovies(
        'discover/tv',
        extraParams: {
          'with_origin_country': 'CN',
          'with_genres': '18',
          'sort_by': 'popularity.desc',
        },
        pages: 5,
        forceRefresh: forceRefresh,
      ).timeout(const Duration(seconds: 40));

      if (titles.isEmpty) {
        titles = await TmdbService.getMovies(
          'discover/tv',
          extraParams: {
            'with_origin_country': 'CN',
            'sort_by': 'popularity.desc',
          },
          pages: 5,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 40));
      }
      if (!mounted || titles.isEmpty) return;
      setState(() {
        _chineseTrendingTv = _deduplicateMovies([
          ..._chineseTrendingTv,
          ...titles,
        ]);
      });
    } catch (error) {
      debugPrint('Chinese drama catalogue refresh failed: $error');
    }
  }

  Widget _pakistaniDramaBlock() {
    final dramas = _pakistaniTrendingDramaTitles();
    if (dramas.isNotEmpty) return _sectionBlock('Pakistani Drama', dramas);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 21, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pakistani Drama',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(
            height: 44,
            child: Center(
              child: Text(
                'No trending Pakistani dramas right now.',
                style: TextStyle(color: ink54, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _movieBoxPlayableAudioLanguages(Movie movie) async {
    final result = await MovieBoxService.prewarmStreams(
      movie.toMovieBoxMap(),
      isSeries: false,
    ).timeout(const Duration(seconds: 6));
    if (result == null || !MovieBoxStreamPolicy.hasPlayableLinks(result)) {
      return <String>[];
    }

    final links = result['links'] as List? ?? const [];
    final languages = <String>[];
    for (final rawLink in links.whereType<Map>()) {
      final label = (rawLink['label'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      final language = label.split('·').first.trim();
      final isQualityOnly = RegExp(r'^\d{3,4}p$', caseSensitive: false)
          .hasMatch(language);
      if (!isQualityOnly &&
          !language.toLowerCase().contains('subtitle') &&
          !languages.contains(language)) {
        languages.add(language);
      }
    }
    if (languages.isEmpty) languages.add('Original');
    return languages;
  }

  Future<MapEntry<String, Movie>?> _verifyPlayableTrendingMovie(
    Movie candidate,
  ) async {
    final category = _trendingMovieCategory(candidate);

    // A matching MovieBox title always wins, even when its Admin duplicate
    // has been unpublished. Only look at Admin after MovieBox has no match.
    final movieBoxMatch = _cachedMovieBoxMatch(candidate) ??
        await _searchMovieBoxMatch(candidate);
    if (movieBoxMatch != null) {
      if (!movieBoxMatch.isMovieBox || movieBoxMatch.movieBoxIsSeries) {
        return null;
      }

      final audioLanguages =
          await _movieBoxPlayableAudioLanguages(movieBoxMatch);
      if (audioLanguages.isNotEmpty) {
        final verifiedMovie = Movie.fromCache({
          ...movieBoxMatch.toJson(),
          'audioLanguages': audioLanguages,
        });
        return MapEntry(category, verifiedMovie);
      }
      // A matching MovieBox title remains canonical even if its current
      // stream is unavailable. Do not replace it with an Admin duplicate.
      return null;
    }

    final adminMatch = _cachedFlixoraMatch(candidate) ??
        (candidate.isFlixora &&
                !CatalogSourcePolicy.isAdminBlocked(
                  isAdmin: true,
                  visibilityKey: _catalogVisibilityKey(candidate),
                  blockedKeys: _unpublishedCatalogKeys,
                )
            ? candidate
            : null);
    if (adminMatch != null && adminMatch.hasPlayableVideoUrl) {
      return MapEntry(category, adminMatch);
    }

    if (!candidate.isFlixora && candidate.hasPlayableVideoUrl) {
      return MapEntry(category, candidate);
    }
    return null;
  }

  Future<void> _refreshPlayableTrendingMovies() async {
    if (!_online) return;
    if (_refreshingPlayableTrendingMovies) {
      _playableTrendingRefreshQueued = true;
      return;
    }
    final candidates = _trendingMovieCandidates().take(8).toList(growable: false);
    if (candidates.isEmpty) return;

    _refreshingPlayableTrendingMovies = true;
    try {
      // Admin visibility is checked once by the background coordinator.
      final verifiedAll = <Movie>[];
      for (var start = 0;
          start < candidates.length && verifiedAll.length < 8;
          start += 2) {
        if (!_canRunBackgroundCatalogueWork) {
          _backgroundCatalogueWorkPending = true;
          break;
        }
        final batch = candidates.skip(start).take(2);
        final resolved = await Future.wait<MapEntry<String, Movie>?>(
          batch.map(_verifyPlayableTrendingMovie),
        );

        for (final entry in resolved.whereType<MapEntry<String, Movie>>()) {
          if (verifiedAll.length >= 16) break;
          verifiedAll.add(entry.value);
        }
      }

      final verified = _deduplicateMovies(verifiedAll)
          .take(8)
          .toList(growable: false);
      final verifiedHindi = verified.where(_hasHindiAudio).toList();
      final verifiedBollywood = verified
          .where((movie) => _trendingMovieCategory(movie) == 'Bollywood')
          .toList();
      final verifiedHollywood = verified
          .where((movie) => _trendingMovieCategory(movie) == 'Hollywood')
          .toList();

      if (!mounted) return;
      setState(() {
        _trendingMovies = verified;
        _trendingHindiDubbedMovies = verifiedHindi;
        _trendingBollywoodMovies = verifiedBollywood;
        _trendingHollywoodMovies = verifiedHollywood;
      });
      await Future.wait([
        MovieCache.saveList(
          MovieCache.playableTrendingMoviesKey,
          _trendingMovies,
        ),
        MovieCache.saveList(
          MovieCache.trendingHindiDubbedKey,
          _trendingHindiDubbedMovies,
        ),
        MovieCache.saveList(
          MovieCache.trendingBollywoodKey,
          _trendingBollywoodMovies,
        ),
        MovieCache.saveList(
          MovieCache.trendingHollywoodKey,
          _trendingHollywoodMovies,
        ),
      ]);
    } catch (error) {
      debugPrint('Could not refresh playable Trending Movies: $error');
    } finally {
      _refreshingPlayableTrendingMovies = false;
      if (_playableTrendingRefreshQueued && mounted && _online) {
        _playableTrendingRefreshQueued = false;
        unawaited(_refreshPlayableTrendingMovies());
      }
    }
  }

  bool _isAnimeTitle(Movie title) {
    final genres = title.genres.map((genre) => genre.toLowerCase()).toSet();
    final country = title.originCountry.toLowerCase();
    return genres.contains('anime') ||
        (genres.contains('animation') &&
            (title.originalLanguage.toLowerCase() == 'ja' ||
                country == 'jp' ||
                country.contains('japan')));
  }

  /// TMDB does not define "Web Series" as a TV genre. Prefer titles explicitly
  /// tagged by FLIXORA Admin; if none exist yet, show the available non-anime
  /// TV catalogue instead of leaving the Home section blank.
  List<Movie> _webSeriesTitles() {
    final fingerprint = _catalogueFingerprint();
    final cached = _webSeriesTitlesCache;
    if (cached != null && _webSeriesTitlesCacheFingerprint == fingerprint) {
      return cached;
    }

    final catalogue = _deduplicateMovies([
      ..._regularMovieBoxItems.where((title) => title.mediaType == 'tv'),
      ...flixoraMovies.where((title) => title.mediaType == 'tv'),
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...koreanDrama,
      ...bengaliTv,
      ...indianDramaTv,
    ].where((title) => title.mediaType == 'tv').toList());

    final tagged = catalogue.where((title) => title.genres.any((genre) {
      final normalized = genre.toLowerCase().replaceAll('-', ' ').trim();
      return normalized == 'web series' || normalized == 'webseries';
    })).toList(growable: false);

    final result = tagged.isNotEmpty
        ? tagged
        : (catalogue.where((title) => !_isAnimeTitle(title)).toList()
          ..sort((a, b) => b.rating.compareTo(a.rating)));
    _webSeriesTitlesCacheFingerprint = fingerprint;
    _webSeriesTitlesCache = result;
    return result;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final authClient = supabaseClient;
    if (authClient != null) {
      _authSubscription = authClient.auth.onAuthStateChange.listen(
        (_) {
          if (mounted) setState(() {});
        },
        onError: (error, stackTrace) {
          debugPrint('Auth state listener error: $error');
        },
      );
    }

    _initializeApp();
    _listenToConnectivity();
    _networkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshConnectionStatus(),
    );
    _catalogueRefreshTimer = Timer.periodic(
      const Duration(minutes: 20),
      (_) {
        if (!mounted ||
            !_online ||
            _tab != 0 ||
            _searchOpen ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }
        unawaited(loadHome(forceRefresh: true));
      },
    );

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        final lastInteraction = _lastCarouselInteractionAt;
        if (!mounted ||
            _tab != 0 ||
            _isOpeningTitle ||
            (lastInteraction != null &&
                DateTime.now().difference(lastInteraction) <
                    const Duration(seconds: 8)) ||
            (_lastHomeScrollAt != null &&
                DateTime.now().difference(_lastHomeScrollAt!) <
                    const Duration(seconds: 6)) ||
            !(ModalRoute.of(context)?.isCurrent ?? true)) {
          return;
        }

        final visibleCount = _homeTrendingMovies().length;

        if (visibleCount == 0) return;

        _slide = (_slide + 1) % visibleCount;

        if (_sliderController.hasClients) {
          _sliderController.animateToPage(
            _slide,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
          );
        }
      },
    );
  }

  Future<void> _initializeApp() async {
    try {
      // Start the reachability probe and small preference reads while the
      // essential cached Home catalogue is being restored.
      final onlineFuture = InternetService.isOnline();
      final savedHistoryFuture = MovieCache.getList(MovieCache.historyKey);
      final prefsFuture = SharedPreferences.getInstance();
      unawaited(_loadSavedPreferences().catchError((_) {}));
      unawaited(_loadAppSettings());

      await _loadCachedMovies();
      if (!mounted) return;

      final savedDownloadsFuture = MovieCache.getDownloads();
      final savedHistory = await savedHistoryFuture;
      final prefs = await prefsFuture;
      final savedSearchHistory =
          prefs.getStringList(_searchHistoryPrefsKey) ?? const <String>[];
      // Publication state is scoped to the exact Admin row, never a MovieBox
      // duplicate that happens to share its TMDB ID or title/year.
      _unpublishedCatalogKeys
        ..clear()
        ..addAll(
          (prefs.getStringList('flixora_unpublished_catalog_keys') ?? const [])
              .where((key) => key.startsWith('admin:id:')),
        );
      _checkedCatalogVisibilityKeys
        ..clear()
        ..addAll(
          (prefs.getStringList('flixora_checked_catalog_visibility_keys') ?? const [])
              .where((key) => key.startsWith('admin:id:')),
        );
      final savedStudyMode = prefs.getBool('flixora_study_mode') ?? false;
      if (mounted) {
        setState(() {
          _watchHistory
            ..clear()
            ..addAll(savedHistory);
          _searchHistory
            ..clear()
            ..addAll(
              savedSearchHistory
                  .map((query) => query.trim())
                  .where((query) => query.isNotEmpty)
                  .take(20),
            );
          _studyMode = savedStudyMode;
        });
      }

      // Download verification can scan many files, so it stays off the first
      // Home frame and fills the Library in the background.
      unawaited(savedDownloadsFuture.then((savedDownloads) {
        if (!mounted) return;
        setState(() {
          _downloads
            ..clear()
            ..addAll(savedDownloads);
        });
      }).catchError((_) {}));

      final online = await onlineFuture;
      if (!mounted) return;
      setState(() {
        _online = online;
        _connectionKnown = true;
      });

      if (online) {
        await loadHome();
      } else {
        // If the essential cache is empty, let the smaller secondary cache
        // finish before showing the offline state.
        if (_allMovies().isEmpty) await _loadSecondaryCachedMovies();
        if (!mounted) return;
        setState(() {
          loading = false;
          homeError = _allMovies().isEmpty ? 'offline' : null;
        });
      }
    } catch (error) {
      debugPrint('FLIXORA startup failed: $error');
      if (!mounted) return;
      setState(() {
        loading = false;
        _connectionKnown = true;
        if (_allMovies().isEmpty) {
          homeError = _online
              ? 'Unable to load movies. Pull down to retry.'
              : 'offline';
        }
      });
    }
  }

  Future<void> _loadAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = prefs.getBool('flixora_notifications') ?? true;
        _familyMode = prefs.getBool('flixora_family_mode') ?? false;
        _downloadInBackground = prefs.getBool('flixora_download_background') ?? true;
        _autoMiniPlayer = prefs.getBool('flixora_auto_miniplayer') ?? true;
        _appLanguage = prefs.getString('flixora_language') ?? 'English';
        _preferredQuality = prefs.getString('flixora_preferred_quality') ?? 'Auto';
      });
    } catch (_) {}
  }

  Future<void> _saveBoolSetting(String key, bool value, void Function(bool) update) async {
    if (key == 'flixora_notifications') {
      var enabled = value;
      if (value) {
        enabled = await FlixoraNotificationService.enable();
        if (!enabled && mounted) {
          _showMessage('Allow notifications in Android Settings to receive FLIXORA updates.');
        }
      } else {
        await FlixoraNotificationService.disable();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, enabled);
      if (mounted) setState(() => update(enabled));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (mounted) setState(() => update(value));
  }

  Future<void> _showLanguagePicker() async {
    const languages = ['English', 'বাংলা', 'हिन्दी'];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: panel,
        title: const Text('Select language', style: TextStyle(color: white)),
        children: languages.map((language) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, language),
          child: Row(children: [
            Expanded(child: Text(language, style: const TextStyle(color: white))),
            if (_appLanguage == language) const Icon(Icons.check, color: gold),
          ]),
        )).toList(),
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flixora_language', selected);
    if (mounted) setState(() => _appLanguage = selected);
    _showMessage('Language preference saved. Full app translation will be added separately.');
  }

  Future<void> _showWatchOptions() async {
    const qualities = ['Auto', '360p', '480p', '720p', '1080p'];
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: panel,
        title: const Text('Watch Options', style: TextStyle(color: white)),
        children: [
          RadioGroup<String>(
            groupValue: _preferredQuality,
            onChanged: (value) {
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: qualities.map((quality) => RadioListTile<String>(
                value: quality,
                activeColor: gold,
                title: Text(quality, style: const TextStyle(color: white)),
              )).toList(),
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('flixora_preferred_quality', selected);
    if (mounted) setState(() => _preferredQuality = selected);
  }

  void _showSettingsInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text(title, style: const TextStyle(color: white)),
        content: Text(message, style: const TextStyle(color: ink70, height: 1.45)),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _loadSavedPreferences() async {
    final results = await Future.wait<Set<int>>([
      MovieCache.getFavourites(),
      MovieCache.getSaved(),
    ]);

    if (!mounted) return;

    setState(() {
      _favourites
        ..clear()
        ..addAll(results[0]);

      _saved
        ..clear()
        ..addAll(results[1]);
    });
  }

  Future<void> _loadCachedMovies() async {
    final cachedMovieBoxSectionsFuture = MovieCache.getMovieBoxSections();
    final cachedTrendingDataFuture = Future.wait<List<Movie>>([
      MovieCache.getList(MovieCache.playableTrendingMoviesKey),
      MovieCache.getList(MovieCache.tmdbTrendingMoviesKey),
    ]);
    // Load the first-screen essentials first. Regional catalogues and less
    // frequently used categories are restored after Home is already visible.
    final results = await Future.wait<List<Movie>>([
      MovieCache.getList(MovieCache.trendingKey),
      MovieCache.getList(MovieCache.popularKey),
      MovieCache.getList(MovieCache.latestKey),
      MovieCache.getList(MovieCache.topRatedKey),
      MovieCache.getList(MovieCache.trendingTvKey),
      MovieCache.getList(MovieCache.popularTvKey),
      MovieCache.getList(MovieCache.topRatedTvKey),
      MovieCache.getList(MovieCache.animeKey),
      MovieCache.getList(MovieCache.flixoraKey),
    ]);

    final cachedMovieBoxSections = (await cachedMovieBoxSectionsFuture)
        .where((section) => !section.isFlixoraOriginal)
        .toList(growable: false);
    final cachedTrendingData = await cachedTrendingDataFuture;
    if (!mounted) return;

    setState(() {
      _movieBoxSections = cachedMovieBoxSections;
      _trendingMovies = cachedTrendingData[0];
      _tmdbTrendingMovies = cachedTrendingData[1];
      trending = results[0];
      popular = results[1];
      latest = results[2];
      topRated = results[3];
      trendingTv = results[4];
      popularTv = results[5];
      topRatedTv = results[6];
      anime = results[7];
      flixoraMovies = results[8];
      loading = false;
      homeError = null;
    });

    // The remaining cached categories no longer block the first Home render.
    unawaited(_loadSecondaryCachedMovies());
  }

  Future<void> _loadSecondaryCachedMovies() {
    return _secondaryCacheLoadFuture ??= _loadSecondaryCachedMoviesInternal();
  }

  Future<void> _loadSecondaryCachedMoviesInternal() async {
    try {
      final results = await Future.wait<List<Movie>>([
        MovieCache.getList(MovieCache.koreanKey),
        MovieCache.getList(MovieCache.bengaliMoviesKey),
        MovieCache.getList(MovieCache.bengaliTvKey),
        MovieCache.getList(MovieCache.bollywoodMoviesKey),
        MovieCache.getList(MovieCache.hollywoodMoviesKey),
        MovieCache.getList(MovieCache.southIndianMoviesKey),
        MovieCache.getList(MovieCache.indianDramaTvKey),
        MovieCache.getList(MovieCache.trendingHindiDubbedKey),
        MovieCache.getList(MovieCache.trendingBollywoodKey),
        MovieCache.getList(MovieCache.trendingHollywoodKey),
        MovieCache.getList(MovieCache.tmdbTrendingTvKey),
        MovieCache.getList(MovieCache.pakistaniTrendingTvKey),
        MovieCache.getList(MovieCache.koreanTrendingMoviesKey),
      ]);
      if (!mounted) return;

      setState(() {
        if (koreanDrama.isEmpty) koreanDrama = results[0];
        if (bengaliMovies.isEmpty) bengaliMovies = results[1];
        if (bengaliTv.isEmpty) bengaliTv = results[2];
        if (bollywoodMovies.isEmpty) bollywoodMovies = results[3];
        if (hollywoodMovies.isEmpty) hollywoodMovies = results[4];
        if (southIndianMovies.isEmpty) southIndianMovies = results[5];
        if (indianDramaTv.isEmpty) indianDramaTv = results[6];
        if (_trendingHindiDubbedMovies.isEmpty) {
          _trendingHindiDubbedMovies = results[7];
        }
        if (_trendingBollywoodMovies.isEmpty) {
          _trendingBollywoodMovies = results[8];
        }
        if (_trendingHollywoodMovies.isEmpty) {
          _trendingHollywoodMovies = results[9];
        }
        if (_tmdbTrendingTv.isEmpty) {
          _tmdbTrendingTv = results[10];
        }
        if (_pakistaniTrendingTv.isEmpty) {
          _pakistaniTrendingTv = results[11];
        }
        if (_koreanTrendingMovies.isEmpty) {
          _koreanTrendingMovies = results[12];
        }
        if (_trendingMovies.isEmpty) {
          _trendingMovies = _deduplicateMovies([
            ...results[7],
            ...results[8],
            ...results[9],
          ]);
        }
        if (_allMovies().isNotEmpty) {
          loading = false;
          homeError = null;
        }
      });
      _syncFeaturedCarouselAfterDataChange();
    } catch (error) {
      debugPrint('Secondary cached catalogue restore failed: $error');
    }
  }

  void _listenToConnectivity() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen(
      (_) async {
        InternetService.invalidateCache();
        // Connectivity events can briefly report "none" during Wi-Fi/mobile
        // hand-offs. Confirm real internet reachability before showing Offline.
        final online = await InternetService.isOnline(forceRefresh: true);

        if (!mounted) return;

        if (online == _online && _connectionKnown) return;
        final wasOffline = !_online;

        setState(() {
          _online = online;
          _connectionKnown = true;
        });

        if (online && wasOffline) {
          await loadHome(forceRefresh: true);

          if (_search.trim().isNotEmpty) {
            unawaited(searchMovies(_search));
          }
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshConnectionStatus();
      final lastRefresh = _lastHomeRefreshAt;
      if (lastRefresh == null ||
          DateTime.now().difference(lastRefresh) >=
              const Duration(minutes: 15)) {
        // Refresh MovieBox home and current releases when the app returns
        // after a while, without polling while the user is actively watching.
        unawaited(loadHome(forceRefresh: true));
      }
    }
  }

  Future<void> _refreshConnectionStatus() async {
    if (!mounted || _checkingConnection) return;
    _checkingConnection = true;
    try {
      final online = await InternetService.isOnline(forceRefresh: true);
      if (!mounted) return;
      if (online == _online) {
        if (_backgroundCatalogueWorkPending &&
            _canRunBackgroundCatalogueWork) {
          unawaited(_runBackgroundCatalogueWork());
        }
        return;
      }

      final wasOffline = !_online;
      setState(() {
        _online = online;
        _connectionKnown = true;
        if (!online && _allMovies().isEmpty) homeError = 'offline';
      });

      if (online && wasOffline) {
        await loadHome(forceRefresh: true);
        if (_search.trim().isNotEmpty) {
          unawaited(searchMovies(_search));
        }
      }
    } finally {
      _checkingConnection = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _networkTimer?.cancel();
    _catalogueRefreshTimer?.cancel();
    _searchTimer?.cancel();
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _sliderController.dispose();
    _featuredCardsController.dispose();
    _searchController.dispose();
    _communityPostController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  bool get _canRunBackgroundCatalogueWork {
    if (!mounted ||
        !_online ||
        _tab != 0 ||
        _searchOpen ||
        _showRanking ||
        _isOpeningTitle) {
      return false;
    }
    final now = DateTime.now();
    if (_lastHomeScrollAt != null &&
        now.difference(_lastHomeScrollAt!) < const Duration(seconds: 6)) {
      return false;
    }
    if (_lastCarouselInteractionAt != null &&
        now.difference(_lastCarouselInteractionAt!) <
            const Duration(seconds: 8)) {
      return false;
    }
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  Future<void> _runBackgroundCatalogueWork({
    bool forceRefresh = false,
  }) async {
    if (_backgroundCatalogueWorkRunning) {
      _backgroundCatalogueWorkPending = true;
      return;
    }
    _backgroundCatalogueWorkRunning = true;
    _backgroundCatalogueWorkPending = false;
    try {
      // Let the first Home frame and immediate user interaction take priority.
      await Future.delayed(const Duration(seconds: 5));
      if (!_canRunBackgroundCatalogueWork) {
        _backgroundCatalogueWorkPending = true;
        return;
      }

      await _refreshCatalogVisibility(forceRefresh: true);
      if (!_canRunBackgroundCatalogueWork) {
        _backgroundCatalogueWorkPending = true;
        return;
      }

      await _refreshSecondaryCatalogues(forceRefresh: forceRefresh);
      if (!_canRunBackgroundCatalogueWork) {
        _backgroundCatalogueWorkPending = true;
        return;
      }

      await _refreshPlayableTrendingMovies();
      if (!_canRunBackgroundCatalogueWork ||
          _secondaryCatalogueNextIndex > 0) {
        _backgroundCatalogueWorkPending = true;
      }
    } catch (error) {
      _backgroundCatalogueWorkPending = true;
      debugPrint('Background catalogue coordinator failed: $error');
    } finally {
      _backgroundCatalogueWorkRunning = false;
      if (_backgroundCatalogueWorkPending &&
          _canRunBackgroundCatalogueWork) {
        unawaited(_runBackgroundCatalogueWork());
      }
    }
  }

  Future<void> _refreshPakistaniDramaCatalogue({
    bool forceRefresh = false,
  }) async {
    if (!_online) return;
    try {
      var titles = await TmdbService.getMovies(
        'discover/tv',
        extraParams: {
          'with_origin_country': 'PK',
          'with_genres': '18',
          'sort_by': 'popularity.desc',
        },
        pages: 3,
        forceRefresh: forceRefresh,
      ).timeout(const Duration(seconds: 35));

      // If the strict genre query returns no rows, broaden only the Pakistani
      // TV discovery request; the section selector still filters drama genre.
      if (titles.isEmpty) {
        titles = await TmdbService.getMovies(
          'discover/tv',
          extraParams: {
            'with_origin_country': 'PK',
            'sort_by': 'popularity.desc',
          },
          pages: 3,
          forceRefresh: forceRefresh,
        ).timeout(const Duration(seconds: 35));
      }
      if (!mounted || titles.isEmpty) return;
      setState(() {
        _pakistaniTrendingTv = _deduplicateMovies([
          ..._pakistaniTrendingTv,
          ...titles,
        ]);
      });
      await MovieCache.saveList(
        MovieCache.pakistaniTrendingTvKey,
        _pakistaniTrendingTv,
      );
    } catch (error) {
      debugPrint('Pakistani drama catalogue refresh failed: $error');
    }
  }

  Future<void> _refreshMovieBoxHome({bool forceRefresh = false}) async {
    if (!_online) return;
    try {
      try {
        await MovieBoxService.enableSafeContentFilter();
      } catch (error) {
        debugPrint('MovieBox safe-content filter setup failed: $error');
      }
      final rawSections = await MovieBoxService.home(forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 15));
      final sections = rawSections
          .map(MovieBoxHomeSection.fromApi)
          .where((section) =>
              section.items.isNotEmpty && !section.isFlixoraOriginal)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _movieBoxSections = sections;
        if (_allMovies().isNotEmpty) {
          loading = false;
          homeError = null;
        }
      });
      for (final item in sections.expand((section) => section.items)) {
        _movieBoxMatchCache[_movieBoxMatchKey(item)] = item;
      }
      await MovieCache.saveMovieBoxSections(sections);
      unawaited(_refreshCatalogVisibility(
        candidates: sections.expand((section) => section.items).toList(),
        forceRefresh: true,
      ));
    } catch (error) {
      debugPrint('MovieBox/WeFeed home feed unavailable: $error');
    }
  }

  Future<void> _refreshSecondaryCatalogues({bool forceRefresh = false}) async {
    if (_refreshingSecondaryCatalogues || !_online) return;
    final lastRefresh = _lastSecondaryCataloguesRefreshAt;
    if (!forceRefresh &&
        _secondaryCatalogueNextIndex == 0 &&
        lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(minutes: 15)) {
      return;
    }
    _refreshingSecondaryCatalogues = true;
    try {
      final loaders = <Future<List<Movie>> Function()>[
        // TV and ongoing releases are loaded after the first movie rows appear.
        () => TmdbService.getMovies('trending/tv/week', forceRefresh: forceRefresh)
            .catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('tv/popular', forceRefresh: forceRefresh)
            .catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('tv/top_rated', forceRefresh: forceRefresh)
            .catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('tv/on_the_air', forceRefresh: forceRefresh)
            .catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('tv/airing_today', forceRefresh: forceRefresh)
            .catchError((_) => <Movie>[]),

        // Fetch pages 2-3 without downloading page 1 again.
        () => TmdbService.getMovies(
          'trending/movie/week', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'movie/popular', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'movie/now_playing', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'movie/top_rated', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'trending/tv/week', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'tv/popular', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies(
          'tv/top_rated', pages: 2, startPage: 2,
          forceRefresh: forceRefresh,
        ).catchError((_) => <Movie>[]),

        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_genres': '16',
          'with_origin_country': 'JP',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'ko',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'bn',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'bn',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'hi',
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'en',
          'with_origin_country': 'US',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ta',
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'te',
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ml',
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'kn',
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'ja',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'zh',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_original_language': 'th',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'hi',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/tv', extraParams: {
          'with_origin_country': 'PK',
          'with_genres': '18',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
        () => TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ko',
          'with_origin_country': 'KR',
          'sort_by': 'popularity.desc',
        }, forceRefresh: forceRefresh).catchError((_) => <Movie>[]),
      ];

      if (_secondaryCatalogueResults.length != loaders.length) {
        _secondaryCatalogueResults
          ..clear()
          ..addAll(List<List<Movie>>.generate(
            loaders.length,
            (_) => <Movie>[],
          ));
      }
      final results = _secondaryCatalogueResults;
      var completedAll = true;
      // Keep the background workload small and pause between batches whenever
      // the user starts scrolling, searching, changing tabs or opening a title.
      for (var start = _secondaryCatalogueNextIndex;
          start < loaders.length;
          start += 2) {
        if (!_canRunBackgroundCatalogueWork) {
          completedAll = false;
          break;
        }
        final batch = await Future.wait<List<Movie>>(
          loaders.skip(start).take(2).map((load) => load()),
        );
        for (var offset = 0; offset < batch.length; offset++) {
          results[start + offset] = batch[offset];
        }
        _secondaryCatalogueNextIndex = start + batch.length;
        if (_secondaryCatalogueNextIndex < loaders.length) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      if (!mounted) return;
      setState(() {
        _tmdbTrendingTv = _deduplicateMovies([
          ...results[0],
          ...results[9],
        ]);
        _pakistaniTrendingTv = _deduplicateMovies(results[27]);
        _koreanTrendingMovies = _deduplicateMovies(results[28]);
        trendingTv = _deduplicateMovies([
          ...trendingTv,
          ...results[0],
          ...results[3],
          ...results[4],
          ...results[9],
        ]);
        popularTv = _deduplicateMovies([
          ...popularTv,
          ...results[1],
          ...results[10],
        ]);
        topRatedTv = _deduplicateMovies([
          ...topRatedTv,
          ...results[2],
          ...results[11],
        ]);

        trending = _deduplicateMovies([...trending, ...results[5]]);
        popular = _deduplicateMovies([...popular, ...results[6]]);
        latest = _deduplicateMovies([...latest, ...results[7]]);
        topRated = _deduplicateMovies([...topRated, ...results[8]]);

        final onAirAnime = [
          ...results[0],
          ...results[3],
          ...results[4],
          ...results[9],
        ].where(_isAnimeTitle);
        anime = _deduplicateMovies([...anime, ...results[12], ...onAirAnime]);

        final asianDrama = [
          ...results[13],
          ...results[23],
          ...results[24],
          ...results[25],
        ];
        if (asianDrama.isNotEmpty) {
          koreanDrama = _deduplicateMovies([...koreanDrama, ...asianDrama]);
        }
        if (results[14].isNotEmpty) {
          bengaliMovies = _deduplicateMovies([...bengaliMovies, ...results[14]]);
        }
        if (results[15].isNotEmpty) {
          bengaliTv = _deduplicateMovies([...bengaliTv, ...results[15]]);
        }

        final bollywood = [...results[16], ...results[26]];
        if (bollywood.isNotEmpty) {
          bollywoodMovies = _deduplicateMovies([...bollywoodMovies, ...bollywood]);
        }
        if (results[17].isNotEmpty) {
          hollywoodMovies = _deduplicateMovies([...hollywoodMovies, ...results[17]]);
        }

        final southIndian = [
          ...results[18],
          ...results[19],
          ...results[20],
          ...results[21],
        ];
        if (southIndian.isNotEmpty) {
          southIndianMovies = _deduplicateMovies([
            ...southIndianMovies,
            ...southIndian,
          ]);
        }
        if (results[22].isNotEmpty) {
          indianDramaTv = _deduplicateMovies([
            ...indianDramaTv,
            ...results[22],
          ]);
        }
      });

      if (completedAll) {
        _secondaryCatalogueNextIndex = 0;
        _lastSecondaryCataloguesRefreshAt = DateTime.now();
      } else {
        _backgroundCatalogueWorkPending = true;
      }
      await Future.wait([
        MovieCache.saveList(MovieCache.trendingKey, trending),
        MovieCache.saveList(MovieCache.tmdbTrendingMoviesKey, _tmdbTrendingMovies),
        MovieCache.saveList(MovieCache.popularKey, popular),
        MovieCache.saveList(MovieCache.latestKey, latest),
        MovieCache.saveList(MovieCache.topRatedKey, topRated),
        MovieCache.saveList(MovieCache.trendingTvKey, trendingTv),
        MovieCache.saveList(MovieCache.tmdbTrendingTvKey, _tmdbTrendingTv),
        MovieCache.saveList(MovieCache.pakistaniTrendingTvKey, _pakistaniTrendingTv),
        MovieCache.saveList(MovieCache.koreanTrendingMoviesKey, _koreanTrendingMovies),
        MovieCache.saveList(MovieCache.popularTvKey, popularTv),
        MovieCache.saveList(MovieCache.topRatedTvKey, topRatedTv),
        MovieCache.saveList(MovieCache.animeKey, anime),
        MovieCache.saveList(MovieCache.koreanKey, koreanDrama),
        MovieCache.saveList(MovieCache.bengaliMoviesKey, bengaliMovies),
        MovieCache.saveList(MovieCache.bengaliTvKey, bengaliTv),
        MovieCache.saveList(MovieCache.bollywoodMoviesKey, bollywoodMovies),
        MovieCache.saveList(MovieCache.hollywoodMoviesKey, hollywoodMovies),
        MovieCache.saveList(MovieCache.southIndianMoviesKey, southIndianMovies),
        MovieCache.saveList(MovieCache.indianDramaTvKey, indianDramaTv),
      ]);
      if (completedAll) {
        _secondaryCatalogueResults
          ..clear()
          ..addAll(List<List<Movie>>.generate(
            loaders.length,
            (_) => <Movie>[],
          ));
      }
      // Visibility refresh and playable-stream verification are coordinated
      // by _runBackgroundCatalogueWork; do not launch duplicate jobs here.
    } catch (error) {
      debugPrint('Background catalogue refresh failed: $error');
    } finally {
      _refreshingSecondaryCatalogues = false;
    }
  }

  Future<void> loadHome({bool forceRefresh = false}) async {
    if (_refreshing) {
      _homeRefreshQueued = true;
      return;
    }
    _refreshing = true;

    try {
      final online = await InternetService.isOnline(forceRefresh: forceRefresh);
      if (!mounted) return;

      if (!online) {
        setState(() {
          _online = false;
          _connectionKnown = true;
          loading = false;
          if (_allMovies().isEmpty) homeError = 'offline';
        });
        return;
      }

      setState(() {
        _online = true;
        _connectionKnown = true;
        loading = _allMovies().isEmpty;
        homeError = null;
      });

      // MovieBox sections can render independently while TMDB is loading.
      unawaited(_refreshMovieBoxHome(forceRefresh: forceRefresh));
      unawaited(_refreshPakistaniDramaCatalogue(forceRefresh: forceRefresh));
      unawaited(_refreshChineseDramaCatalogue(forceRefresh: forceRefresh));

      var completedRequests = 0;
      const primaryRequestCount = 5;

      Future<void> loadPrimarySection(
        Future<List<Movie>> request,
        void Function(List<Movie>) apply,
        Future<void> Function() persist,
      ) async {
        List<Movie> movies;
        try {
          movies = await request;
        } catch (error) {
          debugPrint('Home section request failed: $error');
          movies = <Movie>[];
        }
        completedRequests++;

        if (!mounted) return;
        if (movies.isNotEmpty) {
          setState(() {
            apply(movies);
            loading = false;
            homeError = null;
          });
          _syncFeaturedCarouselAfterDataChange();
          await persist();
        } else if (completedRequests == primaryRequestCount &&
            _allMovies().isEmpty) {
          setState(() {
            loading = false;
            homeError = 'Unable to load movies.';
          });
        }
      }

      // Each section is painted and cached as soon as its own request finishes;
      // the slowest endpoint no longer blocks every Home card.
      await Future.wait([
        loadPrimarySection(
          TmdbService.getMovies('trending/movie/week', forceRefresh: forceRefresh),
          (movies) {
            _tmdbTrendingMovies = movies;
            trending = movies;
            final composed = _homeTrendingMovies();
            if (composed.isNotEmpty) trending = composed;
          },
          () async {
            await Future.wait([
              MovieCache.saveList(MovieCache.trendingKey, trending),
              MovieCache.saveList(
                MovieCache.tmdbTrendingMoviesKey,
                _tmdbTrendingMovies,
              ),
            ]);
          },
        ),
        loadPrimarySection(
          TmdbService.getMovies('movie/popular', forceRefresh: forceRefresh),
          (movies) => popular = movies,
          () => MovieCache.saveList(MovieCache.popularKey, popular),
        ),
        loadPrimarySection(
          TmdbService.getMovies('movie/now_playing', forceRefresh: forceRefresh),
          (movies) => latest = movies,
          () => MovieCache.saveList(MovieCache.latestKey, latest),
        ),
        loadPrimarySection(
          TmdbService.getMovies('movie/top_rated', forceRefresh: forceRefresh),
          (movies) => topRated = movies,
          () => MovieCache.saveList(MovieCache.topRatedKey, topRated),
        ),
        loadPrimarySection(
          FlixoraMovieService.getPublishedMovies(),
          (movies) {
            flixoraMovies = movies;
            final composed = _homeTrendingMovies();
            if (composed.isNotEmpty) trending = composed;
          },
          () async {
            await Future.wait([
              MovieCache.saveList(MovieCache.flixoraKey, flixoraMovies),
              MovieCache.saveList(MovieCache.trendingKey, trending),
            ]);
          },
        ),
      ]);

      _lastHomeRefreshAt = DateTime.now();
      if (!mounted) return;

      unawaited(_runBackgroundCatalogueWork(forceRefresh: forceRefresh));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        if (_allMovies().isEmpty) homeError = error.toString();
      });
    } finally {
      _refreshing = false;
      if (_homeRefreshQueued) {
        _homeRefreshQueued = false;
        if (mounted && _online) unawaited(loadHome(forceRefresh: true));
      }
    }
  }

  int _catalogueFingerprint() => Object.hashAll([
        identityHashCode(_movieBoxSections), _movieBoxSections.length,
        identityHashCode(flixoraMovies), flixoraMovies.length,
        identityHashCode(_trendingMovies), _trendingMovies.length,
        identityHashCode(_tmdbTrendingMovies), _tmdbTrendingMovies.length,
        identityHashCode(trending), trending.length,
        identityHashCode(popular), popular.length,
        identityHashCode(latest), latest.length,
        identityHashCode(topRated), topRated.length,
        identityHashCode(trendingTv), trendingTv.length,
        identityHashCode(_tmdbTrendingTv), _tmdbTrendingTv.length,
        identityHashCode(popularTv), popularTv.length,
        identityHashCode(topRatedTv), topRatedTv.length,
        identityHashCode(anime), anime.length,
        identityHashCode(koreanDrama), koreanDrama.length,
        identityHashCode(bengaliMovies), bengaliMovies.length,
        identityHashCode(bengaliTv), bengaliTv.length,
        identityHashCode(bollywoodMovies), bollywoodMovies.length,
        identityHashCode(hollywoodMovies), hollywoodMovies.length,
        identityHashCode(southIndianMovies), southIndianMovies.length,
        identityHashCode(indianDramaTv), indianDramaTv.length,
        identityHashCode(_pakistaniTrendingTv), _pakistaniTrendingTv.length,
        identityHashCode(_chineseTrendingTv), _chineseTrendingTv.length,
        identityHashCode(_koreanTrendingMovies), _koreanTrendingMovies.length,
        Object.hashAll(_unpublishedCatalogKeys),
      ]);

  List<Movie> _allMovies() {
    final fingerprint = _catalogueFingerprint();
    final cached = _allMoviesCache;
    if (cached != null && _allMoviesCacheFingerprint == fingerprint) {
      return cached;
    }

    final combined = <Movie>[
      ..._regularMovieBoxItems,
      ...flixoraMovies,
      ..._trendingMovies,
      ...trending,
      ...popular,
      ...latest,
      ...topRated,
      ...trendingTv,
      ...popularTv,
      ...topRatedTv,
      ...anime,
      ...koreanDrama,
      ...bengaliMovies,
      ...bengaliTv,
      ...bollywoodMovies,
      ...hollywoodMovies,
      ...southIndianMovies,
      ...indianDramaTv,
    ];

    final result = _deduplicateMovies(combined);
    _allMoviesCacheFingerprint = fingerprint;
    _allMoviesCache = result;
    return result;
  }

  Future<void> searchMovies(String query) async {
    final text = query.trim();
    final requestToken = ++_searchRequestToken;

    if (text.isEmpty) {
      if (!mounted) return;
      setState(() {
        _search = '';
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    if (!mounted) return;
    final cachedSearch =
        _deduplicateMovies(await MovieCache.getSearch(text));
    if (!mounted ||
        requestToken != _searchRequestToken ||
        _search.trim().toLowerCase() != text.toLowerCase()) {
      return;
    }

    if (cachedSearch.isNotEmpty) {
      setState(() {
        searchResults = cachedSearch;
        _searchLoading = true;
        _searchError = null;
      });
    }

    final onlineNow = _online
        ? await InternetService.isOnline()
        : await InternetService.isOnline(forceRefresh: true);
    if (!mounted ||
        requestToken != _searchRequestToken ||
        _search.trim().toLowerCase() != text.toLowerCase()) {
      return;
    }

    if (!onlineNow) {
      setState(() {
        _online = false;
        _connectionKnown = true;
        _search = text;
        searchResults = cachedSearch;
        _searchLoading = false;
        _searchError =
            cachedSearch.isEmpty ? 'Check your internet connection' : null;
      });
      return;
    }

    setState(() {
      _online = true;
      _connectionKnown = true;
      _search = text;
      if (cachedSearch.isNotEmpty) searchResults = cachedSearch;
      _searchLoading = true;
      _searchError = null;
    });

    final adminSearch = FlixoraMovieService.searchPublishedMovies(text)
        .catchError((_) => <Movie>[]);
    final tmdbSearch = TmdbService.search(text)
        .catchError((_) => <Movie>[]);
    final movieBoxSearch = MovieBoxService.search(text)
        .timeout(const Duration(seconds: 10))
        .then((result) {
      final items = result['items'] as List? ?? const [];
      return items
          .whereType<Map>()
          .map((item) => Movie.fromMovieBox(Map<String, dynamic>.from(item)))
          .where((movie) => movie.movieBoxId.isNotEmpty)
          .toList(growable: false);
    }).catchError((_) => <Movie>[]);

    var adminResults = <Movie>[];
    var tmdbResults = <Movie>[];
    var movieBoxItems = <Movie>[];
    var completedRequests = 0;

    void applySearchResults() {
      if (!mounted ||
          requestToken != _searchRequestToken ||
          _search.trim().toLowerCase() != text.toLowerCase()) {
        return;
      }
      final unique = _deduplicateMovies([
        ...movieBoxItems,
        ...adminResults,
        ...tmdbResults,
      ]);
      setState(() {
        searchResults = unique;
        _searchLoading = completedRequests < 3;
        _searchError =
            unique.isEmpty && completedRequests == 3 ? 'No movies found.' : null;
      });
    }

    await Future.wait<void>([
      adminSearch.then<void>((items) {
        adminResults = items;
        completedRequests++;
        applySearchResults();
      }),
      tmdbSearch.then<void>((items) {
        tmdbResults = items;
        completedRequests++;
        applySearchResults();
      }),
      movieBoxSearch.then<void>((items) {
        movieBoxItems = items;
        completedRequests++;
        applySearchResults();
      }),
    ]);

    if (!mounted ||
        requestToken != _searchRequestToken ||
        _search.trim().toLowerCase() != text.toLowerCase()) {
      return;
    }

    await _refreshCatalogVisibility(
      candidates: [...adminResults, ...movieBoxItems, ...tmdbResults],
    );
    final unique = _deduplicateMovies([
      ...movieBoxItems,
      ...adminResults,
      ...tmdbResults,
    ]);
    setState(() {
      searchResults = unique;
      _searchLoading = false;
      _searchError = unique.isEmpty ? 'No movies found.' : null;
    });
    await MovieCache.saveSearch(text, unique);
  }

  void _onSearchChanged(String value) {
    _searchRequestToken++;
    _searchTimer?.cancel();
    final query = value.trim();

    if (query.isEmpty) {
      _searchRequestToken++;
      setState(() {
        _search = '';
        _searchCategory = 'All';
        searchResults = [];
        _searchError = null;
        _searchLoading = false;
      });
      return;
    }

    setState(() {
      _search = query;
      _searchCategory = 'All';
      searchResults = [];
      _searchLoading = true;
      _searchError = null;
    });

    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => searchMovies(query),
    );
  }

  // ignore: unused_element
  Future<void> _toggleFavourite(Movie movie) async {
    setState(() {
      if (_favourites.contains(movie.id)) {
        _favourites.remove(movie.id);
      } else {
        _favourites.add(movie.id);
      }
    });

    await MovieCache.saveFavourites(_favourites);
  }

  Future<void> _toggleSaved(Movie movie) async {
    setState(() {
      if (_saved.contains(movie.id)) {
        _saved.remove(movie.id);
      } else {
        _saved.add(movie.id);
      }
    });

    await MovieCache.saveSaved(_saved);
  }

  Map<String, String> _decodeDownloadHeaders(String? raw) {
    try {
      final decoded = jsonDecode(raw ?? '{}');
      if (decoded is Map) {
        return Map<String, String>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
        );
      }
    } catch (_) {}
    return const <String, String>{};
  }

  Future<List<Map<String, String>>> _movieBoxDirectDownloadOptions(
    Movie movie, {
    required int season,
    required int episode,
  }) async {
    final detail = await MovieBoxService.playDetail(movie.toMovieBoxMap());
    final response = await MovieBoxService.streams(
      detail,
      season: season,
      episode: episode,
      isSeries: movie.movieBoxIsSeries,
    );
    final links = response['links'] as List? ?? const [];
    final options = <Map<String, String>>[];
    for (final rawLink in links.whereType<Map>()) {
      final link = Map<String, dynamic>.from(rawLink);
      final url = (link['url'] ?? '').toString().trim();
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) continue;
      final kind = (link['kind'] ?? link['type'] ?? link['format'] ?? '')
          .toString().toLowerCase().replaceAll('video/', '').trim();
      final path = uri.path.toLowerCase();
      final streamKind = RustPlaybackCore.detectStreamKind(url);
      final adaptive = streamKind == 1 || streamKind == 2 ||
          path.endsWith('.m3u8') || path.endsWith('.mpd') ||
          kind == 'hls' || kind == 'dash' || kind == 'm3u8' || kind == 'mpd';
      if (adaptive) continue;
      final directFile = <int>{3, 4, 5, 6, 7, 8}.contains(streamKind) ||
          <String>{'mp4', 'mkv', 'webm', 'mov', 'avi', 'm4v'}.contains(kind) ||
          RegExp(r'\.(mp4|mkv|webm|mov|avi|m4v)$', caseSensitive: false).hasMatch(path);
      if (!directFile) continue;
      final rawHeaders = link['headers'];
      final headers = rawHeaders is Map
          ? Map<String, String>.from(rawHeaders.map(
              (key, value) => MapEntry(key.toString(), value.toString())))
          : const <String, String>{};
      final label = (link['quality'] ?? link['label'] ?? 'Original').toString();
      final languageMatch = RegExp(r'\[([^\]]+)\]\s*$').firstMatch(label);
      final language = (link['language'] ?? link['audioLanguage'] ??
              languageMatch?.group(1) ?? movie.originalLanguage)
          .toString().trim();
      options.add(<String, String>{
        'quality': label,
        'language': language.isEmpty ? 'Original' : language,
        'video_url': url,
        'headers': jsonEncode(headers),
      });
    }
    return options;
  }

  Future<void> _prefetchSeasonDownloadOptions(
    Movie movie, {
    required int season,
    required List<int> episodes,
    required Map<int, List<Map<String, String>>> seed,
    required void Function(Map<int, List<Map<String, String>>>) onBatch,
  }) async {
    final results = <int, List<Map<String, String>>>{...seed};
    final pending = episodes.where((episode) => !results.containsKey(episode)).toList();
    for (var offset = 0; offset < pending.length; offset += 3) {
      final batch = pending.skip(offset).take(3).toList(growable: false);
      final loaded = await Future.wait(batch.map((episode) async {
        try {
          return MapEntry(episode, await _movieBoxDirectDownloadOptions(
            movie, season: season, episode: episode));
        } catch (error) {
          debugPrint('Download options unavailable for S$season E$episode: $error');
          return MapEntry(episode, <Map<String, String>>[]);
        }
      }));
      for (final entry in loaded) {
        results[entry.key] = entry.value;
      }
      onBatch(Map<int, List<Map<String, String>>>.from(results));
    }
    if (pending.isEmpty) onBatch(Map<int, List<Map<String, String>>>.from(results));
  }

  String _downloadLanguage(Map<String, String> option) {
    final explicit = (option['language'] ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final label = option['quality'] ?? '';
    final match = RegExp(r'\[([^\]]+)\]\s*$').firstMatch(label);
    return match?.group(1)?.trim() ?? 'Original';
  }

  String _downloadQuality(Map<String, String> option) {
    final explicit = (option['quality'] ?? '').trim();
    final match = RegExp(r'^\s*(\d{3,4}p)', caseSensitive: false)
        .firstMatch(explicit);
    return match?.group(1)?.toUpperCase() ?? explicit;
  }

  Future<Map<String, dynamic>?> _showDownloadSelectionSheet({
    required Movie movie,
    required List<Map<String, String>> initialOptions,
    required bool isSeries,
    required List<Map<String, dynamic>> seasons,
    required int initialSeason,
    required int initialEpisode,
  }) async {
    var options = initialOptions;
    var selectedSeason = initialSeason;
    var selectedLanguage = options.isNotEmpty
        ? _downloadLanguage(options.first)
        : (movie.originalLanguage.isNotEmpty ? movie.originalLanguage : 'Original');
    var selectedQuality = options.isNotEmpty ? _downloadQuality(options.first) : '';
    var seasonRequestToken = 0;
    final prefetchStartedForSeason = <int>{};
    final episodeOptionsBySeason =
        <int, Map<int, List<Map<String, String>>>>{
      if (initialSeason > 0)
        initialSeason: {
          if (initialEpisode > 0) initialEpisode: initialOptions,
        },
    };
    final episodesBySeason = <int, List<int>>{
      for (final season in seasons)
        _toInt(season['se']): ((season['episodes'] as List? ?? const [])
            .map(_toInt)
            .where((number) => number > 0)
            .toList()
          ..sort()),
    };
    var episodeNumbers = episodesBySeason[selectedSeason] ?? <int>[];
    final selectedEpisodes = <int>{
      if (initialEpisode > 0 && episodeNumbers.contains(initialEpisode))
        initialEpisode,
    };
    if (isSeries && selectedEpisodes.isEmpty && episodeNumbers.isNotEmpty) {
      selectedEpisodes.add(episodeNumbers.first);
    }
    final selectedQualities = <String>{if (selectedQuality.isNotEmpty) selectedQuality};

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: panel,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          if (isSeries && prefetchStartedForSeason.add(selectedSeason)) {
            final season = selectedSeason;
            final token = ++seasonRequestToken;
            final seed = Map<int, List<Map<String, String>>>.from(
              episodeOptionsBySeason[season] ?? const {},
            );
            unawaited(_prefetchSeasonDownloadOptions(
              movie,
              season: season,
              episodes: episodeNumbers,
              seed: seed,
              onBatch: (loaded) {
                if (!sheetContext.mounted ||
                    token != seasonRequestToken ||
                    selectedSeason != season) return;
                setSheetState(() {
                  episodeOptionsBySeason[season] = loaded;
                  options = loaded.values.expand((items) => items).toList();
                  final loadedLanguages =
                      options.map(_downloadLanguage).toSet().toList()..sort();
                  if (loadedLanguages.isNotEmpty &&
                      !loadedLanguages.contains(selectedLanguage)) {
                    selectedLanguage = loadedLanguages.first;
                  }
                  final loadedQualities = options
                      .where((item) => _downloadLanguage(item) == selectedLanguage)
                      .map(_downloadQuality)
                      .where((item) => item.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort((a, b) {
                      final av = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 0;
                      final bv = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '') ?? 0;
                      return bv.compareTo(av);
                    });
                  if (selectedQuality.isEmpty || !loadedQualities.contains(selectedQuality)) {
                    selectedQuality = loadedQualities.isNotEmpty ? loadedQualities.first : '';
                    selectedQualities
                      ..clear()
                      ..addAll(selectedQuality.isEmpty ? <String>[] : <String>[selectedQuality]);
                  }
                });
              },
            ));
          }
          final languages = options.map(_downloadLanguage).toSet().toList()..sort();
          if (languages.isEmpty) languages.add(selectedLanguage);
          if (!languages.contains(selectedLanguage) && languages.isNotEmpty) {
            selectedLanguage = languages.first;
          }
          final languageOptions = options
              .where((item) => _downloadLanguage(item) == selectedLanguage)
              .toList();
          final qualities = languageOptions
              .map(_downloadQuality)
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) {
              final av = int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 0;
              final bv = int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '') ?? 0;
              return bv.compareTo(av);
            });
          final availableEpisodeNumbers = isSeries
              ? episodeNumbers
              : <int>[];
          final allEpisodesSelected = availableEpisodeNumbers.isNotEmpty &&
              availableEpisodeNumbers.every(selectedEpisodes.contains);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18, 12, 18, 12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.84,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Download', style: TextStyle(
                          color: white, fontSize: 21, fontWeight: FontWeight.w800,
                        )),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, color: ink60),
                      ),
                    ],
                  ),
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ink70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding: const EdgeInsets.only(top: 5, bottom: 12),
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: languages.contains(selectedLanguage)
                              ? selectedLanguage
                              : (languages.isNotEmpty ? languages.first : null),
                          dropdownColor: panel,
                          decoration: const InputDecoration(
                            labelText: 'Audio / Language', filled: true, fillColor: bg,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          items: languages.map((language) => DropdownMenuItem(
                            value: language, child: Text(language),
                          )).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() {
                              selectedLanguage = value;
                              final matching = options
                                  .where((item) => _downloadLanguage(item) == value)
                                  .map(_downloadQuality).toSet();
                              selectedQuality = matching.isEmpty ? '' : matching.first;
                              selectedQualities
                                ..clear()
                                ..addAll(matching);
                            });
                          },
                        ),
                        if (isSeries) ...[
                          const SizedBox(height: 10),
                          DropdownButtonFormField<int>(
                            initialValue: selectedSeason,
                            dropdownColor: panel,
                            decoration: const InputDecoration(
                              labelText: 'Season', filled: true, fillColor: bg,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            items: seasons.map((season) {
                              final number = _toInt(season['se']);
                              return DropdownMenuItem(
                                value: number,
                                child: Text('Season ' + number.toString().padLeft(2, '0')),
                              );
                            }).toList(),
                            onChanged: (number) {
                              if (number == null || number == selectedSeason) return;
                              final nextEpisodes = episodesBySeason[number] ?? <int>[];
                              if (nextEpisodes.isEmpty) return;
                              seasonRequestToken++;
                              final cached = episodeOptionsBySeason[number] ?? const {};
                              final cachedOptions =
                                  cached.values.expand((items) => items).toList();
                              setSheetState(() {
                                selectedSeason = number;
                                episodeNumbers = nextEpisodes;
                                selectedEpisodes
                                  ..clear()
                                  ..add(nextEpisodes.first);
                                options = cachedOptions;
                                selectedLanguage = options.isNotEmpty
                                    ? _downloadLanguage(options.first)
                                    : (movie.originalLanguage.isNotEmpty
                                        ? movie.originalLanguage : 'Original');
                                selectedQuality = options.isNotEmpty
                                    ? _downloadQuality(options.first) : '';
                                selectedQualities
                                  ..clear()
                                  ..addAll(selectedQuality.isEmpty
                                      ? <String>[] : <String>[selectedQuality]);
                              });
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B1B20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: gold.withValues(alpha: 0.18)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('Resources', style: TextStyle(
                                    color: white, fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  )),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      selectedLanguage,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: ink60, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (qualities.isEmpty)
                                const Text(
                                  'Checking available download qualities...',
                                  style: TextStyle(color: ink60, fontSize: 12),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: qualities.map((quality) {
                                    final selected = selectedQualities.contains(quality);
                                    return ChoiceChip(
                                      label: Text(quality),
                                      selected: selected,
                                      showCheckmark: false,
                                      selectedColor: gold,
                                      backgroundColor: const Color(0xFF29292F),
                                      labelStyle: TextStyle(
                                        color: selected ? bg : white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      onSelected: (_) {
                                        setSheetState(() {
                                          selectedQuality = quality;
                                          selectedQualities
                                            ..clear()
                                            ..add(quality);

                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                        if (isSeries) ...[
                          const SizedBox(height: 10),
                          const Text('Episodes', style: TextStyle(
                            color: white, fontSize: 15, fontWeight: FontWeight.w700,
                          )),
                          if (availableEpisodeNumbers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No episodes are available in the selected quality.',
                                style: TextStyle(color: ink60, fontSize: 12),
                              ),
                            )
                          else
                            ...availableEpisodeNumbers.map((episode) => CheckboxListTile(
                              dense: true, contentPadding: EdgeInsets.zero,
                              activeColor: gold, checkColor: bg,
                              value: selectedEpisodes.contains(episode),
                              title: Text(
                                'S' + selectedSeason.toString().padLeft(2, '0') +
                                ' E' + episode.toString().padLeft(2, '0'),
                                style: const TextStyle(color: white),
                              ),
                              onChanged: (checked) => setSheetState(() {
                                if (checked == true) selectedEpisodes.add(episode);
                                else selectedEpisodes.remove(episode);
                              }),
                            )),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (isSeries)
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: goldLight, side: const BorderSide(color: gold),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: availableEpisodeNumbers.isEmpty
                                ? null
                                : () => setSheetState(() {
                                    if (allEpisodesSelected) selectedEpisodes.clear();
                                    else selectedEpisodes.addAll(availableEpisodeNumbers);
                                  }),
                            icon: const Icon(Icons.select_all_rounded, size: 18),
                            label: Text(allEpisodesSelected ? 'Clear episodes' : 'Select All'),
                          ),
                        )
                      else
                        Expanded(
                          child: Text(
                            selectedQualities.length.toString() + ' quality(s) selected',
                            style: const TextStyle(color: ink70, fontSize: 12),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: gold, foregroundColor: bg,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed:
                                  (isSeries ? selectedEpisodes.isEmpty : selectedQualities.isEmpty) ||
                                  selectedQualities.isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, <String, dynamic>{
                                  'language': selectedLanguage,
                                  'qualities': selectedQualities.toList(),
                                  'season': selectedSeason,
                                  'episodes': selectedEpisodes.toList()..sort(),
                                  'episodeOptionsByNumber': <String, List<Map<String, String>>>{
                                    for (final entry in (episodeOptionsBySeason[selectedSeason] ??
                                        const <int, List<Map<String, String>>>{}).entries)
                                      entry.key.toString(): entry.value,
                                  },
                                }),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  Future<void> _queueSelectedDownload(
    Movie movie,
    Map<String, String> selected, {
    int? seasonNumber,
    int? episodeNumber,
    List<Map<String, String>>? fallbackOptions,
  }) async {
    final quality = _downloadQuality(selected);
    final existing = _downloads.where((item) =>
        item.movieId == movie.id &&
        (item.seasonNumber ?? 0) == (seasonNumber ?? 0) &&
        (item.episodeNumber ?? 0) == (episodeNumber ?? 0) &&
        item.quality == quality).toList();
    if (existing.any((item) => item.status == 'Completed')) {
      _showMessage(movie.title + ' is already downloaded in ' + quality + '.');
      return;
    }
    final resumable = existing.where((item) =>
        item.status == 'Paused' || item.status == 'Failed').toList();
    if (resumable.isNotEmpty) {
      await _pauseResumeDownload(resumable.first);
      return;
    }
    if (existing.any((item) =>
        item.status == 'Downloading' || item.status == 'Waiting')) {
      _showMessage(quality + ' is already in the download queue.');
      return;
    }

    final candidates = <Map<String, String>>[];
    final seenCandidates = <String>{};
    for (final option in fallbackOptions ?? <Map<String, String>>[selected]) {
      final url = (option['video_url'] ?? '').trim();
      if (url.isEmpty) continue;
      final headers = option['headers'] ?? '{}';
      if (!seenCandidates.add('$url|$headers')) continue;
      candidates.add(<String, String>{'video_url': url, 'headers': headers});
    }
    if (candidates.isEmpty) return;

    final first = candidates.first;
    final task = DownloadTask(
      movieId: movie.id,
      downloadId: DateTime.now().microsecondsSinceEpoch,
      title: movie.title,
      poster: movie.posterUrl,
      videoUrl: first['video_url'] ?? '',
      quality: quality,
      headers: _decodeDownloadHeaders(first['headers']),
      sourceCandidates: candidates,
      sourceIndex: 0,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      totalBytes: 0,
      status: 'Waiting',
    );
    if (task.videoUrl.isEmpty) return;
    if (mounted) setState(() => _downloads.insert(0, task));
    unawaited(_runDownloadTask(task));
  }

  Future<void> addDownload(
    Movie movie, {
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final preparationKey =
        '${movie.source}:${movie.id}:${seasonNumber ?? 0}:${episodeNumber ?? 0}';
    if (!_downloadPreparationKeys.add(preparationKey)) return;

    _showMessage('Preparing download options...');
    try {
      await _prepareDownload(
        movie,
        seasonNumber: seasonNumber,
        episodeNumber: episodeNumber,
      );
    } finally {
      _downloadPreparationKeys.remove(preparationKey);
    }
  }

  Future<void> _prepareDownload(
    Movie movie, {
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final hasInternet = await InternetService.isOnline();
    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _online = false;
          _connectionKnown = true;
        });
        _showMessage('Check your internet connection');
      }
      return;
    }
    if (mounted && !_online) setState(() => _online = true);

    final isSeries = movie.isMovieBox && movie.movieBoxIsSeries;
    var resolvedSeason = seasonNumber ?? 0;
    var resolvedEpisode = episodeNumber ?? 0;
    var availableSeasons = <Map<String, dynamic>>[];
    if (isSeries) {
      try {
        availableSeasons = await MovieBoxService.seasons(movie.movieBoxId);
        if (availableSeasons.isEmpty) {
          _showMessage('No seasons are available to download for this series.');
          return;
        }
        final chosen = availableSeasons.firstWhere(
          (item) => resolvedSeason > 0 && _toInt(item['se']) == resolvedSeason,
          orElse: () => availableSeasons.first,
        );
        resolvedSeason = _toInt(chosen['se']);
        final episodes = (chosen['episodes'] as List? ?? const [])
            .map(_toInt)
            .where((number) => number > 0)
            .toList(growable: false);
        if (episodes.isEmpty) {
          _showMessage('No episodes are available in this season.');
          return;
        }
        if (!episodes.contains(resolvedEpisode)) {
          resolvedEpisode = episodes.first;
        }
      } catch (error) {
        debugPrint('MovieBox season lookup for download failed: $error');
        _showMessage('Could not load this series episode list. Please retry.');
        return;
      }
    }

    List<Map<String, String>> rawOptions;
    try {
      rawOptions = movie.isMovieBox
          ? await _movieBoxDirectDownloadOptions(
              movie,
              season: resolvedSeason,
              episode: resolvedEpisode,
            )
          : await FlixoraMovieService.getDownloadQualities(movie);
    } catch (error) {
      debugPrint('Download source lookup failed: $error');
      rawOptions = <Map<String, String>>[];
    }
    if (!mounted) return;
    if (rawOptions.isEmpty && !isSeries) {
      _showMessage(
        movie.isMovieBox
            ? 'A direct downloadable video source is not available for this title.'
            : 'Download source is not available for this movie. Ask Admin to add a direct video file.',
      );
      return;
    }

    final options = rawOptions.map((item) {
      final label = item['quality'] ?? 'Original';
      final languageMatch = RegExp(r'\[([^\]]+)\]\s*$').firstMatch(label);
      final qualityMatch = RegExp(r'^\s*(\d{3,4}p)', caseSensitive: false)
          .firstMatch(label);
      final language = (item['language'] ??
              languageMatch?.group(1) ??
              movie.originalLanguage)
          .toString()
          .trim();
      return <String, String>{
        ...item,
        'quality': qualityMatch?.group(1)?.toUpperCase() ?? label,
        'language': language.isEmpty ? 'Original' : language,
        'size_bytes': '',
        'size_label': 'Detected when download starts',
      };
    }).toList(growable: false);

    final selection = await _showDownloadSelectionSheet(
      movie: movie,
      initialOptions: options,
      isSeries: isSeries,
      seasons: availableSeasons,
      initialSeason: resolvedSeason,
      initialEpisode: resolvedEpisode,
    );
    if (!mounted || selection == null) return;

    final language = (selection['language'] ?? 'Original').toString();
    final qualities = (selection['qualities'] as List? ?? const [])
        .map((item) => item.toString())
        .toSet();
    if (isSeries) {
      final selectedSeason = _toInt(selection['season']);
      final episodes = (selection['episodes'] as List? ?? const [])
          .map(_toInt).where((number) => number > 0).toList();
      final cachedRaw = selection['episodeOptionsByNumber'];
      final cachedOptions = <int, List<Map<String, String>>>{};
      if (cachedRaw is Map) {
        for (final entry in cachedRaw.entries) {
          final episode = int.tryParse(entry.key.toString()) ?? 0;
          if (episode <= 0 || entry.value is! List) continue;
          cachedOptions[episode] = (entry.value as List)
              .whereType<Map>()
              .map((item) => Map<String, String>.from(item.map(
                    (key, value) => MapEntry(key.toString(), value.toString()))))
              .toList(growable: false);
        }
      }
      final allEpisodeOptions = <int, List<Map<String, String>>>{};
      await _prefetchSeasonDownloadOptions(
        movie,
        season: selectedSeason,
        episodes: episodes,
        seed: cachedOptions,
        onBatch: (loaded) => allEpisodeOptions
          ..clear()
          ..addAll(loaded),
      );
      var queued = 0;
      var unavailable = 0;
      for (final episode in episodes) {
        final episodeOptions = allEpisodeOptions[episode] ?? const [];
        for (final quality in qualities) {
          final matches = episodeOptions.where((item) =>
              _downloadLanguage(item).toLowerCase() == language.toLowerCase() &&
              _downloadQuality(item).toLowerCase() == quality.toLowerCase()).toList();
          if (matches.isEmpty) {
            unavailable++;
            continue;
          }
          await _queueSelectedDownload(
            movie,
            matches.first,
            fallbackOptions: matches,
            seasonNumber: selectedSeason,
            episodeNumber: episode,
          );
          queued++;
        }
      }
      if (unavailable > 0) {
        _showMessage(
          queued.toString() + ' episode download(s) queued; ' +
          unavailable.toString() + ' selected-quality source(s) unavailable.',
        );
      } else if (queued > 0) {
        _showMessage(queued.toString() + ' episode(s) added to downloads.');
      }
      return;
    }

    final selectedOptions = options.where((item) =>
        _downloadLanguage(item).toLowerCase() == language.toLowerCase() &&
        qualities.contains(_downloadQuality(item))).toList();
    final groupedOptions = <String, List<Map<String, String>>>{};
    for (final option in selectedOptions) {
      (groupedOptions[_downloadQuality(option)] ??= <Map<String, String>>[])
          .add(option);
    }
    for (final group in groupedOptions.values) {
      await _queueSelectedDownload(movie, group.first, fallbackOptions: group);
    }
    if (groupedOptions.isNotEmpty) {
      _showMessage(groupedOptions.length.toString() + ' download quality(ies) added to queue.');
    }
  }

  Future<void> _runDownloadTask(
    DownloadTask task, {
    bool resume = false,
  }) async {
    final downloadId = task.downloadId > 0 ? task.downloadId : task.movieId;
    final candidates = task.sourceCandidates.isEmpty
        ? <Map<String, String>>[
            <String, String>{
              'video_url': task.videoUrl,
              'headers': jsonEncode(task.headers),
            },
          ]
        : task.sourceCandidates;
    if (candidates.isEmpty) {
      if (mounted) setState(() {
        task
          ..status = 'Failed'
          ..errorMessage = 'No downloadable source is available.';
      });
      return;
    }

    final backgroundSession = await _beginBackgroundDownloadTask();
    try {
      final firstIndex = task.sourceIndex.clamp(0, candidates.length - 1).toInt();
    for (var index = firstIndex; index < candidates.length; index++) {
      final candidate = candidates[index];
      final url = (candidate['video_url'] ?? '').trim();
      if (url.isEmpty) continue;
      final headers = _decodeDownloadHeaders(candidate['headers']);
      task
        ..sourceIndex = index
        ..videoUrl = url
        ..headers = headers;
      var lastUiBytes = -1;
      var failureMessage = '';
      var completed = false;
      var paused = false;
      final shouldResume = resume && index == firstIndex;

      await DownloadManager.download(
        url: url,
        fileName: '${task.displayTitle}_${task.quality}',
        uniqueId: downloadId,
        headers: headers,
        existingPartialPath: shouldResume ? task.filePath : null,
        onQueued: (path, offset) {
          if (!mounted) return;
          setState(() {
            task
              ..filePath = path
              ..bytesReceived = offset
              ..status = 'Waiting'
              ..errorMessage = null;
          });
          unawaited(MovieCache.saveDownloads(_downloads));
        },
        onStarted: (path, offset) {
          if (!mounted) return;
          setState(() {
            task
              ..filePath = path
              ..bytesReceived = offset
              ..status = 'Downloading'
              ..errorMessage = null;
          });
          unawaited(MovieCache.saveDownloads(_downloads));
        },
        onProgress: (received, total) {
          if (!mounted) return;
          if (lastUiBytes >= 0 && received - lastUiBytes < 256 * 1024) return;
          lastUiBytes = received;
          setState(() {
            task.bytesReceived = received;
            if (total > 0) task.totalBytes = total;
            if (task.totalBytes > 0) {
              task.progress = (received / task.totalBytes).clamp(0.0, 1.0);
            }
          });
        },
        onPaused: (path, received, total) {
          paused = true;
          if (!mounted) return;
          setState(() {
            task
              ..filePath = path
              ..bytesReceived = received
              ..totalBytes = total > 0 ? total : task.totalBytes
              ..progress = task.totalBytes > 0
                  ? (received / task.totalBytes).clamp(0.0, 1.0)
                  : task.progress
              ..status = 'Paused'
              ..errorMessage = null;
          });
          unawaited(MovieCache.saveDownloads(_downloads));
          _showMessage('Download paused. You can resume it any time.');
        },
        onComplete: (path) async {
          completed = true;
          final fileSize = await File(path).length();
          unawaited(
            FlixoraNotificationService.showDownloadComplete(
              title: task.displayTitle,
              uniqueId: downloadId,
            ),
          );
          if (!mounted) return;
          setState(() {
            task
              ..progress = 1
              ..bytesReceived = fileSize
              ..totalBytes = fileSize
              ..status = 'Completed'
              ..filePath = path
              ..errorMessage = null;
          });
          await MovieCache.saveDownloads(_downloads);
          _showMessage('Successfully downloaded ${task.displayTitle}.');
        },
        onError: (message) {
          failureMessage = message;
        },
      );

      if (completed || paused) return;
      if (failureMessage.isEmpty) {
        failureMessage = 'Download failed. Please try another available source.';
      }
      final canFallback = index + 1 < candidates.length &&
          failureMessage.toLowerCase() != 'download cancelled.';
      if (canFallback) {
        final partialPath = task.filePath;
        if (partialPath != null) {
          try {
            final partialFile = File(partialPath);
            if (await partialFile.exists()) await partialFile.delete();
          } catch (_) {}
        }
        task
          ..filePath = null
          ..bytesReceived = 0
          ..totalBytes = 0
          ..progress = 0
          ..status = 'Waiting'
          ..errorMessage = null
          ..sourceIndex = index + 1;
        resume = false;
        await MovieCache.saveDownloads(_downloads);
        continue;
      }

      if (!mounted) return;
      setState(() {
        task
          ..status = 'Failed'
          ..errorMessage = failureMessage;
      });
      await MovieCache.saveDownloads(_downloads);
      _showMessage(failureMessage);
      return;
      }
    } finally {
      await _endBackgroundDownloadTask(backgroundSession);
    }
  }

  Future<void> _pauseResumeDownload(DownloadTask task) async {
    final downloadId = task.downloadId > 0 ? task.downloadId : task.movieId;
    if (task.status == 'Downloading' || task.status == 'Waiting') {
      DownloadManager.pause(downloadId);
      return;
    }
    if (task.status == 'Paused' || task.status == 'Failed') {
      if (task.videoUrl.trim().isEmpty) {
        _showMessage('The original download URL is no longer available.');
        return;
      }
      if (mounted) {
        setState(() {
          task
            ..status = 'Downloading'
            ..errorMessage = null;
        });
      }
      await _runDownloadTask(task, resume: true);
    }
  }

  Future<void> _deleteDownload(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Delete Download?', style: TextStyle(color: white)),
        content: const Text('Are you sure you want to delete this movie?', style: TextStyle(color: ink70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true) return;
    if (task.filePath != null) {
      try {
        final file = File(task.filePath!);
        if (await file.exists()) await file.delete();
      } catch (_) {
        _showMessage('Could not delete downloaded file.');
        return;
      }
    }
    if (!mounted) return;
    setState(() => _downloads.remove(task));
    await MovieCache.saveDownloads(_downloads);
    _showMessage('Download removed from this device.');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              color: ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFF242832),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  List<Movie> _moviesForIds(Set<int> ids) {
    return _allMovies()
        .where((movie) => ids.contains(movie.id))
        .toList();
  }

  void _recordWatch(Movie movie) {
    _watchHistory.removeWhere((item) =>
        item.id == movie.id ||
        (movie.tmdbId > 0 && item.tmdbId == movie.tmdbId));
    _watchHistory.insert(0, movie);
    if (_watchHistory.length > 30) {
      _watchHistory.removeRange(30, _watchHistory.length);
    }
    unawaited(MovieCache.saveList(MovieCache.historyKey, _watchHistory));
    if (mounted) setState(() {});
  }

  void _openDownloadsTab() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!mounted) return;
    setState(() {
      _tab = 2;
      _librarySection = 'Downloads';
      _profileSection = null;
      _search = '';
      _searchController.clear();
      _searchLoading = false;
    });
  }

  void _openProfileSection(String section) {
    setState(() => _profileSection = section);
  }

  String _titleOpeningKey(Movie movie) {
    if (movie.tmdbId > 0) return '${movie.mediaType}:${movie.tmdbId}';
    return '${movie.mediaType}:${movie.source}:${movie.id}';
  }

  bool _beginTitleOpening(Movie movie) {
    if (!mounted || _isOpeningTitle) return false;
    _isOpeningTitle = true;
    _openingTitleKey = _titleOpeningKey(movie);
    setState(() {});
    return true;
  }

  void _endTitleOpening() {
    _isOpeningTitle = false;
    _openingTitleKey = null;
    if (mounted) setState(() {});
  }

  bool _isTitleOpening(Movie movie) =>
      _isOpeningTitle && _openingTitleKey == _titleOpeningKey(movie);

  Widget _titleOpeningOverlay(Movie movie) {
    if (!_isTitleOpening(movie)) return const SizedBox.shrink();
    return const ColoredBox(
      color: Color(0x99000000),
      child: Center(
        child: SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(color: gold, strokeWidth: 2.4),
        ),
      ),
    );
  }

  Movie? _cachedFlixoraMatch(Movie movie) {
    for (final candidate in [...flixoraMovies, ...searchResults]) {
      if (!candidate.isFlixora || candidate.mediaType != movie.mediaType) {
        continue;
      }
      if (CatalogSourcePolicy.isAdminBlocked(
        isAdmin: true,
        visibilityKey: _catalogVisibilityKey(candidate),
        blockedKeys: _unpublishedCatalogKeys,
      )) {
        continue;
      }
      if (movie.tmdbId > 0 && candidate.tmdbId == movie.tmdbId) {
        return candidate;
      }
      final sameTitle = _normalizedMovieTitle(candidate.title) ==
          _normalizedMovieTitle(movie.title);
      final sameYear = candidate.year == movie.year ||
          candidate.year == 'N/A' ||
          movie.year == 'N/A';
      if (sameTitle && sameYear) return candidate;
    }
    return null;
  }

  Movie? _cachedMovieBoxMatch(Movie movie) {
    if (movie.isMovieBox) return movie;
    final key = _movieBoxMatchKey(movie);
    final cached = _movieBoxMatchCache[key];
    if (cached != null) return cached.withFallbackMetadata(movie);

    final candidates = <Movie>[
      ..._movieBoxSections.expand((section) => section.items),
      ...searchResults.where((item) => item.isMovieBox),
    ];
    for (final candidate in candidates) {
      if (candidate.mediaType != movie.mediaType) continue;
      final sameTmdbId = movie.tmdbId > 0 &&
          candidate.tmdbId > 0 &&
          candidate.tmdbId == movie.tmdbId;
      final sameTitle = _normalizedMovieTitle(candidate.title) ==
          _normalizedMovieTitle(movie.title);
      final sameYear = candidate.year == movie.year ||
          candidate.year == 'N/A' ||
          movie.year == 'N/A';
      if (sameTmdbId || (sameTitle && sameYear)) {
        final resolved = candidate.withFallbackMetadata(movie);
        _movieBoxMatchCache[key] = resolved;
        return resolved;
      }
    }
    return null;
  }

  Future<Movie?> _searchMovieBoxMatch(Movie movie) async {
    if (movie.title.trim().isEmpty ||
        (movie.mediaType != 'movie' && movie.mediaType != 'tv')) {
      return null;
    }
    try {
      final result = await MovieBoxService.search(movie.title, perPage: 20)
          .timeout(const Duration(seconds: 5));
      final items = (result['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Movie.fromMovieBox(Map<String, dynamic>.from(item)))
          .where((item) => item.movieBoxId.isNotEmpty &&
              item.mediaType == movie.mediaType)
          .toList(growable: false);
      final wantedTitle = _normalizedMovieTitle(movie.title);
      for (final candidate in items) {
        final sameTmdbId = movie.tmdbId > 0 &&
            candidate.tmdbId > 0 &&
            candidate.tmdbId == movie.tmdbId;
        final sameTitle = _normalizedMovieTitle(candidate.title) == wantedTitle;
        final sameYear = candidate.year == movie.year ||
            candidate.year == 'N/A' ||
            movie.year == 'N/A';
        if (sameTmdbId || (sameTitle && sameYear)) {
          final resolved = candidate.withFallbackMetadata(movie);
          _movieBoxMatchCache[_movieBoxMatchKey(movie)] = resolved;
          return resolved;
        }
      }
    } catch (error) {
      debugPrint('MovieBox title lookup failed: $error');
    }
    return null;
  }

  /// Resolve playback from the MovieBox catalogue only. Admin/Supabase
  /// is intentionally not queried from the Visitor App playback path.
  Future<Movie?> _resolveMovieForOpening(Movie requested) async {
    final cachedMovieBox = _cachedMovieBoxMatch(requested);
    if (cachedMovieBox != null && cachedMovieBox.isMovieBox) {
      return cachedMovieBox.withFallbackMetadata(requested);
    }

    if (!_online) {
      if (requested.hasPlayableVideoUrl && !requested.isFlixora) {
        return requested;
      }
      return null;
    }

    final movieBoxMatch = await _searchMovieBoxMatch(requested)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        )
        .catchError((_) => null);
    if (movieBoxMatch != null && movieBoxMatch.isMovieBox) {
      return movieBoxMatch.withFallbackMetadata(requested);
    }

    if (requested.isFlixora) return null;
    if (requested.hasPlayableVideoUrl) return requested;
    return null;
  }

  int _archiveMovieId(String identifier) {
    var value = 0;
    for (final unit in identifier.codeUnits) {
      value = ((value * 31) + unit) & 0x7fffffff;
    }
    return value == 0 ? 1 : value;
  }

  void _openArchiveMovie(ArchiveMovie archiveMovie) {
    final videoUrl = archiveMovie.videoUrl?.trim() ?? '';
    if (videoUrl.isEmpty) return;
    final movie = Movie(
      id: _archiveMovieId(archiveMovie.identifier),
      source: 'archive',
      title: archiveMovie.title,
      year: archiveMovie.year,
      overview: archiveMovie.description,
      poster: '',
      backdrop: '',
      rating: 0,
      releaseDate: archiveMovie.year,
      videoUrl: videoUrl,
      mediaType: 'movie',
    );
    unawaited(_openMovie(movie));
  }

  Future<bool> _refreshFromOfflineScreen() async {
    if (!mounted) return false;
    InternetService.invalidateCache();
    final online = await InternetService.isOnline(forceRefresh: true);
    if (!mounted) return false;

    if (!online) {
      setState(() {
        _online = false;
        _connectionKnown = true;
        if (_allMovies().isEmpty) homeError = 'offline';
      });
      return false;
    }

    setState(() {
      _online = true;
      _connectionKnown = true;
      homeError = null;
    });
    await loadHome(forceRefresh: true);
    if (_search.trim().isNotEmpty) {
      unawaited(searchMovies(_search));
    }
    return true;
  }

  void _showNoInternetScreen() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoInternetScreen(
          onRefresh: _refreshFromOfflineScreen,
          closeOnReconnect: true,
        ),
      ),
    );
  }

  bool _hasCompletedLocalDownload(Movie movie) {
    return _downloads.any((task) {
      final matchesMovie = task.movieId == movie.id ||
          (movie.tmdbId > 0 && task.movieId == movie.tmdbId);
      return matchesMovie &&
          task.status == 'Completed' &&
          task.filePath != null &&
          File(task.filePath!).existsSync();
    });
  }

  Future<void> _openMovie(Movie movie) async {
    // Poster taps go straight to the resolved player; the MovieBox-first
    // source policy and Admin-only fallback remain in _playMovie.
    await _playMovie(movie);
  }

  Future<void> _playMovieFromPlayer(Movie movie) async {
    await _playMovie(movie, closeCurrentPlayer: true);
  }

  Future<void> _playMovie(
    Movie movie, {
    bool closeCurrentPlayer = false,
  }) async {
    if (!_beginTitleOpening(movie)) return;
    try {
      if (closeCurrentPlayer) {
        if (!mounted) return;
        Navigator.of(context).pop();
      }

      if (!_online && _hasCompletedLocalDownload(movie)) {
        await _openResolvedPlayer(movie, movie);
        return;
      }

      if (!_online) {
        final online = await InternetService.isOnline(forceRefresh: true);
        if (!mounted) return;
        setState(() {
          _online = online;
          _connectionKnown = true;
          if (!online && _allMovies().isEmpty) homeError = 'offline';
        });
        if (!online) {
          if (_hasCompletedLocalDownload(movie)) {
            await _openResolvedPlayer(movie, movie);
            return;
          }
          _showNoInternetScreen();
          return;
        }
      }

      final selectedMovie = await _resolveMovieForOpening(movie);
      if (!mounted) return;

      if (selectedMovie == null) {
        _showMessage('This title is currently unavailable.');
        return;
      }

      if (selectedMovie.isMovieBox &&
          !selectedMovie.movieBoxIsSeries &&
          !_hasCompletedLocalDownload(selectedMovie)) {
        // For movies, pre-resolve the exact stream in parallel with player
        // navigation. For series, avoid warming episode 1 when the visitor
        // may be resuming a different saved episode.
        unawaited(MovieBoxService.prewarm(
          selectedMovie.toMovieBoxMap(),
          isSeries: false,
        ));
      }
      await _openResolvedPlayer(selectedMovie, movie);
    } finally {
      _endTitleOpening();
    }
  }

  // ignore: unused_element
  Future<void> _playResolvedMovie(
    Movie selectedMovie,
    Movie requestedMovie,
  ) async {
    if (!_beginTitleOpening(selectedMovie)) return;
    try {
      await _openResolvedPlayer(selectedMovie, requestedMovie);
    } finally {
      _endTitleOpening();
    }
  }

  void _pushPlayerRoute(WidgetBuilder builder) {
    final navigator = Navigator.of(context);
    final previousRoute = _activePlayerRoute;
    final previousNavigator = _activePlayerNavigator;
    if (previousRoute != null &&
        previousNavigator != null &&
        previousNavigator.mounted &&
        previousRoute.isActive) {
      try {
        previousNavigator.removeRoute(previousRoute);
      } catch (error) {
        debugPrint('Could not replace the previous FLIXORA Player route: $error');
      }
    }

    _activeMiniPlayerState.value = null;
    final route = _NonBlockingPlayerRoute(pageBuilder: builder);
    _activePlayerNavigator = navigator;
    _activePlayerRoute = route;
    navigator.push<void>(route);
  }


  Future<void> _openResolvedPlayer(
    Movie selectedMovie,
    Movie requestedMovie,
  ) async {
    if (!mounted) return;

    DownloadTask? downloaded;
    for (final task in _downloads) {
      final matchesMovie = task.movieId == selectedMovie.id ||
          task.movieId == requestedMovie.id ||
          (selectedMovie.tmdbId > 0 &&
              task.movieId == selectedMovie.tmdbId);
      if (matchesMovie &&
          task.status == 'Completed' &&
          task.filePath != null &&
          File(task.filePath!).existsSync()) {
        downloaded = task;
        break;
      }
    }

    if (downloaded != null) {
      _recordWatch(selectedMovie);
      _pushPlayerRoute((_) => MoviePlayerScreen(
          movie: selectedMovie,
          localFilePath: downloaded!.filePath,
          localSeasonNumber: downloaded.seasonNumber,
          localEpisodeNumber: downloaded.episodeNumber,
          recommendedMovies: _allMovies(),
          onMovieSelected: _playMovieFromPlayer,
          onSave: () => _toggleSaved(selectedMovie),
          onDownload: () => addDownload(selectedMovie),
          onDownloadEpisode: (season, episode) => addDownload(
            selectedMovie,
            seasonNumber: season,
            episodeNumber: episode,
          ),
          onViewDownloads: _openDownloadsTab,
          isOnline: _online,
          enablePip: _autoMiniPlayer,
      ));
      return;
    }

    final hasInternet = _online ||
        await InternetService.isOnline(forceRefresh: true);
    if (!mounted) return;
    if (!hasInternet) {
      setState(() {
        _online = false;
        _connectionKnown = true;
      });
      _showNoInternetScreen();
      return;
    }

    if (!_online) setState(() => _online = true);

    if (!selectedMovie.canAttemptPlayback) {
      _showMessage('This title has no supported FLIXORA playback source.');
      return;
    }
    // Open the player immediately. MoviePlayerScreen resolves MovieBox
    // streams itself and shows its loading/error state without blocking Home.
    _recordWatch(selectedMovie);
    _pushPlayerRoute((_) => MoviePlayerScreen(
        movie: selectedMovie,
        recommendedMovies: _allMovies(),
        onMovieSelected: _playMovieFromPlayer,
        onSave: () => _toggleSaved(selectedMovie),
        onDownload: () => addDownload(selectedMovie),
        onDownloadEpisode: (season, episode) => addDownload(
          selectedMovie,
          seasonNumber: season,
          episodeNumber: episode,
        ),
        onViewDownloads: _openDownloadsTab,
        isOnline: _online,
          enablePip: _autoMiniPlayer,
    ));
  }

  void _openRanking([String category = 'Cinema', bool tv = false]) {
    setState(() {
      _showRanking = true;
      _rankingTv = tv;
      _rankingCategory = category;
    });
    if (!tv) unawaited(_ensureRankingMovieCatalogues());
  }

  Future<void> _ensureRankingMovieCatalogues() async {
    if (_rankingCataloguesLoading ||
        (bengaliMovies.isNotEmpty && bollywoodMovies.isNotEmpty &&
            hollywoodMovies.isNotEmpty && southIndianMovies.isNotEmpty)) {
      return;
    }
    _rankingCataloguesLoading = true;
    if (mounted) setState(() {});
    try {
      final results = await Future.wait<List<Movie>>([
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'bn', 'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'hi', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'en', 'with_origin_country': 'US',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ta', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'te', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'ml', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
        TmdbService.getMovies('discover/movie', extraParams: {
          'with_original_language': 'kn', 'with_origin_country': 'IN',
          'sort_by': 'popularity.desc',
        }).catchError((_) => <Movie>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _homeSectionCache.clear();
        bengaliMovies = _deduplicateMovies([...bengaliMovies, ...results[0]]);
        bollywoodMovies = _deduplicateMovies([...bollywoodMovies, ...results[1]]);
        hollywoodMovies = _deduplicateMovies([...hollywoodMovies, ...results[2]]);
        southIndianMovies = _deduplicateMovies([
          ...southIndianMovies, ...results[3], ...results[4], ...results[5], ...results[6],
        ]);
      });
      await Future.wait([
        MovieCache.saveList(MovieCache.bengaliMoviesKey, bengaliMovies),
        MovieCache.saveList(MovieCache.bollywoodMoviesKey, bollywoodMovies),
        MovieCache.saveList(MovieCache.hollywoodMoviesKey, hollywoodMovies),
        MovieCache.saveList(MovieCache.southIndianMoviesKey, southIndianMovies),
      ]);
    } catch (error) {
      debugPrint('Ranking movie catalogues could not be refreshed: $error');
    } finally {
      _rankingCataloguesLoading = false;
      if (mounted) setState(() {});
    }
  }

  List<Movie> _rankingMoviePool() => _deduplicateMovies([
        ..._trendingMovieCandidates(),
        ...trending, ...popular, ...latest, ...topRated,
        ...flixoraMovies.where((movie) => movie.mediaType == 'movie'),
        ...bengaliMovies, ...bollywoodMovies, ...hollywoodMovies, ...southIndianMovies,
      ]).where((movie) => movie.mediaType == 'movie').toList(growable: false);

  List<Movie> _rankingRegionalMovies(String category) => _rankingMoviePool()
      .where((movie) => _trendingMovieCategory(movie) == category)
      .toList(growable: false);

  List<String> _sectionFilterOptions(String section) {
    switch (section) {
      case 'Trending Movies':
        return const [
          'All', 'Bollywood', 'Hollywood', 'Korean', 'South Indian',
          'Bengali', 'Asian', 'International', 'Hindi Dubbed',
        ];
      case 'Popular Movies':
        return const ['Cinema', 'TOP Movies', 'New Bengali', 'Bollywood', 'Hollywood', 'South Indian', 'New Release'];
      case 'Trending TV Series':
      case 'Popular TV Series':
      case 'Top Rated TV Series':
        return const [
          'All Series', 'Top Series', 'New Bengali', 'Anime',
          'Drama', 'Web Series', 'Asian Drama', 'Indian Drama',
        ];
      case 'Anime':
        return const ['Popular', 'Action', 'Adventure', 'Fantasy', 'New Release'];
      case 'Korean & Asian Drama':
        return const ['All', 'Korean', 'Chinese', 'Japanese', 'Thai'];
      case 'Bengali Movies':
      case 'Bengali TV Series':
        return const ['All', 'New', 'Popular', 'Top Rated'];
      case 'Now Playing':
        return const ['All', 'New Release', 'Action', 'Drama'];
      case 'Top Rated Movies':
        return const ['All', 'TOP Movies', 'Bollywood', 'Hollywood', 'South Indian'];
      default:
        return const [];
    }
  }

  List<Movie> _filterSectionMovies(
    String section,
    List<Movie> source,
    String filter, {
    bool sourceIsDeduplicated = false,
  }) {
    final items = sourceIsDeduplicated ? source : _deduplicateMovies(source);

    if (section == 'Trending Movies') {
      switch (filter) {
        case 'All':
          return items
              .where((movie) => movie.mediaType == 'movie')
              .toList(growable: false);
        case 'Hindi Dubbed':
          return _deduplicateMovies([
            ..._trendingHindiDubbedMovies,
            ...items.where(_hasHindiAudio),
          ]);
        case 'Bollywood':
        case 'Hollywood':
        case 'Korean':
        case 'South Indian':
        case 'Bengali':
        case 'Asian':
        case 'International':
          // Regional tags combine the weekly-trending rail with the matching
          // regional catalogue, including current TV/web-series/drama titles.
          final regionalMovies = filter == 'Korean'
              ? _koreanTrendingMovies
              : _rankingRegionalMovies(filter);
          final regionalTv = _deduplicateMovies([
            ..._tmdbTrendingTv,
            ...trendingTv,
            ...popularTv,
            ...topRatedTv,
            ...koreanDrama,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
            ..._regularMovieBoxItems.where((title) => title.mediaType == 'tv'),
          ]).where((title) => _trendingMovieCategory(title) == filter);
          return _deduplicateMovies([
            ...items.where((movie) => _trendingMovieCategory(movie) == filter),
            ...regionalMovies,
            ...regionalTv,
          ]);
        default:
          return items
              .where((movie) => movie.mediaType == 'movie')
              .toList(growable: false);
      }
    }

    if (section.contains('TV Series')) {
      switch (filter) {
        case 'New Bengali':
          return _deduplicateMovies(bengaliTv);
        case 'Anime':
          return _deduplicateMovies([
            ...anime,
            ..._regularMovieBoxItems
                .where((title) => title.mediaType == 'tv' && _isAnimeTitle(title)),
            ...flixoraMovies.where((title) =>
                title.mediaType == 'tv' && _isAnimeTitle(title)),
          ]);
        case 'Asian Drama':
          return _deduplicateMovies(koreanDrama);
        case 'Indian Drama':
          return _deduplicateMovies(indianDramaTv);
        case 'Top Series':
          final series = _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
          return series..sort((a, b) => b.rating.compareTo(a.rating));
        case 'Drama':
          return items.where((title) => title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList();
        case 'Web Series':
          return _webSeriesTitles();
      }
    }
    if (filter == 'All' || filter == 'Cinema' || filter == 'All Series' || filter == 'Popular') {
      if (filter == 'Popular' && section == 'Anime') {
        return items.toList()..sort((a, b) => b.rating.compareTo(a.rating));
      }
      return items;
    }
    if (filter == 'TOP Movies' || filter == 'Top Series' || filter == 'Top Rated') {
      return items.toList()..sort((a, b) => b.rating.compareTo(a.rating));
    }
    if (filter == 'New Release' || filter == 'New') {
      return items.toList()..sort((a, b) => b.year.compareTo(a.year));
    }
    if (filter == 'New Bengali') return _deduplicateMovies(bengaliMovies);
    if (filter == 'Bollywood') return _deduplicateMovies(bollywoodMovies);
    if (filter == 'Hollywood') return _deduplicateMovies(hollywoodMovies);
    if (filter == 'South Indian') return _deduplicateMovies(southIndianMovies);
    if (filter == 'Anime') {
      return items.where((m) => m.genres.any((g) => g.toLowerCase().contains('animation')) || m.originalLanguage.toLowerCase() == 'ja').toList();
    }
    if (filter == 'Asian Drama') {
      return items.where((m) => ['ko', 'zh', 'ja', 'th'].contains(m.originalLanguage.toLowerCase())).toList();
    }
    if (filter == 'Indian Drama') {
      return items.where((m) => ['hi', 'bn', 'ta', 'te', 'ml', 'kn'].contains(m.originalLanguage.toLowerCase())).toList();
    }
    if (filter == 'Korean') return items.where((m) => m.originalLanguage.toLowerCase() == 'ko').toList();
    if (filter == 'Chinese') return items.where((m) => ['zh', 'cn'].contains(m.originalLanguage.toLowerCase())).toList();
    if (filter == 'Japanese') return items.where((m) => m.originalLanguage.toLowerCase() == 'ja').toList();
    if (filter == 'Thai') return items.where((m) => m.originalLanguage.toLowerCase() == 'th').toList();
    if (filter == 'Action' || filter == 'Adventure' || filter == 'Fantasy' || filter == 'Drama') {
      return items.where((m) => m.genres.any((g) => g.toLowerCase().contains(filter.toLowerCase()))).toList();
    }
    return items;
  }

  Future<List<Movie>> _loadHotShortsCatalog() async {
    if (!_online) return const <Movie>[];
    final response = await MovieBoxService.shorts(
      perPage: 24,
      maxPages: 10,
    ).timeout(const Duration(seconds: 45));
    final rawItems = response['items'] as List? ?? const [];
    return rawItems
        .whereType<Map>()
        .map((item) => Movie.fromMovieBox(
              Map<String, dynamic>.from(item),
            ))
        .where((movie) => movie.movieBoxId.isNotEmpty)
        .toList(growable: false);
  }

  void _cacheHotShortsCatalog(List<Movie> items) {
    if (!mounted || items.isEmpty) return;
    final existing = _movieBoxSections
        .where((section) => section.isHotShorts)
        .expand((section) => section.items)
        .toList(growable: false);
    final merged = _deduplicateMovies([...existing, ...items]);
    if (merged.isEmpty) return;

    final updatedSections = <MovieBoxHomeSection>[
      ..._movieBoxSections.where((section) => !section.isHotShorts),
      MovieBoxHomeSection(title: 'Hot Shorts TV', items: merged),
    ];
    for (final item in merged) {
      _movieBoxMatchCache[_movieBoxMatchKey(item)] = item;
    }
    setState(() => _movieBoxSections = updatedSections);
    unawaited(MovieCache.saveMovieBoxSections(updatedSections));
  }

  void _openHotShorts(
    List<Movie> source, {
    int initialIndex = 0,
    int? initialSeasonNumber,
    int? initialEpisodeNumber,
  }) {
    final shorts = _deduplicateMovies(
      source.where((movie) => movie.isMovieBox).toList(growable: false),
    );
    if (shorts.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HotShortsScreen(
          items: shorts,
          initialIndex: initialIndex.clamp(0, shorts.length - 1).toInt(),
          initialSeasonNumber: initialSeasonNumber,
          initialEpisodeNumber: initialEpisodeNumber,
          loadCatalogue: _online ? _loadHotShortsCatalog : null,
          onCatalogueLoaded: _cacheHotShortsCatalog,
        ),
      ),
    );
  }

  Future<void> _loadHotShortEpisodes(
    Movie movie, {
    bool forceRefresh = false,
  }) async {
    final subjectId = movie.movieBoxId;
    if (subjectId.isEmpty || !movie.movieBoxIsSeries) return;
    if (_hotShortEpisodeLoading.contains(subjectId)) return;
    if (!forceRefresh && _hotShortEpisodesById.containsKey(subjectId)) return;

    if (mounted) {
      setState(() {
        _hotShortEpisodeLoading.add(subjectId);
        _hotShortEpisodeErrors.remove(subjectId);
        if (forceRefresh) _hotShortEpisodesById.remove(subjectId);
      });
    }

    try {
      final seasons = await MovieBoxService.seasons(subjectId)
          .timeout(const Duration(seconds: 18));
      final episodes = MovieBoxShortEpisode.fromSeasons(seasons);
      if (!mounted) return;
      setState(() {
        _hotShortEpisodesById[subjectId] = episodes;
        if (episodes.isEmpty) {
          _hotShortEpisodeErrors[subjectId] =
              'No episodes are available for this short.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hotShortEpisodeErrors[subjectId] =
            'Could not load episodes. Please try again.';
      });
      debugPrint('Hot Shorts episode list failed for ${movie.title}: $error');
    } finally {
      if (mounted) {
        setState(() => _hotShortEpisodeLoading.remove(subjectId));
      }
    }
  }

  void _toggleHotShortEpisodes(Movie movie) {
    if (!movie.movieBoxIsSeries) return;
    final subjectId = movie.movieBoxId;
    if (_expandedHotShortId == subjectId) {
      setState(() => _expandedHotShortId = null);
      return;
    }
    setState(() => _expandedHotShortId = subjectId);
    unawaited(_loadHotShortEpisodes(movie));
  }

  void _openHotShortEpisode(
    List<Movie> shorts,
    Movie movie,
    MovieBoxShortEpisode episode,
  ) {
    final index = shorts.indexWhere(
      (item) => item.movieBoxId == movie.movieBoxId,
    );
    if (index < 0) return;
    _openHotShorts(
      shorts,
      initialIndex: index,
      initialSeasonNumber: episode.season,
      initialEpisodeNumber: episode.episode,
    );
  }

  Widget _hotShortEpisodesPanel(Movie movie, List<Movie> shorts) {
    final subjectId = movie.movieBoxId;
    final episodes = _hotShortEpisodesById[subjectId] ??
        const <MovieBoxShortEpisode>[];
    final loading = _hotShortEpisodeLoading.contains(subjectId);
    final error = _hotShortEpisodeErrors[subjectId];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 3),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${movie.title} · Episodes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hide episodes',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expandedHotShortId = null),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: ink60,
                    size: 19,
                  ),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: gold,
                  backgroundColor: ink12,
                ),
              )
            else if (error != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(color: ink60, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () => unawaited(
                      _loadHotShortEpisodes(movie, forceRefresh: true),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: episodes.map((episode) {
                  return ActionChip(
                    backgroundColor: const Color(0xFF303030),
                    side: const BorderSide(color: ink12),
                    label: Text(
                      episode.label,
                      style: const TextStyle(
                        color: white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () =>
                        _openHotShortEpisode(shorts, movie, episode),
                  );
                }).toList(growable: false),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hotShortsBlock(List<Movie> source) {
    final shorts = _deduplicateMovies(
      source.where((movie) => movie.isMovieBox).toList(growable: false),
    );
    if (shorts.isEmpty) return const SizedBox.shrink();

    Movie? expandedShort;
    for (final short in shorts) {
      if (short.movieBoxId == _expandedHotShortId) {
        expandedShort = short;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 22, 12, 9),
          child: Row(
            children: [
              const Icon(Icons.smart_display_rounded, color: gold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hot Shorts TV',
                      style: TextStyle(
                        color: white,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Vertical videos · Swipe up to watch next',
                      style: TextStyle(color: ink60, fontSize: 10),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _openHotShorts(shorts),
                style: TextButton.styleFrom(
                  foregroundColor: gold,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Watch',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 238,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: shorts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final movie = shorts[index];
              final imageUrl = movie.posterUrl.isNotEmpty
                  ? movie.posterUrl
                  : movie.backdropUrl;
              final expanded = _expandedHotShortId == movie.movieBoxId;
              return SizedBox(
                width: 132,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Material(
                        color: panel,
                        borderRadius: BorderRadius.circular(13),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openHotShorts(
                            shorts,
                            initialIndex: index,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (imageUrl.isNotEmpty)
                                FlixoraCachedImage(
                                  imageUrl: imageUrl,
                                  isOnline: _online,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 396,
                                  memCacheHeight: 714,
                                  placeholder: const ColoredBox(color: panel),
                                  fallback: const ColoredBox(color: panel),
                                )
                              else
                                const ColoredBox(color: panel),
                              const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x55000000),
                                      Colors.transparent,
                                      Color(0xDD000000),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 9,
                                left: 9,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: gold,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Text(
                                    'SHORTS',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                              const Center(
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Color(0xAA000000),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 9,
                                right: 9,
                                bottom: 10,
                                child: Text(
                                  movie.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: movie.movieBoxIsSeries
                          ? TextButton.icon(
                              onPressed: () => _toggleHotShortEpisodes(movie),
                              icon: Icon(
                                expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.list_alt_rounded,
                                size: 16,
                              ),
                              label: Text(
                                expanded ? 'Hide Episodes' : 'Episodes',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: gold,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 30),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            )
                          : const Center(
                              child: Text(
                                'Single Part',
                                style: TextStyle(
                                  color: ink60,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (expandedShort != null)
          _hotShortEpisodesPanel(expandedShort, shorts),
      ],
    );
  }

  int _movieListFingerprint(List<Movie> movies) => Object.hashAll([
        Object.hashAll(movies.map((movie) => Object.hashAll([
              movie.id,
              movie.tmdbId,
              movie.sourceId,
              movie.source,
              movie.title,
              movie.year,
              movie.rating,
              movie.mediaType,
              movie.originalLanguage,
              movie.originCountry,
              movie.movieBoxId,
              movie.movieBoxDetailPath,
              movie.movieBoxIsSeries,
              movie.movieBoxSubjectType,
              movie.poster,
              movie.backdrop,
              movie.overview,
              movie.releaseDate,
              movie.videoUrl,
              movie.downloadUrl,
              movie.runtime,
              Object.hashAll(movie.genres),
              Object.hashAll(movie.audioLanguages),
            ]))),
        Object.hashAll(_unpublishedCatalogKeys),
        _catalogueFingerprint(),
      ]);

  Widget _sectionBlock(String title, List<Movie> movies) {
    final fingerprint = _movieListFingerprint(movies);
    final cacheKey = title + ':' + fingerprint.toString();
    var cached = _homeSectionCache[cacheKey];
    if (cached == null) {
      final allFilters = _sectionFilterOptions(title);
      final deduplicatedMovies = _deduplicateMovies(movies);
      final filteredByOption = <String, List<Movie>>{
        for (final filter in allFilters)
          filter: _filterSectionMovies(
            title,
            deduplicatedMovies,
            filter,
            sourceIsDeduplicated: true,
          ),
      };
      final filters = title == 'Trending Movies'
          ? allFilters
          : allFilters
              .where((filter) => filteredByOption[filter]!.isNotEmpty)
              .toList(growable: false);
      cached = _CachedHomeSection(
        deduplicatedMovies: deduplicatedMovies,
        filteredByOption: filteredByOption,
        filters: filters,
      );
      if (_homeSectionCache.length >= 64) _homeSectionCache.clear();
      _homeSectionCache[cacheKey] = cached;
    }

    final filters = cached.filters;
    final selected = filters.contains(_sectionFilters[title])
        ? _sectionFilters[title]!
        : (filters.isNotEmpty ? filters.first : '');
    final visibleMovies = filters.isEmpty
        ? cached.deduplicatedMovies
        : cached.filteredByOption[selected] ?? const <Movie>[];

    // Keep Trending Movies and its filter tags visible even when a
    // selected category currently has no matching titles.
    if (visibleMovies.isEmpty && title != 'Trending Movies') {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 21, 12, 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  final isTvSection = title.contains('TV') ||
                      title == 'Anime' || title == 'Drama' ||
                      title == 'Web Series' || title == 'Korean & Asian Drama';
                  _openRanking(
                    isTvSection ? 'All Series' : 'Cinema',
                    isTvSection,
                  );
                },
                style: TextButton.styleFrom(
                  foregroundColor: gold,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(36, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text(
                  'All',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        if (filters.isNotEmpty)
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final value = filters[index];
                final active = selected == value;
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() => _sectionFilters[title] = value);
                    if (title == 'Trending Movies' && value != 'All') {
                      // Ensure regional catalogue data is loaded when a
                      // visitor selects a regional Trending Movies filter.
                      unawaited(_ensureRankingMovieCatalogues());
                    }
                  },
                  child: Center(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: active ? gold : ink60,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (visibleMovies.isEmpty && title == 'Trending Movies')
          const SizedBox(
            height: 54,
            child: Center(
              child: Text(
                'No movies available in this category.',
                style: TextStyle(color: ink54, fontSize: 12),
              ),
            ),
          )
        else
          _movieRow(visibleMovies),
      ],
    );
  }

  Widget _movieRow(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 205,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemExtent: 118,
        itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          final hasHindi = _hasHindiAudio(movie);
          return Container(
            key: ValueKey('${movie.mediaType}:${movie.tmdbId > 0 ? movie.tmdbId : movie.id}'),
            width: 110,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF17181C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF292B31), width: 0.8),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _isOpeningTitle ? null : () => _playMovie(movie),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(7),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            movie.posterUrl.isEmpty
                                ? Container(
                                    color: panel,
                                    child: const Icon(Icons.movie, color: gold, size: 32),
                                  )
                                : FlixoraCachedImage(
                                    imageUrl: movie.posterUrl,
                                    isOnline: _online,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 330,
                                    memCacheHeight: 450,
                                    placeholder: Container(color: panel),
                                    fallback: Container(
                                      color: panel,
                                      child: const Icon(Icons.movie, color: gold),
                                    ),
                                  ),
                            if (hasHindi)
                              Positioned(
                                top: 5,
                                right: 5,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xDD111216),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Hindi',
                                    style: TextStyle(
                                      color: white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      height: 39,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: const BoxDecoration(
                        color: Color(0xFF202126),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(7),
                        ),
                      ),
                      child: Text(
                        _displayTitle(movie),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _featuredSlider() {
    final slides = _homeTrendingMovies().toList(growable: false);

    if (slides.isEmpty) {
      return const SizedBox(height: 12);
    }

    // Match the supplied mobile reference: a full-width 16:9 hero with
    // a compact, overlapping horizontal poster-card strip at its bottom.
    final heroHeight = (MediaQuery.of(context).size.width * 9 / 16)
        .clamp(200.0, 360.0)
        .toDouble();
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final heroCacheWidth = (MediaQuery.sizeOf(context).width * pixelRatio)
        .round()
        .clamp(720, 1440)
        .toInt();
    final heroCacheHeight = (heroHeight * pixelRatio)
        .round()
        .clamp(450, 900)
        .toInt();

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null) {
                _lastCarouselInteractionAt = DateTime.now();
              }
              return false;
            },
            child: PageView.builder(
              controller: _sliderController,
              physics: const BouncingScrollPhysics(),
              allowImplicitScrolling: true,
              itemCount: slides.length,
              onPageChanged: (index) {
                if (_slide != index) _slide = index;
                _scrollFeaturedCardTo(index);
              },
              itemBuilder: (context, index) {
                final movie = slides[index];
                final hasLandscapeBackdrop = movie.backdrop.trim().isNotEmpty &&
                    movie.backdropUrl.isNotEmpty;
                final heroImageUrl = hasLandscapeBackdrop
                    ? movie.backdropUrl
                    : movie.posterUrl;
                // Keep every hero frame full-bleed and the same 16:9 size.
                // Poster-only titles now fill the frame instead of shrinking
                // into a small letterboxed image.
                const heroImageFit = BoxFit.cover;
                return GestureDetector(
                  onTap: _isOpeningTitle ? null : () => _playMovie(movie),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      heroImageUrl.isEmpty
                          ? const ColoredBox(color: Color(0xFF080808))
                          : ColoredBox(
                              color: const Color(0xFF080808),
                              child: FlixoraCachedImage(
                              imageUrl: heroImageUrl,
                              isOnline: _online,
                              fit: heroImageFit,
                              memCacheWidth: heroCacheWidth,
                              memCacheHeight: heroCacheHeight,
                              placeholder: Container(color: panel),
                              fallback: const ColoredBox(color: Color(0xFF080808)),
                            ),
                            ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x55000000),
                              Color(0x08000000),
                              Colors.transparent,
                              Color(0xFF080808),
                            ],
                            stops: [0, 0.28, 0.58, 1],
                          ),
                        ),
                      ),
                      _titleOpeningOverlay(movie),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 6,
            child: _featuredQuickCards(slides),
          ),
        ],
      ),
    );
  }

  Widget _featuredQuickCards(List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: FeaturedCarouselLayout.cardHeight,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _lastCarouselInteractionAt = DateTime.now();
          }
          if (notification is ScrollEndNotification &&
              notification.metrics.axis == Axis.horizontal &&
              _sliderController.hasClients) {
            final selected = FeaturedCarouselLayout.indexForScrollOffset(
              pixels: notification.metrics.pixels,
              viewportWidth: notification.metrics.viewportDimension,
              itemCount: movies.length,
            );
            if (selected != _slide) {
              _sliderController.animateToPage(
                selected,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
              );
            }
          }
          return false;
        },
        child: ListView.builder(
          controller: _featuredCardsController,
          physics: const BouncingScrollPhysics(),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: FeaturedCarouselLayout.horizontalPadding,
          ),
          itemCount: movies.length,
          itemBuilder: (context, index) {
            final movie = movies[index];
            final isAnime = movie.genres.any(
                  (genre) => genre.toLowerCase().contains('animation'),
                ) ||
                movie.originalLanguage.toLowerCase() == 'ja';
            final typeLabel = movie.mediaType == 'tv'
                ? 'TV'
                : (isAnime ? 'Anime' : 'Movie');
            final hasHindiAudio = movie.audioLanguages.any((language) {
                  final value = language.trim().toLowerCase();
                  return value == 'hi' || value.contains('hindi');
                }) ||
                movie.originalLanguage.toLowerCase() == 'hi';
            final displayTitle = hasHindiAudio &&
                    !movie.title.toLowerCase().contains('[hindi]')
                ? '${movie.title} [Hindi]'
                : movie.title;
            final yearLabel = movie.year.isNotEmpty && movie.year != 'N/A'
                ? movie.year
                : (movie.releaseDate.length >= 4
                    ? movie.releaseDate.substring(0, 4)
                    : '');
            final genreLabel =
                movie.genres.isNotEmpty ? movie.genres.first : typeLabel;
            final metadataLabel = <String>[
              if (yearLabel.isNotEmpty) yearLabel,
              if (genreLabel.isNotEmpty) genreLabel,
            ].join(' | ');

            return GestureDetector(
              key: ValueKey('featured:${movie.mediaType}:${movie.tmdbId > 0 ? movie.tmdbId : movie.id}'),
              onTap: _isOpeningTitle ? null : () => _playMovie(movie),
              child: Container(
                width: FeaturedCarouselLayout.cardWidth,
                margin: const EdgeInsets.symmetric(
                  horizontal: FeaturedCarouselLayout.cardMargin,
                ),
                child: SizedBox(
                  height: FeaturedCarouselLayout.cardHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: FeaturedCarouselLayout.cardTopInset,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.only(
                            left: FeaturedCarouselLayout.textLeftInset,
                            right: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25272D),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Icon(
                                          movie.mediaType == 'tv'
                                              ? Icons.live_tv_rounded
                                              : Icons.movie_outlined,
                                          color: ink60,
                                          size: 11,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            metadataLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: ink60,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              IconButton(
                                onPressed: _isOpeningTitle
                                    ? null
                                    : () => _playMovie(movie),
                                tooltip: 'Play ${movie.title}',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 34,
                                  height: 34,
                                ),
                                icon: const CircleAvatar(
                                  radius: 15,
                                  backgroundColor: gold,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Color(0xFF151515),
                                    size: 21,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        top: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: FeaturedCarouselLayout.posterWidth,
                            height: FeaturedCarouselLayout.posterHeight,
                            child: movie.posterUrl.isEmpty
                                ? Container(
                                    color: const Color(0xFF292929),
                                    child: const Icon(
                                      Icons.movie,
                                      color: gold,
                                      size: 18,
                                    ),
                                  )
                                : ColoredBox(
                                    color: const Color(0xFF111111),
                                    child: FlixoraCachedImage(
                                    imageUrl: movie.posterUrl,
                                    isOnline: _online,
                                    fit: BoxFit.contain,
                                    memCacheWidth:
                                        (FeaturedCarouselLayout.posterWidth * 3).round(),
                                    memCacheHeight:
                                        (FeaturedCarouselLayout.posterHeight * 3).round(),
                                    placeholder: Container(
                                      color: const Color(0xFF292929),
                                    ),
                                    fallback: Container(
                                      color: const Color(0xFF292929),
                                      child: const Icon(
                                        Icons.movie,
                                        color: gold,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _homeCategory = 'Trending';
  final Map<String, String> _sectionFilters = {};

  List<Movie> _moviesForHomeCategory(String category) {
    switch (category) {
      case 'Trending':
        return _deduplicateMovies([
          ...flixoraMovies,
          ..._regularMovieBoxItems,
          ...trending,
          ...trendingTv,
        ]);
      case 'Movies':
        return _deduplicateMovies([
          ...flixoraMovies,
          ..._regularMovieBoxItems,
          ...trending, ...popular, ...latest, ...topRated,
        ].where((movie) => movie.mediaType == 'movie').toList());
      case 'TV Series':
        return _deduplicateMovies([
          ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ..._regularMovieBoxItems
              .where((title) => title.mediaType == 'tv'),
          ...trendingTv, ...popularTv, ...topRatedTv, ...koreanDrama, ...bengaliTv,
        ]);
      case 'Anime':
        return _deduplicateMovies([
          ...flixoraMovies.where(_isAnimeTitle),
          ..._regularMovieBoxItems
              .where(_isAnimeTitle),
          ...anime,
        ]);
      case 'Korean Drama':
        return _deduplicateMovies([
          ...flixoraMovies.where((title) =>
              title.mediaType == 'tv' &&
              title.originalLanguage.toLowerCase() == 'ko'),
          ..._regularMovieBoxItems.where((title) =>
              title.mediaType == 'tv' &&
              (title.originCountry.toLowerCase().contains('korea') ||
               title.originCountry.toUpperCase().contains('KR'))),
          ...koreanDrama,
        ]);
      case 'Bengali':
        return _deduplicateMovies([
          ...flixoraMovies.where((title) =>
              title.originalLanguage.toLowerCase() == 'bn' ||
              title.originCountry.toUpperCase().contains('BD')),
          ..._regularMovieBoxItems.where((title) =>
              title.originCountry.toUpperCase().contains('BD') ||
              title.originCountry.toLowerCase().contains('bangladesh')),
          ...bengaliMovies, ...bengaliTv,
        ]);
      case 'Bengali Movies':
        return _deduplicateMovies([
          ...flixoraMovies.where((title) =>
              title.mediaType == 'movie' &&
              (title.originalLanguage.toLowerCase() == 'bn' ||
               title.originCountry.toUpperCase().contains('BD'))),
          ..._regularMovieBoxItems.where((title) =>
              title.mediaType == 'movie' &&
              (title.originCountry.toUpperCase().contains('BD') ||
               title.originCountry.toLowerCase().contains('bangladesh'))),
          ...bengaliMovies,
        ]);
      case 'Drama':
        return _deduplicateMovies(_allMovies().where((title) =>
            title.genres.any((genre) =>
                genre.toLowerCase().contains('drama'))).toList());
      default:
        return [];
    }
  }

  void _scrollFeaturedCardTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_featuredCardsController.hasClients) return;
      final position = _featuredCardsController.position;
      if (!position.hasContentDimensions) return;
      final target = FeaturedCarouselLayout.targetScrollOffset(
        index: index,
        viewportWidth: position.viewportDimension,
        maxScrollExtent: position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() < 1) return;
      _featuredCardsController.animateTo(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _syncFeaturedCarouselAfterDataChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visibleCount = _homeTrendingMovies().length;
      if (visibleCount == 0) {
        if (_sliderController.hasClients) _sliderController.jumpToPage(0);
        if (_featuredCardsController.hasClients) _featuredCardsController.jumpTo(0);
        return;
      }
      final currentPage = _sliderController.hasClients
          ? (_sliderController.page?.round() ?? 0)
          : 0;
      if (currentPage >= visibleCount) {
        _slide = 0;
        if (_sliderController.hasClients) _sliderController.jumpToPage(0);
        if (_featuredCardsController.hasClients) _featuredCardsController.jumpTo(0);
        return;
      }
      final selectedIndex = _slide.clamp(0, visibleCount - 1).toInt();
      _slide = selectedIndex;
      _scrollFeaturedCardTo(selectedIndex);
    });
  }

  bool _hasHindiAudio(Movie movie) {
    return TrendingMovieEligibility.hasHindiAudioVariant(movie.audioLanguages) ||
        movie.originalLanguage.toLowerCase() == 'hi';
  }

  String _displayTitle(Movie movie) {
    if (_hasHindiAudio(movie) &&
        !movie.title.toLowerCase().contains('[hindi]')) {
      return '${movie.title} [Hindi]';
    }
    return movie.title;
  }

  List<Movie> _searchDiscoveryMovies() {
    final titles = List<Movie>.of(_allMovies());
    titles.sort((a, b) {
      final rating = b.rating.compareTo(a.rating);
      return rating != 0 ? rating : b.year.compareTo(a.year);
    });
    return titles;
  }

  List<Movie> _searchSuggestions() {
    final titles = _deduplicateMovies([
      ...trending,
      ...popular,
      ...trendingTv,
      ...popularTv,
      ...flixoraMovies,
    ]);
    if (titles.isEmpty) return _searchDiscoveryMovies().take(4).toList();
    return titles.take(4).toList();
  }

  List<Movie> _filterSearchMovies(List<Movie> source, String category) {
    switch (category) {
      case 'Movies':
        return source.where((movie) => movie.mediaType == 'movie').toList();
      case 'Series':
        return source.where((movie) =>
            movie.mediaType == 'tv' && !_isAnimeTitle(movie)).toList();
      case 'Anime':
        return source.where(_isAnimeTitle).toList();
      case 'Drama':
        return source.where((movie) => movie.genres.any(
          (genre) => genre.toLowerCase().contains('drama'),
        )).toList();
      case 'Bengali':
        return source.where((movie) =>
            movie.originalLanguage.toLowerCase() == 'bn' ||
            movie.originCountry.toUpperCase().contains('BD')).toList();
      default:
        return source;
    }
  }

  List<String> _availableSearchFilters(List<Movie> source) {
    const filters = ['All', 'Movies', 'Series', 'Anime', 'Drama', 'Bengali'];
    return filters.where((filter) =>
        filter == 'All' || _filterSearchMovies(source, filter).isNotEmpty
    ).toList();
  }

  Future<void> _openSearch() async {
    if (_searchOpen) {
      _searchFocusNode.requestFocus();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _tab = 0;
      _showRanking = false;
      _searchOpen = true;
      _search = '';
      _searchCategory = 'All';
      searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchController.clear();
    });

    // Focus immediately; connection monitoring runs independently.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchRequestToken++;
    _searchTimer?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchOpen = false;
      _search = '';
      _searchCategory = 'All';
      searchResults = [];
      _searchError = null;
      _searchLoading = false;
      _searchController.clear();
    });
  }

  Future<void> _saveSearchHistory(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;

    final updated = <String>[
      query,
      ..._searchHistory.where(
        (item) => item.toLowerCase() != query.toLowerCase(),
      ),
    ].take(20).toList(growable: false);

    if (mounted) setState(() => _searchHistory = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryPrefsKey, updated);
  }

  Future<void> _removeSearchHistory(String value) async {
    final updated = _searchHistory
        .where((item) => item.toLowerCase() != value.toLowerCase())
        .toList(growable: false);
    if (mounted) setState(() => _searchHistory = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_searchHistoryPrefsKey, updated);
  }

  Widget _searchHistoryBlock() {
    final items = _searchHistory.take(10).toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 3, bottom: 5),
            child: Text(
              'Search History',
              style: TextStyle(
                color: white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...items.map((query) => SizedBox(
                height: 39,
                child: Row(
                  children: [
                    const Icon(
                      Icons.history_rounded,
                      color: ink60,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _searchForTitle(query),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: white,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove search history item',
                      onPressed: () => _removeSearchHistory(query),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: ink60,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _searchForTitle(String title) async {
    if (!_searchOpen) await _openSearch();
    if (!mounted) return;
    unawaited(_saveSearchHistory(title));
    _searchController.text = title;
    _searchController.selection = TextSelection.collapsed(
      offset: title.length,
    );
    _onSearchChanged(title);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  Widget _searchResultRow(Movie movie, {int? rank}) {
    final metadata = <String>[
      if (movie.rating > 0) movie.rating.toStringAsFixed(1),
      if (movie.year.isNotEmpty && movie.year != 'N/A') movie.year,
      if (movie.originCountry.isNotEmpty) movie.originCountry,
      if (movie.genres.isNotEmpty) movie.genres.first,
    ].join(' | ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: const Color(0xFF15161A),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _isOpeningTitle ? null : () => _playMovie(movie),
          child: SizedBox(
            height: 94,
            child: Row(
              children: [
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 62,
                    height: 82,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        movie.posterUrl.isEmpty
                            ? Container(
                                color: panel,
                                child: const Icon(Icons.movie, color: gold),
                              )
                            : FlixoraCachedImage(
                                imageUrl: movie.posterUrl,
                                isOnline: _online,
                                fit: BoxFit.cover,
                                memCacheWidth: 186,
                                memCacheHeight: 246,
                                fallback: Container(
                                  color: panel,
                                  child: const Icon(Icons.movie, color: gold),
                                ),
                              ),
                        if (rank != null)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: const BoxDecoration(
                                color: gold,
                                borderRadius: BorderRadius.only(
                                  bottomRight: Radius.circular(6),
                                ),
                              ),
                              child: Text(
                                '$rank',
                                style: const TextStyle(
                                  color: Color(0xFF171717),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        if (_hasHindiAudio(movie))
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: const Color(0xCC111216),
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: const Text(
                                'Hindi',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _displayTitle(movie),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Icon(
                              movie.mediaType == 'tv'
                                  ? Icons.live_tv_rounded
                                  : Icons.movie_creation_outlined,
                              color: ink60,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            if (movie.rating > 0) ...[
                              const Icon(
                                Icons.star_rounded,
                                color: premiumGold,
                                size: 14,
                              ),
                              const SizedBox(width: 2),
                            ],
                            Expanded(
                              child: Text(
                                metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: ink60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Play ${movie.title}',
                  onPressed: _isOpeningTitle ? null : () => _playMovie(movie),
                  icon: const CircleAvatar(
                    radius: 15,
                    backgroundColor: gold,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFF151515),
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchLandingContent() {
    final discovery = _searchDiscoveryMovies();
    final suggestions = _searchSuggestions();
    final filters = _availableSearchFilters(discovery);
    final selected = filters.contains(_searchCategory)
        ? _searchCategory
        : 'All';
    final visible = _filterSearchMovies(discovery, selected)
        .take(16)
        .toList();

    return ListView(
      key: const PageStorageKey<String>('flixora-search-landing'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        _searchHistoryBlock(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 16, 10),
          child: Text(
            '🔥 Everyone is searching',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((movie) {
              return ActionChip(
                backgroundColor: const Color(0xFF25262B),
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(
                    _displayTitle(movie),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                onPressed: () => _searchForTitle(movie.title),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        _searchFilterBar(discovery),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Trending now',
            style: TextStyle(
              color: white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No titles available yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ink60),
            ),
          )
        else
          ...List.generate(
            visible.length,
            (index) => _searchResultRow(visible[index], rank: index + 1),
          ),
      ],
    );
  }

  Widget _searchFilterBar(List<Movie> source) {
    final filters = _availableSearchFilters(source);
    final selected = filters.contains(_searchCategory)
        ? _searchCategory
        : 'All';
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final active = filter == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _searchCategory = filter),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 2, bottom: 5),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? gold : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: active ? white : ink60,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF3B3C40),
              borderRadius: BorderRadius.circular(9),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              readOnly: !_searchOpen,
              autofocus: _searchOpen,
              onTap: _openSearch,
              onChanged: _onSearchChanged,
              onSubmitted: (value) {
                _searchTimer?.cancel();
                FocusScope.of(context).unfocus();
                unawaited(_saveSearchHistory(value));
                searchMovies(value);
              },
              style: const TextStyle(color: white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search movies, series & anime...',
                hintStyle: const TextStyle(
                  color: ink70,
                  fontSize: 13,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: white,
                  size: 22,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                          if (_searchOpen) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _searchFocusNode.requestFocus();
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: ink70,
                          size: 18,
                        ),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 8,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        TextButton(
          onPressed: () {
            if (!_searchOpen) {
              _openSearch();
              return;
            }
            _searchTimer?.cancel();
            FocusScope.of(context).unfocus();
            final query = _searchController.text;
            unawaited(_saveSearchHistory(query));
            _onSearchChanged(query);
          },
          style: TextButton.styleFrom(
            foregroundColor: gold,
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text(
            'Search',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _homeTopCategories() {
    const categories = [
      'Trending', 'Movies', 'TV Series', 'Anime', 'Drama',
      'Bengali', 'Bengali Movies', 'Korean Drama',
    ];
    final available = categories.where(
      (category) => _moviesForHomeCategory(category).isNotEmpty,
    ).toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: available.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final category = available[index];
          final selected = category == _homeCategory;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _homeCategory = category),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  color: selected ? white : ink60,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
                child: Text(category),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _homeCategoryCards() {
    const routes = <String, String>{
      'All': 'Trending',
      'All Movies': 'Movies',
      'All Dramas': 'Drama',
      'Bengali Movies': 'Bengali Movies',
      'Anime': 'Anime',
    };
    final available = routes.entries.where(
      (entry) => _moviesForHomeCategory(entry.value).isNotEmpty,
    ).toList();
    if (available.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 22, 16, 10),
          child: Text(
            'Categories',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: available.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final entry = available[index];
              final titles = _moviesForHomeCategory(entry.value);
              final image = titles.firstWhere(
                (movie) => movie.backdropUrl.isNotEmpty ||
                    movie.posterUrl.isNotEmpty,
                orElse: () => titles.first,
              );
              final imageUrl = image.backdropUrl.isNotEmpty
                  ? image.backdropUrl
                  : image.posterUrl;
              return Material(
                color: panel,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _homeCategory = entry.value),
                  child: SizedBox(
                    width: 145,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (imageUrl.isNotEmpty)
                            FlixoraCachedImage(
                              imageUrl: imageUrl,
                              isOnline: _online,
                              fit: BoxFit.cover,
                              memCacheWidth: 435,
                              memCacheHeight: 228,
                              fallback: const ColoredBox(color: panel),
                            )
                          else
                            const ColoredBox(color: panel),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xAA080808),
                                  Color(0x33080808),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                entry.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Movie> _gemsForYou() {
    final fingerprint = _catalogueFingerprint();
    final cached = _gemsForYouCache;
    if (cached != null && _gemsForYouCacheFingerprint == fingerprint) {
      return cached;
    }

    final titles = _deduplicateMovies([
      ...flixoraMovies,
      ...trending,
      ...popular,
      ...topRated,
      ...trendingTv,
      ...popularTv,
      ...anime,
      ...koreanDrama,
      ..._regularMovieBoxItems,
    ]);
    titles.sort((a, b) => b.rating.compareTo(a.rating));
    final result = titles.take(14).toList(growable: false);
    _gemsForYouCacheFingerprint = fingerprint;
    _gemsForYouCache = result;
    return result;
  }

  Widget _homeContent() {
    if (_homeCategory != 'Trending') {
      final movies = _moviesForHomeCategory(_homeCategory);
      return Column(
        children: [
          _homeTopCategories(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(child: Text(
                  _homeCategory,
                  style: const TextStyle(
                    color: white, fontSize: 20, fontWeight: FontWeight.bold,
                  ),
                )),
                TextButton(onPressed: () => setState(() => _homeCategory = 'Trending'), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact), child: const Text('Show all', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
              ],
            ),
          ),
          Expanded(child: _collectionContent(_homeCategory, movies)),
        ],
      );
    }

    final movieBoxSections = _movieBoxSections
        .where((section) =>
            (!section.isBanner ||
                section.title.toLowerCase().contains('coming soon')) &&
            !section.title.toLowerCase().contains('trending') &&
            !section.isFlixoraOriginal &&
            !section.isHotShorts)
        .toList(growable: false);
    final movieBoxSectionWidgets = <Widget>[];
    var hotShortsInserted = false;
    for (final section in movieBoxSections) {
      movieBoxSectionWidgets.add(
        _sectionBlock(section.title, _movieBoxSectionItems(section)),
      );
      if (!hotShortsInserted &&
          section.title.toLowerCase().contains('coming soon')) {
        if (_hotShortsSection != null) {
          movieBoxSectionWidgets.add(
            _hotShortsBlock(_hotShortsSection!.items),
          );
        }
        hotShortsInserted = true;
      }
    }
    if (!hotShortsInserted && _hotShortsSection != null) {
      movieBoxSectionWidgets.add(
        _hotShortsBlock(_hotShortsSection!.items),
      );
    }

    return RefreshIndicator(
      color: gold,
      backgroundColor: panel,
      onRefresh: () => loadHome(forceRefresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              (notification is ScrollStartNotification ||
                  notification is ScrollUpdateNotification)) {
            _lastHomeScrollAt = DateTime.now();
          }
          return false;
        },
        child: ListView(
        key: const PageStorageKey<String>('flixora-home-trending'),
        cacheExtent: 320,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          _homeTopCategories(),
          RepaintBoundary(child: _featuredSlider()),
          _sectionBlock('Trending Movies', _trendingHomeCandidates()),
          _pakistaniDramaBlock(),
          _sectionBlock('Trending TV Series', _deduplicateMovies([
            ..._regularMovieBoxItems
                .where((title) => title.mediaType == 'tv'),
            ...trendingTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
          _sectionBlock('Chinese Drama', _chineseDramaTitles()),
          ...movieBoxSectionWidgets,
          _homeCategoryCards(),
          _sectionBlock('Gems for you', _gemsForYou()),
          _sectionBlock('Drama', _deduplicateMovies([
            ...trendingTv, ...popularTv, ...topRatedTv,
            ...bengaliTv, ...koreanDrama, ...indianDramaTv, ...flixoraMovies,
            ..._regularMovieBoxItems,
          ]).where((title) => title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList()),
          _sectionBlock('Web Series', _webSeriesTitles()),
          _sectionBlock('Anime', _deduplicateMovies([
            ...anime,
            ..._regularMovieBoxItems
                .where(_isAnimeTitle),
            ...flixoraMovies.where(_isAnimeTitle),
          ])),
          _sectionBlock('Korean & Asian Drama', koreanDrama),
          _sectionBlock('Bengali Movies', bengaliMovies),
          _sectionBlock('Bengali TV Series', bengaliTv),
          _sectionBlock('Popular Movies', _withoutFlixoraDuplicates(popular)),
          _sectionBlock('Popular TV Series', _deduplicateMovies([
            ...popularTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
          _sectionBlock('Now Playing', _withoutFlixoraDuplicates(latest)),
          _sectionBlock('Top Rated Movies', _withoutFlixoraDuplicates(topRated)),
          _sectionBlock('Top Rated TV Series', _deduplicateMovies([
            ...topRatedTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ])),
          const SizedBox(height: 25),
        ],
        ),
      ),
    );
  }

  Widget _collectionContent(String title, List<Movie> movies) {
    if (movies.isEmpty) {
      return Center(
        child: Text(
          'No $title available.',
          style: const TextStyle(color: ink54),
        ),
      );
    }

    return GridView.builder(
      key: PageStorageKey<String>('flixora-home-collection-$title'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.60,
        crossAxisSpacing: 9,
        mainAxisSpacing: 12,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return Container(
          key: ValueKey('collection:${movie.mediaType}:${movie.tmdbId > 0 ? movie.tmdbId : movie.id}'),
          decoration: BoxDecoration(
            color: const Color(0xFF17181C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF292B31), width: 0.8),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _isOpeningTitle ? null : () => _playMovie(movie),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          movie.posterUrl.isEmpty
                              ? Container(
                                  color: panel,
                                  child: const Icon(Icons.movie, color: gold),
                                )
                              : FlixoraCachedImage(
                                  imageUrl: movie.posterUrl,
                                  isOnline: _online,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 300,
                                  memCacheHeight: 450,
                                  fallback: Container(
                                    color: panel,
                                    child: const Icon(Icons.movie, color: gold),
                                  ),
                                ),
                          if (_hasHindiAudio(movie))
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xDD111216),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Hindi',
                                  style: TextStyle(
                                    color: white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    height: 38,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: const BoxDecoration(
                      color: Color(0xFF202126),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(7),
                      ),
                    ),
                    child: Text(
                      _displayTitle(movie),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: white,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _searchContent() {
    final filters = _availableSearchFilters(searchResults);
    final selected = filters.contains(_searchCategory)
        ? _searchCategory
        : 'All';
    final filtered = _filterSearchMovies(searchResults, selected);
    return Column(
      children: [
        _searchFilterBar(searchResults),
        if (_searchLoading && searchResults.isNotEmpty)
          const LinearProgressIndicator(
            minHeight: 2,
            color: gold,
            backgroundColor: panel,
          ),
        Expanded(
          child: _searchLoading && searchResults.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: gold),
                )
              : searchResults.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searchError ?? 'No results found.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ink60),
                        ),
                      ),
                    )
                  : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No titles in this category.',
                            style: TextStyle(color: ink60),
                          ),
                        )
                      : ListView.builder(
                          key: const PageStorageKey<String>('flixora-search-results'),
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 4, bottom: 18),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) =>
                              _searchResultRow(filtered[index]),
                        ),
        ),
      ],
    );
  }

  Widget _downloadsContent() {
    return DownloadsScreen(
      tasks: _downloads,
      onDelete: _deleteDownload,
      onPauseResume: _pauseResumeDownload,
      onPlay: (task) {
        if (task.filePath == null) return;
        final movie = Movie(
          id: task.movieId,
          title: task.displayTitle,
          year: 'N/A',
          overview: '',
          poster: task.poster,
          backdrop: task.poster,
          rating: 0,
          releaseDate: '',
          videoUrl: task.filePath!,
        );
        _pushPlayerRoute((_) => MoviePlayerScreen(
            movie: movie,
            localFilePath: task.filePath,
            recommendedMovies: _allMovies(),
            onMovieSelected: _openMovie,
            isOnline: _online,
            enablePip: _autoMiniPlayer,
          ));
      },
    );
  }


  Widget _libraryContent() {
    const sections = ['Downloads', 'My List', 'Favourites', 'History'];
    Widget content;
    switch (_librarySection) {
      case 'My List':
        content = _collectionContent('My List', _moviesForIds(_saved));
        break;
      case 'Favourites':
        content = _collectionContent('Favourites', _moviesForIds(_favourites));
        break;
      case 'History':
        content = _watchHistoryPage();
        break;
      case 'Downloads':
      default:
        content = _downloadsContent();
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Text(
            'Everything you keep, in one place.',
            style: TextStyle(color: ink60, fontSize: 13),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            scrollDirection: Axis.horizontal,
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final section = sections[index];
              final selected = section == _librarySection;
              return ChoiceChip(
                label: Text(section),
                selected: selected,
                onSelected: (_) => setState(() => _librarySection = section),
                selectedColor: gold,
                backgroundColor: panel,
                side: BorderSide(color: selected ? gold : ink24),
                labelStyle: TextStyle(
                  color: selected ? white : ink70,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              );
            },
          ),
        ),
        Expanded(child: content),
      ],
    );
  }

  Widget _profileContent() {
    final user = supabaseClient?.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 29,
              backgroundColor: panel,
              child: Icon(Icons.person, color: gold, size: 32),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.email ?? 'FLIXORA Visitor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: white, fontSize: 17, fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user == null ? 'Sign in to sync your account' : 'Visitor account',
                    style: const TextStyle(color: ink54, fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: user == null ? _showVisitorLogin : _signOutVisitor,
              child: Text(user == null ? 'Login / Sign Up' : 'Logout'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: [
              _cineProfileStat('WATCHED', _watchHistory.length.toString()),
              _cineProfileDivider(),
              _cineProfileStat('MY LIST', _saved.length.toString()),
              _cineProfileDivider(),
              _cineProfileStat(
                'DOWNLOADS',
                _downloads.where((task) => task.status == 'Completed').length.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _profileGroup([
          _profileTile(Icons.card_giftcard, 'Rewards Center',
              () => _openProfileSection('Rewards Center')),
        ]),
        const SizedBox(height: 12),
        _watchHistoryPreview(),
        const SizedBox(height: 12),
        _profileGroup([
          _profileTile(Icons.bookmark_outline, 'My List',
              () => _openProfileSection('My List'),
              trailingText: '${_saved.length}'),
          _profileTile(Icons.favorite_outline, 'My Favourites',
              () => _openProfileSection('My Favourites'),
              trailingText: '${_favourites.length}'),
          _profileTile(Icons.notifications_none, 'Messages',
              () => _openProfileSection('Messages'),
              trailing: const Icon(Icons.chevron_right, color: ink54)),
          _profileTile(Icons.live_tv_outlined, 'TV Download & Web Link',
              () => _openProfileSection('TV Download & Web Link'),
              trailing: const Text('NEW', style: TextStyle(
                color: white, backgroundColor: Colors.red, fontSize: 10,
              ))),
        ]),
        const SizedBox(height: 14),
        _profileGroup([
          _profileTile(Icons.groups_outlined, 'Community',
              () => _openProfileSection('Community')),
          _profileTile(Icons.chat_bubble_outline, 'My Activity',
              () => _openProfileSection('My Activity')),
        ]),
        const SizedBox(height: 14),
        _profileGroup([
          _profileTile(Icons.settings_outlined, 'Settings',
              () => _openProfileSection('Settings')),
          _profileTile(Icons.lock_outline, 'Parental PIN',
              _showParentalPinDialog, trailingText: 'Set up'),
          _profileTile(Icons.school_outlined, 'Study Mode',
              _toggleStudyMode, trailingText: _studyMode ? 'On' : 'Off'),
          _profileTile(Icons.feedback_outlined, 'Feedback', () {
            Share.share('I would like to share feedback about FLIXORA.');
          }),
        ]),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            'FLIXORA  •  Movies, made simple.',
            style: TextStyle(color: ink38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _cineProfileStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: gold,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: ink54,
              fontSize: 9,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cineProfileDivider() {
    return Container(width: 1, height: 34, color: ink12);
  }

  Widget _watchHistoryPreview() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 2, 10),
        child: Row(children: [
          const Icon(Icons.history, color: ink70, size: 20),
          const SizedBox(width: 9),
          const Expanded(child: Text('Watch History', style: TextStyle(color: white, fontSize: 17, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))),
          Text('${_watchHistory.length}', style: const TextStyle(color: ink54)),
          IconButton(tooltip: 'View all watch history', onPressed: () => _openProfileSection('Watch History'), icon: const Icon(Icons.chevron_right, color: ink70, size: 25)),
        ]),
      ),
      if (_watchHistory.isEmpty)
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 12), child: Text('Movies you play will appear here.', style: TextStyle(color: ink54)))
      else
        SizedBox(height: 112, child: ListView.separated(
          scrollDirection: Axis.horizontal, itemCount: _watchHistory.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final movie = _watchHistory[index];
            final image = movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
            return GestureDetector(onTap: () => _playMovie(movie), child: SizedBox(width: 148, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 148, height: 78, child: FlixoraCachedImage(imageUrl: image, isOnline: _online))),
              const SizedBox(height: 5),
              Text(movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 12, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
            ])));
          },
        )),
    ]);
  }

  Future<int?> _watchProgressPercent(Movie movie) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = movie.tmdbId > 0 ? movie.tmdbId : movie.id.abs();
      final resumeKey = 'flixora_resume_${movie.mediaType}_$id';
      final recentKey = 'flixora_recent_resume_${movie.mediaType}_$id';

      int readMilliseconds(String key) {
        final precise = prefs.getInt('${key}_ms');
        return precise ?? ((prefs.getInt(key) ?? 0) * 1000);
      }

      int readDurationMilliseconds(String key) {
        final precise = prefs.getInt('${key}_duration_ms');
        return precise ??
            ((prefs.getInt('${key}_duration') ?? 0) * 1000);
      }

      var position = readMilliseconds(recentKey);
      var duration = readDurationMilliseconds(recentKey);
      if (position <= 0 || duration <= 0) {
        position = readMilliseconds(resumeKey);
        duration = readDurationMilliseconds(resumeKey);
      }
      if (position <= 0 || duration <= 0) {
        final episodePrefix = 'flixora_resume_${movie.mediaType}_${id}_s';
        var bestProgress = 0;
        for (final key in prefs.getKeys()) {
          if (!key.startsWith(episodePrefix) ||
              key.endsWith('_duration') ||
              key.endsWith('_ms') ||
              key.endsWith('_duration_ms')) {
            continue;
          }
          final episodePosition = readMilliseconds(key);
          final episodeDuration = readDurationMilliseconds(key);
          if (episodePosition <= 0 || episodeDuration <= 0) continue;
          final percent = ((episodePosition / episodeDuration) * 100)
              .round()
              .clamp(0, 100);
          if (percent > bestProgress) bestProgress = percent;
        }
        if (bestProgress > 0) return bestProgress;
        return 0;
      }
      return ((position / duration) * 100).round().clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  Widget _watchHistoryPage() {
    if (_watchHistory.isEmpty) return _profileMessagePage(Icons.history, 'No watch history yet', 'Movies you start watching will appear here.');
    return ListView.separated(
      key: const PageStorageKey<String>('flixora-watch-history-list'),
      primary: true,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 104),
      itemCount: _watchHistory.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final movie = _watchHistory[index];
        final image = movie.backdropUrl.isNotEmpty ? movie.backdropUrl : movie.posterUrl;
        return InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => _playMovie(movie),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 116, height: 78, child: Stack(fit: StackFit.expand, children: [
              FlixoraCachedImage(imageUrl: image, isOnline: _online),
              Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), color: Colors.black54, child: Text(movie.year, style: const TextStyle(color: white, fontSize: 10, fontWeight: FontWeight.bold)))),
            ]))),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(movie.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 15, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic)),
              const SizedBox(height: 7),
              FutureBuilder<int?>(
                future: _watchProgressPercent(movie),
                builder: (context, snapshot) {
                  final progress = snapshot.data ?? 0;
                  return Text(
                    '$progress% watched',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink60,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                    ),
                  );
                },
              ),
            ])),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: ink60), color: panel,
              onSelected: (value) async {
                if (value == 'remove') {
                  setState(() => _watchHistory.removeWhere((item) =>
                      item.id == movie.id ||
                      (movie.tmdbId > 0 && item.tmdbId == movie.tmdbId)));
                  await MovieCache.saveList(MovieCache.historyKey, _watchHistory);
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove from history'))],
            ),
            IconButton(tooltip: 'Play', onPressed: () => _playMovie(movie), icon: const CircleAvatar(radius: 17, backgroundColor: ink70, child: Icon(Icons.play_arrow, color: Colors.white, size: 21))),
          ]),
        );
      },
    );
  }

  Widget _profileGroup(List<Widget> children) {
    return Card(
      color: panel,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      child: Column(children: children),
    );
  }

  Widget _profileTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? trailingText,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: ink70),
      title: Text(title, style: const TextStyle(
        color: white, fontWeight: FontWeight.w600,
      )),
      trailing: trailing ?? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(trailingText,
                  style: const TextStyle(color: ink54)),
            ),
          const Icon(Icons.chevron_right, color: ink54),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<bool> _ensureCommunityProfile() async {
    final client=supabaseClient; final user=client?.auth.currentUser;
    if(client==null||user==null)return false;
    final existing=await client.from('community_profiles').select('user_id').eq('user_id',user.id).maybeSingle();
    if(existing!=null)return true;
    final controller=TextEditingController(text:(user.email??'').split('@').first.isEmpty?'FLIXORA User':(user.email??'').split('@').first);
    final name=await showDialog<String>(context:context,barrierDismissible:false,builder:(dialogContext)=>AlertDialog(
      backgroundColor:panel,title:const Text('Choose your Community name',style:TextStyle(color:white)),
      content:TextField(controller:controller,maxLength:40,style:const TextStyle(color:white),decoration:const InputDecoration(hintText:'Display name')),
      actions:[FilledButton(onPressed:(){final value=controller.text.trim();if(value.isNotEmpty&&value.length<=40)Navigator.pop(dialogContext,value);},child:const Text('Continue'))],
    ));
    controller.dispose(); if(name==null||name.trim().isEmpty)return false;
    await client.from('community_profiles').insert({'user_id':user.id,'display_name':name.trim()});
    return true;
  }

  Future<bool> _communityProfileTask() {
    final userId = supabaseClient?.auth.currentUser?.id;
    if (userId == null) return Future<bool>.value(false);
    if (_communityProfileUserId != userId) {
      _communityProfileUserId = userId;
      _communityProfileFuture = null;
      _communityFeedFuture = null;
      _communityInboxFuture = null;
    }
    return _communityProfileFuture ??= _ensureCommunityProfile();
  }

  Future<Map<String, dynamic>> _loadCommunityFeed() async {
    final client = supabaseClient!;
    final posts = List<Map<String, dynamic>>.from(
      await client.from('community_posts').select('*').isFilter('removed_at', null)
          .order('created_at', ascending: false).limit(60),
    );
    final authorIds = posts.map((post) => post['author_id'].toString()).toSet().toList();
    final postIds = posts.map((post) => post['id'].toString()).toList();
    final profiles = authorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client.from('community_profiles').select('user_id,display_name,avatar_url')
                .inFilter('user_id', authorIds),
          );
    final likes = postIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client.from('community_likes').select('post_id,user_id').inFilter('post_id', postIds),
          );
    return {'posts': posts, 'profiles': profiles, 'likes': likes};
  }

  Future<void> _refreshCommunityFeed() async {
    final next = _loadCommunityFeed();
    _communityFeedFuture = next;
    if (mounted) setState(() {});
    try { await next; } catch (_) {}
  }

  Widget _communityContent() {
    final user = supabaseClient?.auth.currentUser;
    if (user == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.groups_outlined, color: gold, size: 48),
        const SizedBox(height: 12),
        const Text('Sign in to join FLIXORA Community', style: TextStyle(color: white)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _showVisitorLogin, child: const Text('Login / Sign Up')),
      ]));
    }
    return FutureBuilder<bool>(
      future: _communityProfileTask(),
      builder: (context, profile) {
        if (profile.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        if (profile.hasError) {
          return _profileMessagePage(Icons.error_outline, 'Community unavailable', profile.error.toString());
        }
        if (profile.data != true) {
          return _profileMessagePage(Icons.person_outline, 'Profile setup required', 'Sign in to continue.');
        }
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _communityPostController,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 3000,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(color: white),
                  decoration: const InputDecoration(
                    hintText: 'Share a movie review or start a discussion...',
                    hintStyle: TextStyle(color: ink54),
                    border: InputBorder.none,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _publishingCommunityPost ? null : () async {
                      final draft = _communityPostController.text.trim();
                      if (draft.isEmpty) {
                        _showMessage('Write something before publishing.');
                        return;
                      }
                      setState(() => _publishingCommunityPost = true);
                      try {
                        await supabaseClient!.from('community_posts').insert({
                          'author_id': user.id, 'body': draft,
                        });
                        _communityPostController.clear();
                        _communityFeedFuture = _loadCommunityFeed();
                        if (mounted) setState(() {});
                      } catch (error) {
                        _showMessage('Could not publish post: $error');
                      } finally {
                        if (mounted) setState(() => _publishingCommunityPost = false);
                      }
                    },
                    icon: _publishingCommunityPost
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(_publishingCommunityPost ? 'Posting...' : 'Post'),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _communityFeedFuture ??= _loadCommunityFeed(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator(color: gold));
                }
                if (snapshot.hasError) {
                  return _profileMessagePage(Icons.wifi_off, 'Could not load Community', snapshot.error.toString());
                }
                final data = snapshot.data!;
                final posts = data['posts'] as List<Map<String, dynamic>>;
                final profiles = data['profiles'] as List<Map<String, dynamic>>;
                final likes = data['likes'] as List<Map<String, dynamic>>;
                if (posts.isEmpty) {
                  return _profileMessagePage(Icons.forum_outlined, 'No Community posts yet',
                      'Be the first to start a movie discussion.');
                }
                return RefreshIndicator(
                  color: gold,
                  backgroundColor: panel,
                  onRefresh: _refreshCommunityFeed,
                  child: ListView.separated(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                    itemCount: posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final post = posts[index];
                      final authorMatches = profiles.where((p) => p['user_id'] == post['author_id']);
                      final author = authorMatches.isEmpty ? null : authorMatches.first;
                      final postLikes = likes.where((l) => l['post_id'] == post['id']).toList();
                      final liked = postLikes.any((l) => l['user_id'] == user.id);
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: panel, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: ink12),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const CircleAvatar(radius: 17, backgroundColor: ink12,
                                child: Icon(Icons.person, color: gold, size: 19)),
                            const SizedBox(width: 9),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text((author?['display_name'] ?? 'FLIXORA User').toString(),
                                  style: const TextStyle(color: white, fontWeight: FontWeight.w700)),
                              Text(DateTime.tryParse(post['created_at'].toString())?.toLocal()
                                      .toString().split('.').first ?? '',
                                  style: const TextStyle(color: ink54, fontSize: 10)),
                            ])),
                            PopupMenuButton<String>(
                              color: panel,
                              onSelected: (value) { if (value == 'report') _reportCommunityPost(post); },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'report', child: Text('Report post'))],
                              icon: const Icon(Icons.more_horiz, color: ink70),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Text(post['body'].toString(), style: const TextStyle(color: white, height: 1.4)),
                          Row(children: [
                            TextButton.icon(
                              onPressed: () async {
                                try {
                                  if (liked) {
                                    await supabaseClient!.from('community_likes').delete()
                                        .eq('post_id', post['id']).eq('user_id', user.id);
                                  } else {
                                    await supabaseClient!.from('community_likes').insert({
                                      'post_id': post['id'], 'user_id': user.id,
                                    });
                                  }
                                  await _refreshCommunityFeed();
                                } catch (error) { _showMessage('Like failed: $error'); }
                              },
                              icon: Icon(liked ? Icons.favorite : Icons.favorite_border,
                                  color: liked ? Colors.redAccent : ink70, size: 18),
                              label: Text('${postLikes.length}', style: const TextStyle(color: ink70)),
                            ),
                            TextButton.icon(
                              onPressed: () => _openCommunityComments(post),
                              icon: const Icon(Icons.mode_comment_outlined, color: ink70, size: 18),
                              label: const Text('Comments', style: TextStyle(color: ink70)),
                            ),
                          ]),
                        ]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }

  Future<void> _reportCommunityPost(Map<String, dynamic> post) async {
    const reasons = ['Spam', 'Harassment', 'Hate or abuse', 'Spoilers', 'Other'];
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: panel,
        title: const Text('Report post', style: TextStyle(color: white)),
        children: reasons.map((value) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialogContext, value),
          child: Text(value, style: const TextStyle(color: white)),
        )).toList(),
      ),
    );
    if (reason == null) return;
    try {
      await supabaseClient!.from('community_reports').insert({
        'reporter_id': supabaseClient!.auth.currentUser!.id,
        'target_type': 'post', 'target_id': post['id'],
        'reported_user_id': post['author_id'], 'reason': reason,
      });
      _showMessage('Report submitted for review.');
    } catch (error) { _showMessage('Could not submit report: $error'); }
  }

  Future<void> _openCommunityComments(Map<String, dynamic> post) async {
    final client = supabaseClient!;
    final controller = TextEditingController();
    final commentsStream = client.from('community_comments').stream(primaryKey: ['id'])
        .eq('post_id', post['id']).order('created_at');
    try {
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: panel,
        builder: (sheetContext) {
          final availableHeight = MediaQuery.sizeOf(sheetContext).height -
              MediaQuery.viewInsetsOf(sheetContext).bottom;
          final sheetHeight = (availableHeight * 0.72).clamp(240.0, 560.0).toDouble();
          return StatefulBuilder(
            builder: (context, setSheetState) => AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SizedBox(height: sheetHeight, child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                  child: Row(children: [
                    const Expanded(child: Text('Discussion', style: TextStyle(
                      color: white, fontSize: 17, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close, color: ink70)),
                  ]),
                ),
                Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: commentsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Center(child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load comments: ${snapshot.error}',
                          style: const TextStyle(color: ink70)),
                    ));
                    final comments = snapshot.data ?? [];
                    if (comments.isEmpty) return const Center(child: Text(
                      'No comments yet. Start the discussion.', style: TextStyle(color: ink54)));
                    return ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: comments.length,
                      itemBuilder: (context, index) => Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: ink10, borderRadius: BorderRadius.circular(10)),
                          child: Text(comments[index]['body'].toString(),
                              style: const TextStyle(color: white)),
                        ),
                      ),
                    );
                  },
                )),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(child: TextField(
                      controller: controller, minLines: 1, maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(color: white),
                      decoration: InputDecoration(
                        hintText: 'Write a comment...', filled: true, fillColor: ink10,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    )),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: gold),
                      onPressed: () async {
                        final body = controller.text.trim();
                        if (body.isEmpty) return;
                        try {
                          await client.from('community_comments').insert({
                            'post_id': post['id'], 'author_id': client.auth.currentUser!.id,
                            'body': body,
                          });
                          controller.clear();
                          setSheetState(() {});
                        } catch (error) { _showMessage('Could not comment: $error'); }
                      },
                    ),
                  ]),
                ),
              ])),
            ),
          );
        },
      );
    } finally { controller.dispose(); }
  }

  Future<Map<String, dynamic>> _loadCommunityInbox() async {
    final client = supabaseClient!;
    final userId = client.auth.currentUser!.id;
    final memberships = List<Map<String, dynamic>>.from(
      await client.from('conversation_members').select('conversation_id').eq('user_id', userId),
    );
    final conversationIds = memberships.map((m) => m['conversation_id'].toString()).toList();
    final inbox = <Map<String, dynamic>>[];
    if (conversationIds.isNotEmpty) {
      final allMembers = List<Map<String, dynamic>>.from(
        await client.from('conversation_members').select('conversation_id,user_id')
            .inFilter('conversation_id', conversationIds),
      );
      final otherUserIds = allMembers.where((m) => m['user_id'] != userId)
          .map((m) => m['user_id'].toString()).toSet().toList();
      final profiles = otherUserIds.isEmpty ? <Map<String, dynamic>>[] :
          List<Map<String, dynamic>>.from(await client.from('community_profiles')
              .select('user_id,display_name').inFilter('user_id', otherUserIds));
      final lastMessages = List<Map<String, dynamic>>.from(await client.from('direct_messages')
          .select('conversation_id,body,created_at').inFilter('conversation_id', conversationIds)
          .order('created_at', ascending: false));
      for (final membership in memberships) {
        final conversationId = membership['conversation_id'].toString();
        final other = allMembers.where((m) => m['conversation_id'].toString() == conversationId &&
            m['user_id'] != userId);
        if (other.isEmpty) continue;
        final otherUserId = other.first['user_id'];
        final profile = profiles.where((p) => p['user_id'] == otherUserId);
        final last = lastMessages.where((m) => m['conversation_id'].toString() == conversationId);
        inbox.add({
          'conversation_id': conversationId,
          'display_name': profile.isEmpty ? 'FLIXORA User' : profile.first['display_name'],
          'last_message': last.isEmpty ? '' : last.first['body'],
        });
      }
    }
    final availableProfiles = List<Map<String, dynamic>>.from(
      await client.from('community_profiles').select('user_id,display_name')
          .neq('user_id', userId).order('display_name').limit(100),
    );
    return {'inbox': inbox, 'profiles': availableProfiles};
  }

  Future<void> _startCommunityChat(String targetUserId) async {
    try {
      final conversationId = await supabaseClient!.rpc(
        'start_direct_conversation', params: {'p_target_user': targetUserId},
      );
      if (conversationId == null) throw Exception('Conversation could not be created.');
      await _openCommunityChat(conversationId.toString());
      _communityInboxFuture = _loadCommunityInbox();
      if (mounted) setState(() {});
    } catch (error) { _showMessage('Could not start chat: $error'); }
  }

  Future<void> _showNewCommunityMessagePicker(List<Map<String, dynamic>> profiles) async {
    if (profiles.isEmpty) {
      _showMessage('No other FLIXORA members are available yet.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: panel,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.65,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
            child: Row(children: [
              const Expanded(child: Text('New Message', style: TextStyle(
                color: white, fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.close, color: ink70)),
            ]),
          ),
          Expanded(child: ListView.separated(
            itemCount: profiles.length,
            separatorBuilder: (_, __) => const Divider(color: ink10, height: 1),
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return ListTile(
                leading: const CircleAvatar(backgroundColor: ink12,
                    child: Icon(Icons.person_outline, color: gold)),
                title: Text(profile['display_name'].toString(), style: const TextStyle(color: white)),
                trailing: const Icon(Icons.chat_bubble_outline, color: gold),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startCommunityChat(profile['user_id'].toString());
                },
              );
            },
          )),
        ]),
      ),
    );
  }

  Future<void> _openCommunityChat(String conversationId) async {
    final client = supabaseClient!;
    final userId = client.auth.currentUser!.id;
    final controller = TextEditingController();
    // Read receipts are best-effort: a read-time update must never prevent
    // the conversation and its message composer from opening.
    try {
      await client.from('conversation_members').update({
        'last_read_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('conversation_id', conversationId).eq('user_id', userId);
    } catch (_) {}

    final messageStream = client.from('direct_messages').stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId).order('created_at');
    try {
      await showModalBottomSheet<void>(
        context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: panel,
        builder: (sheetContext) {
          var sending = false;
          final availableHeight = MediaQuery.sizeOf(sheetContext).height -
              MediaQuery.viewInsetsOf(sheetContext).bottom;
          final sheetHeight = (availableHeight * 0.72).clamp(260.0, 600.0).toDouble();
          return StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> sendMessage() async {
                final body = controller.text.trim();
                if (body.isEmpty || sending) return;
                setSheetState(() => sending = true);
                try {
                  await client.from('direct_messages').insert({
                    'conversation_id': conversationId, 'sender_id': userId, 'body': body,
                  });
                  controller.clear();
                } catch (error) {
                  _showMessage('Message not sent: $error');
                } finally {
                  if (sheetContext.mounted) setSheetState(() => sending = false);
                }
              }
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: SizedBox(height: sheetHeight, child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                    child: Row(children: [
                      const Expanded(child: Text('Messages', style: TextStyle(
                        color: white, fontSize: 17, fontWeight: FontWeight.bold))),
                      IconButton(onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close, color: ink70)),
                    ]),
                  ),
                  Expanded(child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: messageStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Center(child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Could not load messages: ${snapshot.error}',
                            style: const TextStyle(color: ink70)),
                      ));
                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) return const Center(child: Text(
                        'Say hello to start the conversation.', style: TextStyle(color: ink54)));
                      return ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final item = messages[index];
                          final mine = item['sender_id'] == userId;
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 300),
                              decoration: BoxDecoration(
                                color: mine ? gold.withValues(alpha: 0.2) : ink10,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(item['body'].toString(), style: const TextStyle(color: white)),
                            ),
                          );
                        },
                      );
                    },
                  )),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: TextField(
                        controller: controller, minLines: 1, maxLines: 4,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => sendMessage(),
                        style: const TextStyle(color: white),
                        decoration: InputDecoration(
                          hintText: 'Write a message...', filled: true, fillColor: ink10,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                        ),
                      )),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: sending ? null : sendMessage,
                        style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: bg,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
                        child: sending ? const SizedBox(width: 17, height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded, size: 18),
                      ),
                    ]),
                  ),
                ])),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<Map<String, dynamic>> _communityInboxTask() {
    return _communityInboxFuture ??= _loadCommunityInbox();
  }

  Widget _messagesContent() {
    final user = supabaseClient?.auth.currentUser;
    if (user == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.message_outlined, color: gold, size: 48),
        const SizedBox(height: 12),
        const Text('Sign in to use FLIXORA Messages', style: TextStyle(color: white)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _showVisitorLogin, child: const Text('Login / Sign Up')),
      ]));
    }
    return FutureBuilder<bool>(
      future: _communityProfileTask(),
      builder: (context, profile) {
        if (profile.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: gold));
        }
        if (profile.hasError || profile.data != true) {
          return _profileMessagePage(Icons.error_outline, 'Messages unavailable',
              profile.hasError ? profile.error.toString() : 'Community profile setup is required.');
        }
        return FutureBuilder<Map<String, dynamic>>(
          future: _communityInboxTask(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: gold));
            }
            if (snapshot.hasError) {
              return _profileMessagePage(Icons.error_outline, 'Could not load Messages',
                  snapshot.error.toString());
            }
            final inbox = snapshot.data!['inbox'] as List<Map<String, dynamic>>;
            final profiles = snapshot.data!['profiles'] as List<Map<String, dynamic>>;
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: () => _showNewCommunityMessagePicker(profiles),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('New Message'),
                )),
                const SizedBox(height: 16),
                if (inbox.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No conversations yet. Start a new message.',
                        style: TextStyle(color: ink54))),
                  )
                else ...[
                  const Padding(padding: EdgeInsets.only(bottom: 8),
                    child: Text('Your conversations', style: TextStyle(
                      color: white, fontSize: 16, fontWeight: FontWeight.bold))),
                  ...inbox.map((chat) => Card(
                    color: panel,
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: ink12,
                          child: Icon(Icons.person, color: gold)),
                      title: Text(chat['display_name'].toString(), style: const TextStyle(color: white)),
                      subtitle: Text(chat['last_message'].toString(), maxLines: 1,
                          overflow: TextOverflow.ellipsis, style: const TextStyle(color: ink54)),
                      trailing: const Icon(Icons.chevron_right, color: ink54),
                      onTap: () => _openCommunityChat(chat['conversation_id'].toString()),
                    ),
                  )),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _profileSectionContent() {
    switch (_profileSection) {
      case 'Watch History':
        return _watchHistoryPage();
      case 'My List':
        return _collectionContent('My List', _moviesForIds(_saved));
      case 'My Favourites':
        return _collectionContent('My Favourites', _moviesForIds(_favourites));
      case 'My Activity':
        return _collectionContent('My Activity', _watchHistory);
      case 'Settings':
        return _settingsContent();
      case 'Rewards Center':
        return _profileMessagePage(
          Icons.card_giftcard, 'Rewards are coming soon',
          'FLIXORA rewards are not enabled yet.',
        );
      case 'Messages':
        return _messagesContent();
      case 'TV Download & Web Link':
        return _profileMessagePage(
          Icons.live_tv_outlined, 'TV links are not connected yet',
          'This section is reserved for verified TV download and web links.',
        );
      case 'Community':
        return _communityContent();
      default:
        return _profileContent();
    }
  }

  Widget _settingSwitch({required String title, required String subtitle, required bool value, required ValueChanged<bool> onChanged}) {
    return SwitchListTile(
      value: value, onChanged: onChanged, activeThumbColor: ink,
      activeTrackColor: gold, inactiveThumbColor: ink,
      inactiveTrackColor: ink24,
      title: Text(title, style: const TextStyle(color: white, fontSize: 15, fontStyle: FontStyle.italic)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 7), child: Text(subtitle, style: const TextStyle(color: ink60, fontSize: 12, height: 1.3))),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  void _showAboutUs() {
    _showPolicyDialog(
      title: 'About FLIXORA',
      message: '''ABOUT FLIXORA

Your World of Entertainment

Welcome to FLIXORA — a modern entertainment platform designed to bring movies, discovery and community together in one place.

FLIXORA aims to provide users with a smooth, convenient and enjoyable entertainment experience through a clean interface, organized movie collections and easy-to-use features.

Whether you want to discover something new, explore movie details, save your favorites or connect with other movie lovers, FLIXORA is designed to make your experience simple and enjoyable.

WHAT FLIXORA OFFERS

1. Explore Movies
Discover movies from different genres and categories. Explore a growing collection of entertainment content in one place.

2. Detailed Movie Information
Explore movie posters, backdrops, ratings, release dates, descriptions and other available details to help you choose what to watch.

3. Personalized Experience
Enjoy a modern, user-friendly interface designed to make browsing and exploring content easier.

4. Community
Connect with other FLIXORA members, share your thoughts, create posts and take part in entertainment discussions.

5. Private Messaging
Communicate privately with other community members through the messaging feature.

6. Saved Movies
Keep your favorite movies saved so you can easily find them again.

7. Continuous Improvements
We continuously aim to improve the platform with better performance, useful features and an enhanced user experience.

OUR MISSION

Our mission is to make entertainment discovery easier and more enjoyable by bringing movie exploration, personal collections and community interaction together in one platform.

OUR VISION

Our vision is to grow FLIXORA into a modern, user-focused entertainment platform that values simplicity, innovation, reliability and user experience.

We believe entertainment is better when discovery and connection come together.

APP INFORMATION

Application Name: FLIXORA
Version: 1.0.12
Platform: Android
Application Type: Entertainment

DEVELOPER INFORMATION

Developed & Maintained By

MD : SHOHANUR ISLAM SHRABON

Founder & Developer of FLIXORA

COMMUNITY & PROMOTION TEAM

Sakib Shorno

Mubin Dewan

Thank you for being a part of FLIXORA. Your support motivates us to keep improving and building a better entertainment experience.

FLIXORA
Entertainment Beyond Boundaries.

© FLIXORA. All Rights Reserved.''',
    );
  }

  void _showPrivacyPolicy() {
    _showPolicyDialog(
      title: 'Privacy Policy',
      message: '''PRIVACY POLICY

FLIXORA — Your Privacy Matters

Last Updated: November 14, 2026

Welcome to FLIXORA. Your privacy and the protection of your personal information are important to us.

This Privacy Policy explains what information may be collected when you use FLIXORA, how it may be used, how it is protected and what choices you have regarding your information.

By using FLIXORA, you acknowledge that you have read and understood this Privacy Policy.

1. INFORMATION WE COLLECT

To provide and maintain FLIXORA's features, certain information may be collected or stored.

A. Account Information
When you create or use an account, information may include:
• User ID and account identification details.
• Email address, if provided during registration.
• Community display name.
• Profile information you choose to provide.

B. Community Information
When you use the Community feature, information may include:
• Posts and text you publish.
• Comments and replies.
• Likes and interactions.
• Reports submitted by you.
• Community profile information.

Your posts and comments may be visible to other FLIXORA users.

C. Private Messages
FLIXORA provides private messaging between users.

Messages and related conversation information may be stored to provide messaging functionality and maintain conversation history.

Messages are intended for the relevant conversation participants. Please avoid sharing sensitive personal information unnecessarily.

D. Saved Movies and Preferences
When you use features such as Saved Movies, information about your saved content and preferences may be stored to provide a personalized experience.

E. Technical Information
Certain technical information may be processed to maintain app functionality, security and performance. This may include app-related information, device or operating-system details, connection information and technical error data, depending on the app's implementation.

2. HOW WE USE YOUR INFORMATION

Information processed through FLIXORA may be used to:
• Create and manage user accounts.
• Provide app features and services.
• Display Community posts and comments.
• Enable private messaging.
• Save your selected movies and preferences.
• Process reports and moderate Community content.
• Help prevent misuse and protect users.
• Maintain app security and performance.
• Resolve technical problems and improve the user experience.

We aim to use information only for legitimate app-related purposes.

3. INFORMATION SHARING

Your information is handled with respect for your privacy.
• Community posts and comments may be visible to other users.
• Private messages are intended for the participants of the conversation.
• Certain information may be reviewed when necessary to investigate reports or address violations of Community rules.
• Information may be disclosed when required by applicable law or necessary to protect the security of FLIXORA and its users.

FLIXORA does not intend to sell users' personal information.

4. DATA SECURITY

We take reasonable steps to protect information processed through FLIXORA.

Security measures may include:
• Account access restrictions.
• Authentication and authorization controls.
• Database security policies.
• Restricted access to protected information.
• Security maintenance and monitoring.

However, no digital platform can guarantee absolute security. Users should protect their account credentials and avoid sharing account access with others.

5. DATA RETENTION

Information may be retained for as long as reasonably necessary to provide FLIXORA's features, maintain functionality, protect platform security and meet applicable legal requirements.

Retention periods may vary depending on the type of information and its purpose.

6. YOUR PRIVACY CHOICES

You should have reasonable control over the information you provide through FLIXORA.

Depending on available app features, you may be able to:
• Manage your profile information.
• Choose what you publish in the Community.
• Manage your saved movies.
• Stop using Community or Messaging features.
• Request correction or deletion of eligible personal information.

Some information may need to be retained for security, legal or legitimate operational purposes.

7. ACCOUNT AND DATA DELETION

If you no longer wish to use FLIXORA, you may request deletion of your account and associated personal information.

A deletion request may include:
• Account-related information.
• Community profile information.
• Posts and comments, where eligible.
• Other personal information associated with your account.

Certain information may be retained where necessary for legal compliance, security or dispute resolution.

Deletion requests may require account verification.

8. CHILDREN'S PRIVACY

FLIXORA is not specifically designed to collect personal information from children.

We encourage parents and guardians to supervise children's use of online services and help them understand the importance of protecting personal information.

If we become aware that personal information has been collected from a child in circumstances where it should not have been, appropriate steps will be taken as required by applicable law.

9. CHANGES TO THIS PRIVACY POLICY

We may update this Privacy Policy when FLIXORA introduces new features, improves existing services or changes its privacy practices.

Updated versions will be published within the application with a revised Last Updated date.

We encourage users to review this page periodically.

10. PRIVACY QUESTIONS AND REQUESTS

If you have questions, concerns or requests regarding your privacy or personal information, please use the official support or privacy request method provided by FLIXORA when available.

11. YOUR AGREEMENT

By using FLIXORA, you acknowledge that you have read and understood this Privacy Policy and how your information may be handled in connection with the application's features.

FLIXORA
Entertainment Beyond Boundaries.

© FLIXORA. All Rights Reserved.''',
    );
  }

  void _showPolicyDialog({required String title, required String message}) {
    final isPrivacy = title.toLowerCase().contains('privacy');
    final paragraphs = message
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(pageContext).pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: white),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: white,
                fontFamily: 'Arial',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: false,
          ),
          body: SafeArea(
            top: false,
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: gold.withValues(alpha: 0.28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            isPrivacy
                                ? Icons.privacy_tip_outlined
                                : Icons.movie_creation_outlined,
                            color: goldLight,
                            size: 25,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isPrivacy
                              ? 'Your Privacy Matters'
                              : 'Your World of Entertainment',
                          style: const TextStyle(
                            color: white,
                            fontFamily: 'Arial',
                            fontSize: 21,
                            height: 1.25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isPrivacy
                              ? 'Learn how FLIXORA handles information and protects your privacy.'
                              : 'Discover what FLIXORA is, what it offers and the vision behind it.',
                          style: const TextStyle(
                            color: ink70,
                            fontFamily: 'Arial',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        if (isPrivacy) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Last Updated: November 14, 2026',
                            style: TextStyle(
                              color: goldLight,
                              fontFamily: 'Arial',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final paragraph in paragraphs)
                    _policyDocumentBlock(paragraph),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'FLIXORA  •  Entertainment Beyond Boundaries.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: ink54,
                        fontFamily: 'Arial',
                        fontSize: 11,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _policyDocumentBlock(String paragraph) {
    final lines = paragraph
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return const SizedBox.shrink();

    final firstLine = lines.first;
    final isSectionHeading = lines.length == 1 &&
        (firstLine == firstLine.toUpperCase() ||
            RegExp(r'^\d+\.\s').hasMatch(firstLine) ||
            RegExp(r'^[A-Z]\.\s').hasMatch(firstLine));

    if (isSectionHeading) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: gold,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                firstLine,
                style: const TextStyle(
                  color: goldLight,
                  fontFamily: 'Arial',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isBulletList = lines.every(
      (line) => line.startsWith('•') || RegExp(r'^\d+\.\s').hasMatch(line),
    );
    if (isBulletList) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.circle, color: gold, size: 6),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        line.replaceFirst(RegExp(r'^(?:•|\\d+\\.)\\s*'), ''),
                        style: const TextStyle(
                          color: ink70,
                          fontFamily: 'Arial',
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        paragraph,
        style: const TextStyle(
          color: ink70,
          fontFamily: 'Arial',
          fontSize: 13,
          height: 1.65,
        ),
      ),
    );
  }

  Widget _settingsContent() {
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(12, 14, 12, 16), children: [
        const Padding(padding: EdgeInsets.fromLTRB(4, 2, 4, 9), child: Text('Your app and preferences', style: TextStyle(color: ink70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.notifications_none, 'Notifications', () => _saveBoolSetting('flixora_notifications', !_notificationsEnabled, (x) => _notificationsEnabled = x),
            trailing: Switch(value: _notificationsEnabled, onChanged: (v) => _saveBoolSetting('flixora_notifications', v, (x) => _notificationsEnabled = x), activeThumbColor: ink, activeTrackColor: gold)),
          _profileTile(Icons.language, 'Language', _showLanguagePicker, trailingText: _appLanguage),
          _profileTile(Icons.tune, 'Watch Options', _showWatchOptions, trailingText: _preferredQuality),
          _settingSwitch(title: 'Family Mode', subtitle: 'Helps keep the catalogue suitable for family viewing.', value: _familyMode, onChanged: (v) => _saveBoolSetting('flixora_family_mode', v, (x) => _familyMode = x)),
          _settingSwitch(title: 'Download in background', subtitle: 'Keep download tasks active while you use other screens.', value: _downloadInBackground, onChanged: (v) => _saveBoolSetting('flixora_download_background', v, (x) => _downloadInBackground = x)),
          _settingSwitch(title: 'Auto activate Miniplayer', subtitle: 'Miniplayer behavior will be connected when the player feature is extended.', value: _autoMiniPlayer, onChanged: (v) => _saveBoolSetting('flixora_auto_miniplayer', v, (x) => _autoMiniPlayer = x)),
          _profileTile(Icons.privacy_tip_outlined, 'Privacy Settings', () => _showSettingsInfo('Privacy Settings', 'Your watch history, saved list and app preferences are currently stored on this device. Account sync and privacy controls will be expanded with the visitor account backend.')),
        ]),
        const SizedBox(height: 20),
        const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 9), child: Text('More info and support', style: TextStyle(color: ink70, fontSize: 13))),
        _profileGroup([
          _profileTile(Icons.system_update, 'Check update', () => _showSettingsInfo('Check update', 'Automatic update checking is not connected to a release service yet. Install new FLIXORA versions from the official release when available.')),
          _profileTile(Icons.info_outline, 'About us', _showAboutUs),
          _profileTile(Icons.policy_outlined, 'Privacy Policy', _showPrivacyPolicy),
          _profileTile(Icons.description_outlined, 'User Agreement', () => _showSettingsInfo('User Agreement', 'The user agreement page will be added before release.')),
        ]),
      ])),
    ]);
  }

  Widget _profileMessagePage(IconData icon, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: gold, size: 54),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(color: white, fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: ink54, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Future<void> _showVisitorLogin() async {
    final client = supabaseClient;
    if (client == null) {
      _showMessage('Visitor login is unavailable until the account service is configured.');
      return;
    }
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    var isSignUp = false;
    var busy = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: panel,
          title: Text(isSignUp ? 'Create visitor account' : 'Visitor Login',
              style: const TextStyle(color: white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: white),
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,                style: const TextStyle(color: white),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => setDialogState(() {
                isSignUp = !isSignUp;
                errorText = null;
              }),
              child: Text(isSignUp ? 'I have an account' : 'Create account'),
            ),
            FilledButton(
              onPressed: busy ? null : () async {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (!email.contains('@') || password.length < 6) {
                  setDialogState(() => errorText =
                      'Enter a valid email and a password of at least 6 characters.');
                  return;
                }
                setDialogState(() { busy = true; errorText = null; });
                try {
                  if (isSignUp) {
                    final response = await client.auth.signUp(
                      email: email,
                      password: password,
                      emailRedirectTo: authRedirectUrl,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      setState(() {});
                      _showMessage(response.session == null
                          ? 'Account created. Check your email if verification is required.'
                          : 'Visitor account created and signed in.');
                    }
                  } else {
                    await client.auth.signInWithPassword(
                      email: email, password: password,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) {
                      setState(() {});
                      _showMessage('Visitor login successful.');
                    }
                  }
                } catch (error) {
                  setDialogState(() {
                    busy = false;
                    errorText = error.toString().replaceFirst('Exception: ', '');
                  });
                }
              },
              child: busy
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isSignUp ? 'Create account' : 'Login'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    passwordController.dispose();
  }
  Future<void> _signOutVisitor() async {
    try {
      await supabaseClient?.auth.signOut();
      if (mounted) {
        setState(() {});
        _showMessage('Logged out.');
      }
    } catch (error) {
      _showMessage('Could not log out: $error');
    }
  }

  Future<void> _showParentalPinDialog() async {
    final controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    final existingPin = prefs.getString('flixora_parental_pin');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: Text(existingPin == null ? 'Set Parental PIN' : 'Change Parental PIN',
            style: const TextStyle(color: white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: const TextStyle(color: white),
          decoration: const InputDecoration(
            labelText: '4–6 digit PIN',
            counterStyle: TextStyle(color: ink54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                _showMessage('PIN must contain 4 to 6 digits.');
                return;
              }
              await prefs.setString('flixora_parental_pin', pin);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) _showMessage('Parental PIN saved on this device.');
            },
            child: const Text('Save PIN'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _toggleStudyMode() async {
    final nextValue = !_studyMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('flixora_study_mode', nextValue);
    if (!mounted) return;
    setState(() => _studyMode = nextValue);
    _showMessage(nextValue
        ? 'Study Mode enabled.'
        : 'Study Mode disabled.');
  }

  List<Movie> _rankingMovies() {
    if (_rankingTv) {
      switch (_rankingCategory) {
        case 'Top Series': {
          final series = _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv, ...anime,
            ...koreanDrama, ...bengaliTv, ...indianDramaTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
          return series..sort((a, b) => b.rating.compareTo(a.rating));
        }
        case 'New Bengali':
          return _deduplicateMovies(bengaliTv);
        case 'Anime':
          return _deduplicateMovies([
            ...anime,
            ..._regularMovieBoxItems
                .where((title) => title.mediaType == 'tv' && _isAnimeTitle(title)),
            ...flixoraMovies.where((title) =>
                title.mediaType == 'tv' && _isAnimeTitle(title)),
          ]);
        case 'Drama': {
          return _deduplicateMovies([
            ...topRatedTv, ...popularTv, ...trendingTv,
            ...bengaliTv, ...koreanDrama, ...indianDramaTv, ...flixoraMovies,
            ..._regularMovieBoxItems,
          ]).where((title) => title.mediaType == 'tv' && title.genres.any(
            (genre) => genre.toLowerCase().contains('drama'),
          )).toList();
        }
        case 'Web Series':
          return _webSeriesTitles();
        case 'Asian Drama':
          return _deduplicateMovies(koreanDrama);
        case 'Indian Drama':
          return _deduplicateMovies(indianDramaTv);
        case 'Pakistani Drama':
          return _pakistaniTrendingDramaTitles();
        default:
          return _deduplicateMovies([
            ...trendingTv, ...popularTv, ...topRatedTv, ...anime,
            ...koreanDrama, ...bengaliTv, ...indianDramaTv,
            ...flixoraMovies.where((title) => title.mediaType == 'tv'),
          ]);
      }
    }
    switch (_rankingCategory) {
      case 'TOP Movies':
        final movies = _deduplicateMovies([
          ...topRated, ...popular, ...trending,
        ].where((movie) => movie.mediaType == 'movie').toList());
        return movies..sort((a, b) => b.rating.compareTo(a.rating));
      case 'New Bengali':
        return _rankingRegionalMovies('Bengali');
      case 'Bollywood':
        return _rankingRegionalMovies('Bollywood');
      case 'Hollywood':
        return _rankingRegionalMovies('Hollywood');
      case 'South Indian':
        return _rankingRegionalMovies('South Indian');
      case 'New Release':
        return _deduplicateMovies(_withoutFlixoraDuplicates(latest));
      case 'Pakistani Drama':
        return _pakistaniTrendingDramaTitles();
      default:
        return _rankingMoviePool();
    }
  }

  Widget _rankingContent() {
    const movieCategories = [
      'Cinema', 'TOP Movies', 'New Bengali', 'Bollywood',
      'Hollywood', 'South Indian', 'New Release', 'Pakistani Drama',
    ];
    const tvCategories = [
      'All Series', 'Top Series', 'New Bengali',
      'Anime', 'Drama', 'Web Series', 'Asian Drama', 'Indian Drama',
    ];
    final categories = _rankingTv ? tvCategories : movieCategories;
    final movies = _rankingMovies();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 126, child: ColoredBox(color: const Color(0xFF11141C), child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 20), itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index]; final selected = category == _rankingCategory;
          return InkWell(
            onTap: () => setState(() => _rankingCategory = category),
            child: Container(
              height: 58,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? gold.withValues(alpha: 0.16) : Colors.transparent,
                border: Border(
                  left: BorderSide(
                    color: selected ? gold : Colors.transparent,
                    width: 4,
                  ),
                ),
              ),
              child: Text(
                category,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? gold : const Color(0xFFD4DAE4),
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ))),
      Expanded(child: movies.isEmpty
          ? (_rankingCataloguesLoading && !_rankingTv
              ? const Center(child: CircularProgressIndicator(color: gold))
              : const Center(child: Text('No movies available in this category.', style: TextStyle(color: ink54))))
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), itemCount: movies.length,
        itemBuilder: (context, index) {
          final movie = movies[index];
          return Padding(padding: const EdgeInsets.only(bottom: 18), child: SizedBox(height: 112, child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(7), child: SizedBox(width: 76, height: 108, child: Stack(fit: StackFit.expand, children: [
              movie.posterUrl.isEmpty
                  ? Container(color: panel, child: const Icon(Icons.movie, color: gold))
                  : FlixoraCachedImage(
                      imageUrl: movie.posterUrl,
                      isOnline: _online,
                      fit: BoxFit.cover,
                      fallback: Container(color: panel, child: const Icon(Icons.movie, color: gold)),
                    ),
              Positioned(left: 0, top: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: index == 0 ? const Color(0xFFE83E9B) : const Color(0xFF2787E8), borderRadius: const BorderRadius.only(bottomRight: Radius.circular(7))), child: Text((index + 1).toString().padLeft(2, '0'), style: const TextStyle(color: white, fontWeight: FontWeight.w900, fontSize: 12)))),
            ]))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(movie.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: white, fontSize: 14, fontWeight: FontWeight.w700)),
              const Spacer(),
              Row(children: [const Icon(Icons.star, color: premiumGold, size: 16), const SizedBox(width: 4), Text(movie.rating.toStringAsFixed(1), style: const TextStyle(color: premiumGold, fontWeight: FontWeight.w800)), const SizedBox(width: 6), Flexible(child: Text(movie.year, overflow: TextOverflow.ellipsis, style: const TextStyle(color: ink54, fontSize: 11)))]),
            ])),
            IconButton(onPressed: () => _playMovie(movie), icon: const Icon(Icons.play_circle_fill, color: gold, size: 34), tooltip: 'Play'),
          ])));
        },
      )),
    ]);
  }

  Widget _currentPage() {
    if (_showRanking) return _rankingContent();
    if (_searchOpen) {
      return _search.isEmpty ? _searchLandingContent() : _searchContent();
    }
    if (_search.isNotEmpty) return _searchContent();

    switch (_tab) {
      case 0:
        if (loading && _allMovies().isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: gold),
          );
        }

        if (homeError != null && _allMovies().isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: gold, size: 45),
                const SizedBox(height: 12),
                const Text(
                  'Unable to load movies.',
                  style: TextStyle(color: white),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: loadHome,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          );
        }

        if (_allMovies().isEmpty) {
          return const Center(
            child: Text(
              'No movies available yet.',
              style: TextStyle(color: ink54),
            ),
          );
        }

        return _homeContent();

      case 1:
        return _watchHistoryPage();
      case 2:
        return _libraryContent();
      case 3:
        return _profileSection == null
            ? _profileContent()
            : _profileSectionContent();
      case 4:
        return ArchiveScreen(onMovieSelected: _openArchiveMovie);
      default:
        return _homeContent();
    }
  }

  Widget _bottomNavItem(int index, IconData icon, IconData activeIcon, String label) {
    final selected = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _search = '';
            _showRanking = false;
            _searchController.clear();
            _searchLoading = false;
            _profileSection = null;
            _tab = index;
          });
        },
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? activeIcon : icon, size: 22, color: selected ? gold : ink60),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: selected ? gold : ink60, fontSize: 11, height: 1.0, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ],          ),
        ),
      ),
    );
  }

  String _pageTitle() {
    if (_search.isNotEmpty) return 'Search Results';

    if (_tab == 1) return 'Watch History';
    if (_tab == 2) return 'Library';
    if (_tab == 3) return _profileSection ?? 'CineProfile';
    if (_tab == 4) return 'Free Movies';
    return 'FLIXORA';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: bg,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
        centerTitle: _showRanking,
        toolbarHeight: _showRanking ? kToolbarHeight : (_tab == 0 ? 62 : kToolbarHeight),
        titleSpacing: _searchOpen ? 0 : (_tab == 0 && !_showRanking ? 8 : 16),
        leadingWidth: _searchOpen ? 48 : null,
        leading: _showRanking
            ? IconButton(
                onPressed: () => setState(() => _showRanking = false),
                icon: const Icon(Icons.arrow_back),
              )
            : _searchOpen
                ? IconButton(
                    tooltip: 'Back',
                    onPressed: _closeSearch,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : (_tab == 3 && _profileSection != null
                    ? IconButton(
                        onPressed: () => setState(() => _profileSection = null),
                        icon: const Icon(Icons.arrow_back),
                      )
                    : null),
        title: _showRanking
            ? const Text(
                'Ranking',
                style: TextStyle(color: white, fontWeight: FontWeight.w700),
              )
            : _tab == 0
                ? (_searchOpen
                    ? _searchField()
                    : Row(
                        children: [
                          Image.asset(
                            'assets/images/flixora_logo.png',
                            width: 39,
                            height: 39,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 9),
                          Expanded(child: _searchField()),
                        ],
                      ))
                : Text(
                    _pageTitle(),
                    style: const TextStyle(
                      color: gold,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
        actions: _tab == 0 || _showRanking
            ? const []
            : [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Tooltip(
                    message: _online
                        ? 'Internet connected'
                        : 'No internet connection',
                    child: Icon(
                      _online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                      color: _online ? gold : Colors.redAccent,
                    ),
                  ),
                ),
              ],
      ),
      body: (!_connectionKnown && _allMovies().isEmpty)
          ? const Center(
              child: CircularProgressIndicator(color: gold),
            )
          : (_tab == 0 && !_searchOpen && !_online && _allMovies().isEmpty)
              ? NoInternetScreen(onRefresh: _refreshFromOfflineScreen)
              : _currentPage(),
      extendBody: true,
      bottomNavigationBar: _showRanking ? null : Container(
        color: panel,
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          child: Container(
            height: 56,
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: ink10, width: 0.5)),
            ),
            child: Row(
              children: [
                _bottomNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
                _bottomNavItem(1, Icons.history_rounded, Icons.history, 'History'),
                _bottomNavItem(2, Icons.video_library_outlined, Icons.video_library, 'Library'),
                _bottomNavItem(3, Icons.person_outline, Icons.person, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NoInternetScreen extends StatefulWidget {
  final Future<bool> Function() onRefresh;
  final bool closeOnReconnect;

  const NoInternetScreen({
    super.key,
    required this.onRefresh,
    this.closeOnReconnect = false,
  });

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  Timer? _retryTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _retryTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) {
        if (!_refreshing) unawaited(_refresh(silent: true));
      },
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final connected = await widget.onRefresh();
      if (!mounted) return;
      if (connected) {
        if (widget.closeOnReconnect && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still offline. Please try again.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not refresh the connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _openWifiSettings(BuildContext context) async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.wifi);
    } catch (_) {
      try {
        await AppSettings.openAppSettings();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to open settings.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 75, color: gold),
              const SizedBox(height: 20),
              const Text(
                'Connect to the internet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'When your internet connection is restored: Explore various movies, TV series and more',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink,
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 25),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: gold,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(190, 46),
                ),
                onPressed: _refreshing ? null : () => _refresh(),
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(_refreshing ? 'Checking connection...' : 'Refresh'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _openWifiSettings(context),
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Open Wi-Fi Settings'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: goldLight,
                  side: const BorderSide(color: gold),
                  minimumSize: const Size(190, 44),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DownloadsScreen extends StatelessWidget {
  final List<DownloadTask> tasks;
  final Future<void> Function(DownloadTask) onDelete;
  final ValueChanged<DownloadTask> onPauseResume;
  final ValueChanged<DownloadTask> onPlay;

  const DownloadsScreen({
    super.key,
    required this.tasks,
    required this.onDelete,
    required this.onPauseResume,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.download_outlined, size: 65, color: goldLight),
              const SizedBox(height: 15),
              const Text(
                'No Downloads Yet',
                style: TextStyle(
                  color: white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your saved videos will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ink70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(
            'Saved Videos',
            style: TextStyle(
              color: white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            key: const PageStorageKey<String>('flixora-downloads-list'),
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final task = tasks[index];
              final completed = task.status == 'Completed';
              final failed = task.status == 'Failed';
              final paused = task.status == 'Paused';
              final downloading = task.status == 'Downloading';
              final statusColor = completed
                  ? gold
                  : failed
                      ? goldLight
                      : paused
                          ? ink70
                          : goldLight;
              final percent = (task.progress * 100).round().clamp(0, 100);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: completed ? gold : ink12,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: SizedBox(
                        width: 68,
                        height: 94,
                        child: task.poster.isEmpty
                            ? Container(
                                color: bg,
                                child: const Icon(
                                  Icons.movie,
                                  color: goldLight,
                                  size: 30,
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: task.poster,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: bg,
                                  child: const Icon(
                                    Icons.movie,
                                    color: goldLight,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${VideoQualityService.displayName(task.quality)}  •  ${task.totalBytes > 0 ? DownloadManager.formatBytes(task.totalBytes) : 'Size unavailable'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: ink70,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            completed
                                ? 'Successfully Downloaded'
                                : failed
                                    ? (task.errorMessage ?? 'Download failed')
                                    : paused
                                        ? 'Paused · Ready to resume'
                                        : task.status == 'Waiting'
                                            ? 'Waiting in queue'
                                            : 'Downloading',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: LinearProgressIndicator(
                                    value: task.totalBytes > 0
                                        ? task.progress
                                        : (completed ? 1 : null),
                                    minHeight: 6,
                                    backgroundColor: ink24,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                completed
                                    ? '100%'
                                    : task.totalBytes > 0
                                        ? '$percent%'
                                        : DownloadManager.formatBytes(task.bytesReceived),
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          if (!completed && task.bytesReceived > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Downloaded: ${DownloadManager.formatBytes(task.bytesReceived)}',
                              style: const TextStyle(
                                color: ink70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!completed)
                          IconButton(
                            tooltip: downloading ? 'Pause download' : 'Resume download',
                            onPressed: () => onPauseResume(task),
                            icon: Icon(
                              (downloading || task.status == 'Waiting')
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: downloading || task.status == 'Waiting' ||
                                      paused || failed
                                  ? goldLight
                                  : ink24,
                            ),
                          ),
                        if (completed)
                          IconButton(
                            tooltip: 'Play downloaded movie',
                            onPressed: task.filePath != null
                                ? () => onPlay(task)
                                : null,
                            icon: const Icon(
                              Icons.play_circle_fill,
                              color: Color(0xFF39E69B),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Delete download',
                          onPressed: downloading ? null : () => onDelete(task),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
/// Dedicated vertical Reels-style player for MovieBox Hot Shorts TV.
/// Every selected short is resolved through the central MovieBox/WeFeed core.
class HotShortsScreen extends StatefulWidget {
  final List<Movie> items;
  final int initialIndex;
  final int? initialSeasonNumber;
  final int? initialEpisodeNumber;
  final Future<List<Movie>> Function()? loadCatalogue;
  final ValueChanged<List<Movie>>? onCatalogueLoaded;

  const HotShortsScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
    this.initialSeasonNumber,
    this.initialEpisodeNumber,
    this.loadCatalogue,
    this.onCatalogueLoaded,
  });

  @override
  State<HotShortsScreen> createState() => _HotShortsScreenState();
}

class _HotShortsScreenState extends State<HotShortsScreen> {
  late List<Movie> _items;
  bool _catalogueRequested = false;
  late final Player _player;
  late final VideoController _videoController;
  late final PageController _pageController;

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;

  Future<void> _playerOperation = Future<void>.value();
  Timer? _controlsTimer;
  int _activeIndex = 0;
  int _requestToken = 0;
  bool _loading = true;
  bool _playing = false;
  bool _showControls = true;
  bool _disposed = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _activeSeasonNumber;
  int? _activeEpisodeNumber;
  List<MovieBoxShortEpisode> _availableEpisodes = [];

  @override
  void initState() {
    super.initState();
    _items = List<Movie>.from(widget.items);
    _activeIndex = _items.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _items.length - 1).toInt();
    _pageController = PageController(initialPage: _activeIndex);
    _player = Player(
      configuration: PlayerConfiguration(
        title: 'FLIXORA Hot Shorts',
        bufferSize: 24 * 1024 * 1024,
        libass: true,
      ),
    );
    _videoController = VideoController(_player);

    _playingSubscription = _player.stream.playing.listen((value) {
      if (!mounted || _disposed) return;
      setState(() {
        _playing = value;
        if (!value) _showControls = true;
      });
      if (value) {
        _scheduleControlsHide();
      } else {
        _controlsTimer?.cancel();
      }
    });
    _positionSubscription = _player.stream.position.listen((value) {
      if (!mounted || _disposed) return;
      setState(() => _position = value);
    });
    _durationSubscription = _player.stream.duration.listen((value) {
      if (!mounted || _disposed) return;
      setState(() => _duration = value);
    });
    _errorSubscription = _player.stream.error.listen((value) {
      if (!mounted || _disposed || _loading || _playing) return;
      setState(() => _error = 'This short stream could not be played. Tap retry.');
      debugPrint('Hot Shorts player error: $value');
    });
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (!completed || _disposed || _loading) return;
      unawaited(_player.seek(Duration.zero).then((_) => _player.play()));
    });

    if (_items.isNotEmpty) {
      unawaited(_loadShort(_activeIndex).whenComplete(_loadCatalogue));
    } else {
      unawaited(_loadCatalogue());
    }
  }

  Future<void> _loadCatalogue() async {
    final loader = widget.loadCatalogue;
    if (_catalogueRequested || loader == null || _disposed) return;
    _catalogueRequested = true;
    try {
      final loaded = await loader();
      if (!mounted || _disposed || loaded.isEmpty) return;

      final seen = <String>{};
      final merged = <Movie>[];
      for (final movie in [..._items, ...loaded]) {
        final key = movie.movieBoxId.isNotEmpty
            ? movie.movieBoxId
            : '${movie.title.toLowerCase().trim()}|${movie.year}';
        if (seen.add(key)) merged.add(movie);
      }
      if (merged.length > _items.length) {
        setState(() => _items = merged);
        widget.onCatalogueLoaded?.call(List<Movie>.unmodifiable(merged));
      }
    } catch (error) {
      debugPrint('Hot Shorts background catalogue load failed: $error');
    }
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted || _disposed || !_playing) return;
      setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    if (!mounted || _disposed) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  Future<void> _togglePlayback() async {
    if (_disposed) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play();
        _scheduleControlsHide();
      }
    } catch (error) {
      if (mounted && !_disposed) {
        setState(() => _error = 'Could not control this short video: $error');
      }
    }
  }

  Future<void> _showEpisodePicker() async {
    if (!mounted || _disposed) return;
    final episodes = _availableEpisodes;
    if (episodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _loading
                ? 'Episodes are loading. Please wait.'
                : 'No episodes are available for this short series.',
          ),
        ),
      );
      return;
    }

    final seasons = episodes.map((episode) => episode.season).toSet().toList()
      ..sort();
    final selectedEpisode =
        await showModalBottomSheet<MovieBoxShortEpisode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.68,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose Episode',
                        style: TextStyle(
                          color: white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded, color: white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final season in seasons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Season $season',
                                style: const TextStyle(
                                  color: gold,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: episodes
                                    .where((episode) =>
                                        episode.season == season)
                                    .map((episode) {
                                  final selected =
                                      episode.season == _activeSeasonNumber &&
                                          episode.episode ==
                                              _activeEpisodeNumber;
                                  return ChoiceChip(
                                    label: Text('EP ${episode.episode}'),
                                    selected: selected,
                                    onSelected: (_) =>
                                        Navigator.of(sheetContext)
                                            .pop(episode),
                                    selectedColor: gold,
                                    backgroundColor: panel,
                                    labelStyle: TextStyle(
                                      color: selected
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                    side: BorderSide(
                                      color: selected ? gold : ink24,
                                    ),
                                  );
                                }).toList(growable: false),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selectedEpisode != null && mounted && !_disposed) {
      await _loadShort(
        _activeIndex,
        requestedSeasonNumber: selectedEpisode.season,
        requestedEpisodeNumber: selectedEpisode.episode,
      );
    }
  }

  Map<String, String> _linkHeaders(Map<String, dynamic> link) {
    final rawHeaders = link['headers'];
    if (rawHeaders is! Map) return const <String, String>{};
    return Map<String, String>.from(
      rawHeaders.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  }

  int _qualityRank(Map<String, dynamic> link) {
    final label = (link['label'] ?? '').toString().toLowerCase();
    if (label.contains('2160p') || label.contains('4k')) return 5;
    if (label.contains('1080p')) return 4;
    if (label.contains('720p')) return 3;
    if (label.contains('480p')) return 2;
    if (label.contains('360p')) return 1;
    return 0;
  }

  Future<void> _prefetchShort(int index) async {
    if (_disposed || index < 0 || index >= _items.length) return;
    final movie = _items[index];
    try {
      await MovieBoxService.prewarmStreams(
        movie.toMovieBoxMap(),
        isSeries: movie.movieBoxIsSeries,
      );
    } catch (_) {
      // The next short will resolve normally when the viewer swipes to it.
    }
  }

  Future<void> _loadShort(
    int index, {
    int? requestedSeasonNumber,
    int? requestedEpisodeNumber,
  }) async {
    if (_disposed || index < 0 || index >= _items.length) return;
    final requestToken = ++_requestToken;
    final movie = _items[index];

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _position = Duration.zero;
        _duration = Duration.zero;
        _activeSeasonNumber = null;
        _activeEpisodeNumber = null;
        _availableEpisodes = [];
        _playing = false;
      });
    }

    // Serialize pause/open operations so a previous short cannot resume
    // over the next page while its MovieBox stream is being resolved.
    final pauseOperation = _playerOperation.then((_) async {
      if (!_disposed && requestToken == _requestToken) {
        await _player.pause();
      }
    });
    _playerOperation = pauseOperation.catchError((Object _) {});

    try {
      final requests = <Future<dynamic>>[
        MovieBoxService.playDetail(movie.toMovieBoxMap())
            .timeout(const Duration(seconds: 18)),
      ];
      if (movie.movieBoxIsSeries) {
        requests.add(
          MovieBoxService.seasons(movie.movieBoxId)
              .timeout(const Duration(seconds: 18)),
        );
      }

      final resolved = await Future.wait<dynamic>(requests);
      if (_disposed || requestToken != _requestToken) return;
      final detail = Map<String, dynamic>.from(resolved.first as Map);

      var seasonNumber = 0;
      var episodeNumber = 0;
      var availableEpisodes = <MovieBoxShortEpisode>[];
      if (movie.movieBoxIsSeries) {
        final seasons = (resolved[1] as List)
            .whereType<Map>()
            .map((season) => Map<String, dynamic>.from(season))
            .toList(growable: false);
        availableEpisodes = MovieBoxShortEpisode.fromSeasons(seasons);
        if (availableEpisodes.isEmpty) {
          throw StateError('No episodes were returned for this short series.');
        }

        final wantedSeason = requestedSeasonNumber ??
            (index == widget.initialIndex ? widget.initialSeasonNumber : null);
        final wantedEpisode = requestedEpisodeNumber ??
            (index == widget.initialIndex ? widget.initialEpisodeNumber : null);
        MovieBoxShortEpisode? selectedEpisode;
        if (wantedSeason != null && wantedEpisode != null) {
          for (final episode in availableEpisodes) {
            if (episode.season == wantedSeason &&
                episode.episode == wantedEpisode) {
              selectedEpisode = episode;
              break;
            }
          }
        }
        if (selectedEpisode == null && wantedSeason != null) {
          for (final episode in availableEpisodes) {
            if (episode.season == wantedSeason) {
              selectedEpisode = episode;
              break;
            }
          }
        }
        selectedEpisode ??= availableEpisodes.first;
        seasonNumber = selectedEpisode.season;
        episodeNumber = selectedEpisode.episode;
      }

      if (mounted && requestToken == _requestToken) {
        setState(() {
          _availableEpisodes = availableEpisodes;
          _activeSeasonNumber =
              movie.movieBoxIsSeries ? seasonNumber : null;
          _activeEpisodeNumber =
              movie.movieBoxIsSeries ? episodeNumber : null;
        });
      }

      final streamResult = await MovieBoxService.streams(
        detail,
        season: seasonNumber,
        episode: episodeNumber,
        isSeries: movie.movieBoxIsSeries,
        forceRefresh: false,
      ).timeout(const Duration(seconds: 25));
      if (_disposed || requestToken != _requestToken) return;

      final rawLinks = streamResult['links'] as List? ?? const [];
      final links = rawLinks
          .whereType<Map>()
          .map((link) => Map<String, dynamic>.from(link))
          .where((link) {
            final uri = Uri.tryParse((link['url'] ?? '').toString().trim());
            return uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host.isNotEmpty;
          })
          .toList(growable: false);
      if (links.isEmpty) {
        throw StateError('MovieBox did not return a playable short video.');
      }

      final languages = links
          .map((link) => (link['label'] ?? '').toString().split('·').first.trim())
          .where((language) => language.isNotEmpty)
          .toSet()
          .toList(growable: false);
      final preferredLanguage = languages.contains('Original')
          ? 'Original'
          : (languages.isNotEmpty ? languages.first : '');
      final candidates = links
          .where((link) => preferredLanguage.isEmpty ||
              (link['label'] ?? '').toString().split('·').first.trim() ==
                  preferredLanguage)
          .toList()
        ..sort((a, b) => _qualityRank(b).compareTo(_qualityRank(a)));

      Object? lastError;
      for (final link in candidates.take(5)) {
        if (_disposed || requestToken != _requestToken) return;
        final url = (link['url'] ?? '').toString().trim();
        final headers = _linkHeaders(link);
        try {
          final operation = _playerOperation.then((_) async {
            if (_disposed || requestToken != _requestToken) return;
            await _player.stop();
            if (_disposed || requestToken != _requestToken) return;
            await _player.open(
              Media(url, httpHeaders: headers),
              play: false,
            );
            if (_disposed || requestToken != _requestToken) {
              await _player.stop();
              return;
            }
            await _player.play();
            if (_disposed || requestToken != _requestToken) {
              await _player.stop();
            }
          });
          _playerOperation = operation.catchError((Object _) {});
          await operation;
          if (_disposed || requestToken != _requestToken) return;
          if (mounted) {
            setState(() {
              _loading = false;
              _error = null;
            });
          }
          _scheduleControlsHide();
          if (index + 1 < _items.length) {
            unawaited(_prefetchShort(index + 1));
          }
          return;
        } catch (error) {
          lastError = error;
        }
      }

      throw lastError ?? StateError('No working MovieBox stream was found.');
    } catch (error) {
      if (mounted && !_disposed && requestToken == _requestToken) {
        setState(() {
          _loading = false;
          _error = 'This short could not be played right now. Tap retry to resolve it again.';
        });
        debugPrint('Hot Shorts playback failed for ${movie.title}: $error');
      }
    }
  }

  void _onPageChanged(int index) {
    if (_disposed || index == _activeIndex) return;
    setState(() {
      _activeIndex = index;
      _showControls = true;
      _loading = true;
    });
    unawaited(_loadShort(index));
  }

  Widget _shortArtwork(Movie movie) {
    final imageUrl = movie.posterUrl.isNotEmpty
        ? movie.posterUrl
        : movie.backdropUrl;
    if (imageUrl.isEmpty) return const ColoredBox(color: Colors.black);
    return FlixoraCachedImage(
      imageUrl: imageUrl,
      isOnline: true,
      fit: BoxFit.cover,
      memCacheWidth: 900,
      memCacheHeight: 1600,
      placeholder: const ColoredBox(color: Colors.black),
      fallback: const ColoredBox(color: Colors.black),
    );
  }

  Widget _shortPage(Movie movie, int index) {
    final active = index == _activeIndex;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: active ? _toggleControls : null,
            child: active && !_loading && _error == null
                ? Video(
                    controller: _videoController,
                    fit: BoxFit.cover,
                    controls: NoVideoControls,
                  )
                : _shortArtwork(movie),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Colors.transparent,
                  Color(0xCC000000),
                ],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
        ),
        if (active && _loading)
          const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: gold,
                strokeWidth: 2.5,
              ),
            ),
          ),
        if (active && _error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_outline_rounded,
                    color: gold,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _loadShort(
                      _activeIndex,
                      requestedSeasonNumber: _activeSeasonNumber,
                      requestedEpisodeNumber: _activeEpisodeNumber,
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (active && _showControls)
          Positioned.fill(
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 5,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 27,
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'HOT SHORTS TV',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        if (movie.movieBoxIsSeries)
                          TextButton.icon(
                            onPressed: _showEpisodePicker,
                            icon: const Icon(
                              Icons.list_alt_rounded,
                              size: 17,
                            ),
                            label: const Text('EP'),
                            style: TextButton.styleFrom(
                              foregroundColor: gold,
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        Text(
                          '${index + 1}/${_items.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 78,
                    bottom: 31,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          movie.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 8),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          movie.movieBoxIsSeries &&
                                  _activeSeasonNumber != null &&
                                  _activeEpisodeNumber != null
                              ? 'Short Series · S$_activeSeasonNumber · E$_activeEpisodeNumber'
                              : (movie.movieBoxIsSeries
                                  ? 'Short Series'
                                  : 'Shorts'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'Swipe up for the next short',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 15,
                    bottom: 42,
                    child: IconButton.filled(
                      onPressed: _togglePlayback,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0x99000000),
                        foregroundColor: Colors.white,
                        fixedSize: const Size(48, 48),
                      ),
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 27,
                      ),
                    ),
                  ),
                  if (_duration > Duration.zero)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: (_position.inMilliseconds /
                                  _duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          minHeight: 3,
                          backgroundColor: Colors.white30,
                          valueColor: const AlwaysStoppedAnimation<Color>(gold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _requestToken++;
    _controlsTimer?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _pageController.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No shorts available.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        physics: const PageScrollPhysics(),
        itemCount: _items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) =>
            _shortPage(_items[index], index),
      ),
    );
  }
}

class MovieDetailsScreen extends StatelessWidget {
  final Movie movie;
  final bool isOnline;
  final bool isFavourite;
  final bool isSaved;
  final VoidCallback onShare;
  final VoidCallback onFavourite;
  final VoidCallback onSave;
  final VoidCallback onDownload;
  final VoidCallback onWatch;

  const MovieDetailsScreen({
    super.key,
    required this.movie,
    required this.isOnline,
    required this.isFavourite,
    required this.isSaved,
    required this.onShare,
    required this.onFavourite,
    required this.onSave,
    required this.onDownload,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: bg,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  movie.backdropUrl.isNotEmpty
                      ? FlixoraCachedImage(
                          isOnline: isOnline,
                          imageUrl: movie.backdropUrl,
                          fit: BoxFit.cover,
                        )
                      : Container(color: panel),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, bg],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 115,
                          height: 165,
                          child: movie.posterUrl.isNotEmpty
                              ? FlixoraCachedImage(
                                  isOnline: isOnline,
                                  imageUrl: movie.posterUrl,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: panel,
                                  child: const Icon(
                                    Icons.movie,
                                    color: gold,
                                    size: 40,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 17),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movie.title,
                              style: const TextStyle(
                                color: white,
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              movie.mediaType == 'tv' ? 'TV SERIES' : 'MOVIE',
                              style: const TextStyle(
                                color: gold,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              movie.year,
                              style: const TextStyle(
                                color: ink60,
                              ),
                            ),                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: gold,
                                  size: 18,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  movie.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            if (movie.originCountry.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Country: ${movie.originCountry}',
                                style: const TextStyle(color: ink60),
                              ),
                            ],
                            if (movie.originalLanguage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Language: ${movie.originalLanguage.toUpperCase()}',
                                style: const TextStyle(color: ink60),
                              ),
                            ],
                            if (movie.runtime != null &&
                                movie.runtime! > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '${movie.runtime} min',
                                style: const TextStyle(
                                  color: ink60,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (movie.genres.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: movie.genres
                          .map(
                            (genre) => Chip(
                              label: Text(genre),
                              backgroundColor: panel,
                              labelStyle: const TextStyle(
                                color: goldLight,
                                fontSize: 11,
                              ),
                              side: BorderSide.none,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Overview',
                    style: TextStyle(
                      color: white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    movie.overview.isEmpty
                        ? 'No description available.'
                        : movie.overview,
                    style: const TextStyle(
                      color: ink70,
                      height: 1.6,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 25),
                  if (movie.canAttemptPlayback)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: gold,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: onWatch,
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 27,
                        ),
                        label: const Text(
                          'WATCH NOW',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No supported FLIXORA playback source is linked to this title yet.',
                        style: TextStyle(color: ink60, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.playlist_add, color: gold),
                          label: const Text('Add to list', style: TextStyle(color: white)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onShare,
                          icon: const Icon(Icons.share_outlined, color: gold),
                          label: const Text('Share', style: TextStyle(color: white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onFavourite,
                          icon: Icon(
                            isFavourite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: gold,
                          ),
                          label: Text(
                            isFavourite ? 'Liked' : 'Favourite',
                            style: const TextStyle(color: white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onSave,
                          icon: Icon(
                            isSaved
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                            color: gold,
                          ),
                          label: Text(
                            isSaved ? 'Saved' : 'Save',
                            style: const TextStyle(color: white),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (movie.canAttemptPlayback)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onDownload,
                        icon: const Icon(
                          Icons.download,
                          color: gold,
                        ),
                        label: const Text(
                          'Download Movie',
                          style: TextStyle(color: white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MoviePlayerScreen extends StatefulWidget {
  final Movie movie;
  final String? localFilePath;
  final int? localSeasonNumber;
  final int? localEpisodeNumber;
  final List<Movie> recommendedMovies;
  final ValueChanged<Movie>? onMovieSelected;
  final VoidCallback? onSave;
  final VoidCallback? onDownload;
  final void Function(int seasonNumber, int episodeNumber)? onDownloadEpisode;
  final VoidCallback? onViewDownloads;
  final bool isOnline;
  final bool enablePip;

  const MoviePlayerScreen({
    super.key,
    required this.movie,
    this.localFilePath,
    this.localSeasonNumber,
    this.localEpisodeNumber,
    this.recommendedMovies = const [],
    this.onMovieSelected,
    this.onSave,
    this.onDownload,
    this.onDownloadEpisode,
    this.onViewDownloads,
    this.isOnline = true,
    this.enablePip = true,
  });

  @override
  State<MoviePlayerScreen> createState() => _MoviePlayerScreenState();
}

class _MoviePlayerScreenState extends State<MoviePlayerScreen> with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _videoController;
  late Future<Map<String, dynamic>> _movieDetailsFuture;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<Tracks>? _tracksSubscription;
  StreamSubscription<Track>? _activeTrackSubscription;
  StreamSubscription<List<AudioDevice>>? _audioDevicesSubscription;
  StreamSubscription<bool>? _completedSubscription;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<int> _miniPlayerOverlayRevision = ValueNotifier<int>(0);
  bool _isSeeking = false;
  Duration? _seekPreviewPosition;
  Duration? _pendingSeekPosition;
  Timer? _seekSyncTimer;
  int _seekRequestToken = 0;
  int _playerPointerCount = 0;

  bool _isPlaying = false;
  bool _isBuffering = false;
  Timer? _bufferingRecoveryTimer;
  int _bufferingRecoveryAttempts = 0;
  bool _recoveringFromBuffering = false;
  bool _showControls = true;
  bool _isLocked = false;
  bool _isFullscreen = false;
  bool _isMiniPlayer = false;
  bool _isDisposed = false;
  bool _wasPlayingBeforeBackground = false;
  bool _isBackgrounded = false;
  bool _recoveringFromBackground = false;
  Duration _backgroundResumePosition = Duration.zero;
  DateTime? _lastBackgroundResumeAt;
  Future<void> _resumeSaveQueue = Future<void>.value();
  bool _initialized = false;
  bool _isOpening = false;
  bool _playerIsOnline = true;
  Timer? _playerConnectionTimer;
  Timer? _playbackErrorTimer;
  Offset? _miniPlayerOffset;
  List<Map<String, String>> _availableQualities = [];
  String? _selectedQuality;
  String _currentVideoUrl = '';
  bool _loadingQualities = false;
  int _selectedAudioTrackIndex = 0;
  double _audioDelay = 0.0;
  List<Map<String, dynamic>> _tvSeasons = [];
  List<Map<String, dynamic>> _tvEpisodes = [];
  List<Map<String, dynamic>> _movieBoxSeasons = [];
  List<Map<String, dynamic>> _movieBoxAllLinks = [];
  List<Map<String, dynamic>> _movieBoxSubtitles = [];
  final Map<String, Map<String, String>> _movieBoxHeadersByUrl = {};
  List<String> _movieBoxLanguages = [];
  String? _selectedMovieBoxLanguage;
  Map<String, dynamic>? _movieBoxDetail;
  int _selectedSeasonNumber = 1;
  int _selectedEpisodeNumber = 1;
  bool _loadingTvEpisodes = false;
  int _tvSeasonRequestToken = 0;
  int _movieBoxPlaybackRequestToken = 0;
  String? _tvEpisodeError;
  bool _showAllSeasonEpisodes = false;
  bool _loadingAllEpisodes = false;
  List<Map<String, dynamic>> _allTvEpisodes = [];

  String? _errorMessage;

  double _speed = 1.0;
  double _volume = 100;
  double _screenBrightness = 0.5;

  // Subtitle presentation only; stream and playback pipeline remain untouched.
  double _subtitleFontSize = 20;
  String _subtitleTextColor = '#FFFFFF';
  String _subtitleBackgroundColor = '#000000';
  double _subtitleBackgroundOpacity = 0.24;
  double _subtitlePosition = 92;
  double _subtitleDelay = 0;
  double _subtitleOutlineSize = 1.5;
  double _subtitleShadowOffset = 1;
  bool _automaticSubtitleLoading = false;
  bool _subtitleVisibilityEnabled = true;
  String _selectedSubtitleLanguageCode = '';
  bool _subtitleManuallySelected = false;
  String? _automaticSubtitleMessage;
  SubtitleTrack? _automaticEnglishTrack;
  List<Map<String, dynamic>> _automaticSubtitleOptions = [];
  int _automaticSubtitleRequestToken = 0;

  double _videoZoom = 1.0;
  // 0 = Crop, 1 = Full 100% (stretch), 2 = Normal (preserve full frame).
  int _videoFitMode = 2;
  bool _restoringResumePosition = false;
  String? _gestureMode;
  String _gestureFeedback = '';
  Offset? _gestureStartPoint;
  Duration _gestureStartPosition = Duration.zero;
  Duration? _gesturePreviewPosition;
  double _gestureStartBrightness = 0.5;
  double _gestureStartVolume = 100;
  double _gestureStartZoom = 1.0;
  bool _volumeGestureEnabled = true;
  bool _brightnessGestureEnabled = true;
  bool _doubleTapSkipEnabled = true;
  int _doubleTapSkipSeconds = 10;
  double _gestureSensitivity = 1.0;
  Timer? _gestureFeedbackTimer;

  Timer? _hideTimer;

  Tracks _tracks = Tracks(
    video: [VideoTrack.auto()],
    audio: [AudioTrack.auto()],
    subtitle: [SubtitleTrack.auto()],
  );

  List<String> get _resumeKeys {
    final ids = <int>{
      if (widget.movie.tmdbId > 0) widget.movie.tmdbId,
      if (widget.movie.id != 0) widget.movie.id.abs(),
    };
    final episodeKey = widget.movie.mediaType == 'tv'
        ? '_s${_selectedSeasonNumber}_e${_selectedEpisodeNumber}'
        : '';
    return ids
        .map((id) => 'flixora_resume_${widget.movie.mediaType}_$id$episodeKey')
        .toList(growable: false);
  }

  String get _resumeKey => _resumeKeys.first;

  List<String> get _lastEpisodeKeys {
    if (widget.movie.mediaType != 'tv') return const <String>[];
    final ids = <int>{
      if (widget.movie.tmdbId > 0) widget.movie.tmdbId,
      if (widget.movie.id != 0) widget.movie.id.abs(),
    };
    return ids
        .map((id) => 'flixora_last_episode_tv_$id')
        .toList(growable: false);
  }

  Future<List<int>?> _readLastEpisodeSelection() async {
    if (widget.movie.mediaType != 'tv' || widget.localFilePath != null) {
      return null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _lastEpisodeKeys) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final season = _toInt(decoded['season']);
        final episode = _toInt(decoded['episode']);
        if (season > 0 && episode > 0) return <int>[season, episode];
      }
    } catch (error) {
      debugPrint('Could not read last FLIXORA episode: $error');
    }
    return null;
  }

  Future<void> _persistLastEpisodeSelection(
    int season,
    int episode,
  ) async {
    if (widget.movie.mediaType != 'tv' ||
        season <= 0 ||
        episode <= 0) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = jsonEncode(<String, int>{
        'season': season,
        'episode': episode,
      });
      for (final key in _lastEpisodeKeys) {
        await prefs.setString(key, value);
      }
    } catch (error) {
      debugPrint('Could not save last FLIXORA episode: $error');
    }
  }

  String _resolveInitialNetworkUrl() {
    // Admin-managed encodes take priority over the legacy single video_url.
    // This keeps the initial source and the quality selector in sync.
    if (_availableQualities.isNotEmpty) {
      final defaultQuality = _availableQualities
          .cast<Map<String, String>?>()
          .firstWhere(
            (item) => item?['quality']?.trim().toLowerCase() == '720p',
            orElse: () => _availableQualities.first,
          )!;
      _selectedQuality = defaultQuality['quality'];
      return defaultQuality['video_url'] ?? '';
    }

    if (widget.movie.isMovieBox && _availableQualities.isNotEmpty) {
      return _availableQualities.first['video_url'] ?? '';
    }

    final legacyUrl = widget.movie.videoUrl.trim();
    final legacyUri = Uri.tryParse(legacyUrl);
    if (legacyUri != null &&
        (legacyUri.scheme == 'http' || legacyUri.scheme == 'https') &&
        legacyUri.host.isNotEmpty) {
      return legacyUrl;
    }
    return '';
  }

  bool get _validVideoUrl {
    if (widget.localFilePath != null) return true;
    final candidates = <String>[
      _resolveInitialNetworkUrl(),
      ..._availableQualities.map((item) => item['video_url'] ?? ''),
      widget.movie.videoUrl,
    ];
    return candidates.any((url) {
      final uri = Uri.tryParse(url.trim());
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _playerIsOnline = widget.isOnline;
    _selectedSeasonNumber = widget.localSeasonNumber ?? 1;
    _selectedEpisodeNumber = widget.localEpisodeNumber ?? 1;
    _movieDetailsFuture = widget.movie.isMovieBox
        ? Future<Map<String, dynamic>>.value(const <String, dynamic>{})
        : _loadPlayerMovieDetails();
    _player = Player(
      configuration: PlayerConfiguration(
        title: 'FLIXORA',
        // Keep text subtitles on the Flutter SubtitleView overlay. Native libass
        // rendering disables that overlay and needs an Android font asset.
        bufferSize: 64 * 1024 * 1024,
        libass: false,
      ),
    );
    _videoController = VideoController(_player);

    _attachPlayerListeners();
    _loadSubtitlePreferences();
    _loadAudioDelayPreference();
    _loadGesturePreferences();
    _loadApplicationBrightness();
    _startPlayerConnectionMonitor();
    _prepareAndInitializePlayer();
  }

  Future<Map<String, dynamic>> _loadPlayerMovieDetails() async {
    final id = widget.movie.tmdbId;
    if (id <= 0) return {};
    try {
      final isTv = widget.movie.mediaType == 'tv';
      final details = await TmdbService.details(
        id,
        mediaType: isTv ? 'tv' : 'movie',
      );

      if (isTv) {
        final seasons = (details['seasons'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((item) => _toInt(item['season_number']) > 0)
            .toList()
          ..sort((a, b) => _toInt(a['season_number'])
              .compareTo(_toInt(b['season_number'])));
        final firstSeason = seasons.isNotEmpty
            ? _toInt(seasons.first['season_number'])
            : 1;
        final savedSelection = await _readLastEpisodeSelection();
        final savedSeason = savedSelection == null
            ? firstSeason
            : (seasons.any((item) =>
                    _toInt(item['season_number']) == savedSelection[0])
                ? savedSelection[0]
                : firstSeason);
        final savedEpisode = savedSelection?[1];
        if (mounted && !_isDisposed) {
          setState(() {
            _tvSeasons = seasons;
            _selectedSeasonNumber = savedSeason;
            _selectedEpisodeNumber = savedEpisode ?? 1;
          });
        }

        await _loadTvSeasonEpisodes(
          savedSeason,
          preferredEpisode: savedEpisode,
        );
      }
      return details;
    } catch (e) {
      debugPrint('Could not load player title metadata: $e');
      return {};
    }
  }

  Future<void> _loadTvSeasonEpisodes(
    int seasonNumber, {
    int? preferredEpisode,
  }) async {
    if (widget.movie.isMovieBox) {
      await _loadMovieBoxSeasonEpisodes(
        seasonNumber,
        resolveStreams: true,
        preferredEpisode: preferredEpisode,
      );
      return;
    }
    if (widget.movie.tmdbId <= 0 || _isDisposed) return;
    final requestToken = ++_tvSeasonRequestToken;
    if (mounted) {
      setState(() {
        _loadingTvEpisodes = true;
        _tvEpisodeError = null;
        _selectedSeasonNumber = seasonNumber;
        _selectedEpisodeNumber = preferredEpisode ?? 1;
      });
    }
    List<Map<String, dynamic>> episodes = [];
    String? errorMessage;
    try {
      final season = await TmdbService.seasonDetails(
        widget.movie.tmdbId,
        seasonNumber,
      );
      episodes = (season['episodes'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
        ..sort((a, b) => _toInt(a['episode_number'])
            .compareTo(_toInt(b['episode_number'])));
    } catch (error) {
      debugPrint('Could not load TV season $seasonNumber: $error');
      errorMessage = 'Episode details are temporarily unavailable.';
    }
    final firstEpisode = episodes.isNotEmpty
        ? _toInt(episodes.first['episode_number'])
        : 1;
    final selectedEpisode = preferredEpisode != null &&
            episodes.any((item) =>
                _toInt(item['episode_number']) == preferredEpisode)
        ? preferredEpisode
        : firstEpisode;
    if (!mounted || _isDisposed || requestToken != _tvSeasonRequestToken) return;
    setState(() {
      _tvEpisodes = episodes;
      _selectedEpisodeNumber = selectedEpisode;
      _loadingTvEpisodes = false;
      _tvEpisodeError = errorMessage;
    });
    await _persistLastEpisodeSelection(seasonNumber, selectedEpisode);
  }

  void _selectTvEpisode(int episodeNumber) {
    if (episodeNumber <= 0 ||
        episodeNumber == _selectedEpisodeNumber ||
        _loadingQualities ||
        _isOpening) return;
    // Persist the currently selected episode before changing the key.
    unawaited(_saveResumePosition(_position));
    setState(() => _selectedEpisodeNumber = episodeNumber);
    unawaited(_persistLastEpisodeSelection(
      _selectedSeasonNumber,
      episodeNumber,
    ));
    if (widget.movie.isMovieBox) {
      unawaited(_loadMovieBoxStreams(
        season: _selectedSeasonNumber,
        episode: episodeNumber,
        openPlayer: true,
      ));
      return;
    }
  }

  List<List<int>> _episodeNavigationEntries() {
    if (!widget.movie.isMovieBox ||
        !widget.movie.movieBoxIsSeries ||
        widget.localFilePath != null) {
      return const <List<int>>[];
    }

    final seasons = _movieBoxSeasons.toList()
      ..sort((a, b) => _toInt(a['se']).compareTo(_toInt(b['se'])));
    final entries = <List<int>>[];
    for (final season in seasons) {
      final seasonNumber = _toInt(season['se']);
      if (seasonNumber <= 0) continue;
      final episodeNumbers = (season['episodes'] as List? ?? const [])
          .map(_toInt)
          .where((number) => number > 0)
          .toSet()
          .toList()
        ..sort();
      for (final episodeNumber in episodeNumbers) {
        entries.add([seasonNumber, episodeNumber]);
      }
    }
    return entries;
  }

  int _episodeNavigationIndex(List<List<int>> entries) => entries.indexWhere(
        (entry) =>
            entry[0] == _selectedSeasonNumber &&
            entry[1] == _selectedEpisodeNumber,
      );

  bool get _hasEpisodeNavigation {
    final entries = _episodeNavigationEntries();
    return entries.length > 1 && _episodeNavigationIndex(entries) >= 0;
  }

  bool _canChangeEpisode(int direction) {
    if (direction == 0 || _loadingQualities || _isOpening || _isDisposed) {
      return false;
    }
    final entries = _episodeNavigationEntries();
    final currentIndex = _episodeNavigationIndex(entries);
    final targetIndex = currentIndex + direction;
    return currentIndex >= 0 &&
        targetIndex >= 0 &&
        targetIndex < entries.length;
  }

  Future<void> _changeEpisodeBy(int direction) async {
    if (!_canChangeEpisode(direction)) return;
    final entries = _episodeNavigationEntries();
    final currentIndex = _episodeNavigationIndex(entries);
    final target = entries[currentIndex + direction];
    final seasonNumber = target[0];
    final episodeNumber = target[1];
    final season = _movieBoxSeasons.firstWhere(
      (item) => _toInt(item['se']) == seasonNumber,
      orElse: () => <String, dynamic>{},
    );
    final episodeNumbers = (season['episodes'] as List? ?? const [])
        .map(_toInt)
        .where((number) => number > 0)
        .toList(growable: false);
    final episodeItems = episodeNumbers
        .map((number) => <String, dynamic>{
              'episode_number': number,
              'name': 'Episode $number',
            })
        .toList(growable: false);

    if (mounted && !_isDisposed) {
      setState(() {
        _selectedSeasonNumber = seasonNumber;
        _selectedEpisodeNumber = episodeNumber;
        _tvEpisodes = episodeItems;
        _loadingTvEpisodes = false;
        _loadingQualities = true;
        _tvEpisodeError = null;
        _errorMessage = null;
      });
      _miniPlayerOverlayRevision.value++;
    }

    await _loadMovieBoxStreams(
      season: seasonNumber,
      episode: episodeNumber,
      openPlayer: true,
    );
  }

  Future<void> _toggleAllEpisodes() async {
    if (_showAllSeasonEpisodes) {
      if (mounted) setState(() => _showAllSeasonEpisodes = false);
      return;
    }
    if (_allTvEpisodes.isNotEmpty) {
      if (mounted) setState(() => _showAllSeasonEpisodes = true);
      return;
    }

    if (mounted) {
      setState(() => _loadingAllEpisodes = true);
    }
    try {
      if (!widget.movie.isMovieBox && _tvSeasons.isEmpty) {
        await _movieDetailsFuture;
        if (!mounted || _isDisposed) return;
      }
      final allEpisodes = <Map<String, dynamic>>[];
      if (widget.movie.isMovieBox && widget.movie.movieBoxIsSeries) {
        for (final entry in _episodeNavigationEntries()) {
          allEpisodes.add(<String, dynamic>{
            'season_number': entry[0],
            'episode_number': entry[1],
            'name': 'Episode ${entry[1]}',
          });
        }
      } else {
        final seasons = _tvSeasons
            .map((season) => _toInt(season['season_number']))
            .where((number) => number > 0)
            .toSet()
            .toList()
          ..sort();
        final results = await Future.wait(
          seasons.map((seasonNumber) async {
            try {
              return await TmdbService.seasonDetails(
                widget.movie.tmdbId,
                seasonNumber,
              );
            } catch (_) {
              return <String, dynamic>{};
            }
          }),
        );
        for (var index = 0; index < results.length; index++) {
          final seasonNumber = seasons[index];
          final episodes = (results[index]['episodes'] as List? ?? const [])
              .whereType<Map>()
              .map((episode) {
                final item = Map<String, dynamic>.from(episode);
                item['season_number'] = seasonNumber;
                return item;
              });
          allEpisodes.addAll(episodes);
        }
      }

      if (allEpisodes.isEmpty) {
        allEpisodes.addAll(_tvEpisodes.map((episode) => <String, dynamic>{
              ...episode,
              'season_number': _selectedSeasonNumber,
            }));
      }
      allEpisodes.sort((a, b) {
        final seasonCompare = _toInt(a['season_number'])
            .compareTo(_toInt(b['season_number']));
        if (seasonCompare != 0) return seasonCompare;
        return _toInt(a['episode_number'])
            .compareTo(_toInt(b['episode_number']));
      });
      if (mounted && !_isDisposed) {
        setState(() {
          _allTvEpisodes = allEpisodes;
          _showAllSeasonEpisodes = true;
        });
      }
    } catch (error) {
      debugPrint('Could not load all FLIXORA episodes: $error');
      if (mounted && !_isDisposed) {
        setState(() => _tvEpisodeError = 'Could not load all episodes. Please try again.');
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _loadingAllEpisodes = false);
      }
    }
  }

  Future<void> _selectEpisodeFromAll(int seasonNumber, int episodeNumber) async {
    if (seasonNumber <= 0 ||
        episodeNumber <= 0 ||
        _loadingQualities ||
        _isOpening ||
        _isDisposed) {
      return;
    }
    if (widget.movie.isMovieBox && widget.movie.movieBoxIsSeries) {
      if (seasonNumber == _selectedSeasonNumber) {
        _selectTvEpisode(episodeNumber);
        return;
      }
      final season = _movieBoxSeasons.cast<Map<String, dynamic>?>().firstWhere(
        (item) => _toInt(item?['se']) == seasonNumber,
        orElse: () => null,
      );
      final episodeNumbers = (season?['episodes'] as List? ?? const [])
          .map(_toInt)
          .where((number) => number > 0)
          .toList(growable: false);
      final episodes = episodeNumbers
          .map((number) => <String, dynamic>{
                'episode_number': number,
                'name': 'Episode $number',
              })
          .toList(growable: false);
      if (!episodeNumbers.contains(episodeNumber)) return;
      unawaited(_saveResumePosition(_position));
      if (mounted) {
        setState(() {
          _selectedSeasonNumber = seasonNumber;
          _selectedEpisodeNumber = episodeNumber;
          _tvEpisodes = episodes;
          _loadingTvEpisodes = false;
          _tvEpisodeError = null;
          _loadingQualities = true;
          _errorMessage = null;
        });
      }
      await _persistLastEpisodeSelection(seasonNumber, episodeNumber);
      await _loadMovieBoxStreams(
        season: seasonNumber,
        episode: episodeNumber,
        openPlayer: true,
      );
      return;
    }

    if (seasonNumber != _selectedSeasonNumber) {
      await _loadTvSeasonEpisodes(
        seasonNumber,
        preferredEpisode: episodeNumber,
      );
    } else {
      _selectTvEpisode(episodeNumber);
    }
  }

  int get _totalTvEpisodeCount {
    if (widget.movie.isMovieBox && widget.movie.movieBoxIsSeries) {
      final actualCount = _episodeNavigationEntries().length;
      if (actualCount > 0) return actualCount;
    }
    final declaredCount = _tvSeasons.fold<int>(
      0,
      (total, season) => total + _toInt(season['episode_count']),
    );
    if (declaredCount > 0) return declaredCount;
    if (_allTvEpisodes.isNotEmpty) return _allTvEpisodes.length;
    return _tvEpisodes.length;
  }

  Widget _tvEpisodeSelector() {
    if (widget.movie.mediaType != 'tv' || widget.localFilePath != null) {
      return const SizedBox.shrink();
    }

    final seasonNumbers = _tvSeasons
        .map((season) => _toInt(season['season_number']))
        .where((number) => number > 0)
        .toSet()
        .toList()
      ..sort();
    if (seasonNumbers.isEmpty) seasonNumbers.add(1);

    final episodeNumbers = _tvEpisodes
        .map((episode) => _toInt(episode['episode_number']))
        .where((number) => number > 0)
        .toSet()
        .toList()
      ..sort();

    final safeSeason = seasonNumbers.contains(_selectedSeasonNumber)
        ? _selectedSeasonNumber
        : seasonNumbers.first;
    final safeEpisode = episodeNumbers.contains(_selectedEpisodeNumber)
        ? _selectedEpisodeNumber
        : (episodeNumbers.isNotEmpty ? episodeNumbers.first : 1);
    final episodeLabel = safeEpisode.toString().padLeft(2, '0');

    final selectedEpisode = _tvEpisodes.cast<Map<String, dynamic>?>().firstWhere(
      (item) => _toInt(item?['episode_number']) == safeEpisode,
      orElse: () => null,
    );
    final selectedEpisodeName =
        (selectedEpisode?['name'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: playerPanel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                color: playerGoldLight,
                size: 18,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Season & Episodes',
                  style: TextStyle(
                    color: playerWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (_loadingTvEpisodes)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: playerGold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            key: ValueKey<int>(safeSeason),
            initialValue: safeSeason,
            dropdownColor: playerPanel,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Season',
              labelStyle: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
              ),
              filled: true,
              fillColor: playerBg,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: playerWhite, fontSize: 13),
            items: seasonNumbers
                .map(
                  (number) => DropdownMenuItem<int>(
                    value: number,
                    child: Text('Season $number'),
                  ),
                )
                .toList(),
            onChanged: (_loadingTvEpisodes || _loadingQualities || _isOpening)
                ? null
                : (number) {
                    if (number != null &&
                        number != _selectedSeasonNumber) {
                      _loadTvSeasonEpisodes(number);
                    }
                  },
          ),
          const SizedBox(height: 13),
          Text(
            _totalTvEpisodeCount > 0
                ? 'Episodes ($_totalTvEpisodeCount)'
                : 'Episodes',
            style: const TextStyle(
              color: playerWhite,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (seasonNumbers.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(
                          _totalTvEpisodeCount > 0
                              ? 'All ($_totalTvEpisodeCount)'
                              : 'All',
                        ),
                        selected: _showAllSeasonEpisodes,
                        showCheckmark: false,
                        onSelected: (_loadingTvEpisodes ||
                                _loadingQualities ||
                                _isOpening ||
                                _loadingAllEpisodes)
                            ? null
                            : (_) => _toggleAllEpisodes(),
                        selectedColor: playerGold.withValues(alpha: 0.22),
                        backgroundColor: playerBg,
                        side: BorderSide(
                          color: _showAllSeasonEpisodes
                              ? playerGold
                              : const Color(0x3DFFFFFF),
                        ),
                        labelStyle: TextStyle(
                          color: _showAllSeasonEpisodes
                              ? playerGoldLight
                              : playerWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 7),
                      if (!_showAllSeasonEpisodes)
                        ...episodeNumbers.map((number) {
                          final selected = number == safeEpisode;
                          return Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: ChoiceChip(
                              label: Text(number.toString().padLeft(2, '0')),
                              selected: selected,
                              showCheckmark: false,
                              onSelected: (_loadingTvEpisodes ||
                                      _loadingQualities ||
                                      _isOpening)
                                  ? null
                                  : (_) => _selectTvEpisode(number),
                              selectedColor: playerGold.withValues(alpha: 0.22),
                              backgroundColor: playerBg,
                              side: BorderSide(
                                color: selected
                                    ? playerGold
                                    : const Color(0x3DFFFFFF),
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? playerGoldLight
                                    : playerWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                if (episodeNumbers.isEmpty &&
                    !_loadingTvEpisodes &&
                    !_showAllSeasonEpisodes)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No episodes available in this season.',
                      style: TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (_loadingAllEpisodes)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: playerGold,
                      backgroundColor: playerBg,
                    ),
                  ),
                if (_showAllSeasonEpisodes && _allTvEpisodes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 190),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: _allTvEpisodes.map((episode) {
                              final season = _toInt(episode['season_number']);
                              final number = _toInt(episode['episode_number']);
                              final selected = season == safeSeason &&
                                  number == safeEpisode;
                              return ChoiceChip(
                                label: Text(
                                  'S$season E${number.toString().padLeft(2, '0')}',
                                ),
                                selected: selected,
                                showCheckmark: false,
                                onSelected: (_loadingTvEpisodes ||
                                        _loadingQualities ||
                                        _isOpening)
                                    ? null
                                    : (_) => _selectEpisodeFromAll(season, number),
                                selectedColor: playerGold.withValues(alpha: 0.22),
                                backgroundColor: playerBg,
                                side: BorderSide(
                                  color: selected
                                      ? playerGold
                                      : const Color(0x3DFFFFFF),
                                ),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? playerGoldLight
                                      : playerWhite,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else if (!_loadingTvEpisodes)
            const Text(
              'No episodes available for this season.',
              style: TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 11,
              ),
            ),
          if (_tvEpisodeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _tvEpisodeError!.replaceAll(RegExp('moviebox', caseSensitive: false), 'FLIXORA'),
              style: const TextStyle(
                color: Color(0xFFFFC56E),
                fontSize: 10,
              ),
            ),
          ],
          if (selectedEpisodeName.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              'S$safeSeason · E$episodeLabel · $selectedEpisodeName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0x99FFFFFF),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatPlayerReleaseDate(String value) {
    final date = DateTime.tryParse(value.trim());
    if (date == null) return value;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _playerMetadataItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: playerGoldLight, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _playerMetadata() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _movieDetailsFuture,
      builder: (context, snapshot) {
        final details = snapshot.data ?? const <String, dynamic>{};

        final rawDate = (details['release_date'] ??
                details['first_air_date'] ??
                widget.movie.releaseDate)
            .toString()
            .trim();
        final releaseDate = rawDate.isNotEmpty
            ? _formatPlayerReleaseDate(rawDate)
            : (widget.movie.year.isNotEmpty && widget.movie.year != 'N/A'
                ? widget.movie.year
                : '');

        final rawRating = details['vote_average'];
        final rating = widget.movie.rating > 0
            ? widget.movie.rating
            : (rawRating is num ? rawRating.toDouble() : 0.0);

        final countries = <String>[];
        final rawCountries = details['production_countries'];
        if (rawCountries is List) {
          for (final item in rawCountries.whereType<Map>()) {
            final country =
                (item['name'] ?? item['iso_3166_1'] ?? '').toString().trim();
            if (country.isNotEmpty && !countries.contains(country)) {
              countries.add(country);
            }
          }
        }
        if (countries.isEmpty && details['origin_country'] is List) {
          countries.addAll(
            (details['origin_country'] as List)
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty),
          );
        }
        if (countries.isEmpty && widget.movie.originCountry.isNotEmpty) {
          countries.add(widget.movie.originCountry);
        }

        final genres = <String>[];
        final rawGenres = details['genres'];
        if (rawGenres is List) {
          for (final item in rawGenres.whereType<Map>()) {
            final genre = (item['name'] ?? '').toString().trim();
            if (genre.isNotEmpty && !genres.contains(genre)) {
              genres.add(genre);
            }
          }
        }
        if (genres.isEmpty) genres.addAll(widget.movie.genres);

        final items = <Widget>[];
        final originalLanguageCode =
            (details['original_language'] ?? '').toString().trim().toLowerCase();
        const originalLanguageNames = <String, String>{
          'en': 'English', 'hi': 'Hindi', 'ur': 'Urdu', 'bn': 'Bangla',
          'ta': 'Tamil', 'te': 'Telugu', 'ml': 'Malayalam', 'kn': 'Kannada',
          'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'es': 'Spanish',
          'fr': 'French', 'de': 'German', 'pt': 'Portuguese', 'ru': 'Russian',
          'ar': 'Arabic', 'tr': 'Turkish',
        };
        final originalLanguageName =
            originalLanguageNames[originalLanguageCode] ??
            (originalLanguageCode.isEmpty ? '' : originalLanguageCode.toUpperCase());
        if (originalLanguageName.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.translate_rounded,
            'Original language: $originalLanguageName',
          ));
        }
        if (rating > 0) {
          items.add(_playerMetadataItem(
            Icons.star_rounded,
            'TMDB ${rating.toStringAsFixed(1)}/10',
          ));
        }
        if (releaseDate.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.calendar_today_rounded,
            releaseDate,
          ));
        }
        if (countries.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.public_rounded,
            countries.take(2).join(', '),
          ));
        }
        items.add(_playerMetadataItem(
          Icons.movie_filter_outlined,
          widget.movie.mediaType == 'tv' ? 'TV Series' : 'Movie',
        ));
        if (genres.isNotEmpty) {
          items.add(_playerMetadataItem(
            Icons.local_offer_outlined,
            genres.take(3).join(' • '),
          ));
        }

        return Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 10),
          child: Wrap(
            spacing: 13,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: items,
          ),
        );
      },
    );
  }

  Future<void> _prepareMovieBoxPlayback({
    Future<void>? playerConfiguration,
    bool forceRefreshDetail = false,
    bool allowStartupRetry = true,
  }) async {
    if (_isDisposed || !_playerIsOnline) {
      if (mounted) {
        setState(() => _errorMessage = 'Connect to the internet to load this title.');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingQualities = true;
        _errorMessage = null;
      });
    }
    try {
      final rawItem = widget.movie.toMovieBoxMap();
      final detailFuture = MovieBoxService.playDetail(
        rawItem,
        forceRefresh: forceRefreshDetail,
      ).timeout(const Duration(seconds: 12));
      final seasonsFuture = widget.movie.movieBoxIsSeries
          ? MovieBoxService.seasons(widget.movie.movieBoxId)
              .timeout(const Duration(seconds: 18))
          : Future<dynamic>.value(const <dynamic>[]);

      // The detail response is required for stream resolution; season metadata
      // is only needed for the selector. Start resolving the selected stream
      // as soon as the required detail is ready instead of waiting for both.
      _movieBoxDetail = Map<String, dynamic>.from(await detailFuture as Map);
      if (_isDisposed) return;

      // Movie playback has no episode selection to restore. Skip the
      // preferences read so stream resolution can start immediately.
      final savedSelection = widget.movie.movieBoxIsSeries
          ? await _readLastEpisodeSelection()
          : null;
      var targetSeason = savedSelection?[0] ?? 1;
      var targetEpisode = savedSelection?[1] ?? 1;

      if (widget.movie.movieBoxIsSeries) {
        if (mounted && !_isDisposed) {
          setState(() {
            _selectedSeasonNumber = targetSeason;
            _selectedEpisodeNumber = targetEpisode;
          });
        }
      }

      final streamFuture = _loadMovieBoxStreams(
        season: widget.movie.movieBoxIsSeries ? targetSeason : 0,
        episode: widget.movie.movieBoxIsSeries ? targetEpisode : 0,
        openPlayer: true,
        playerConfiguration: playerConfiguration,
      );

      if (widget.movie.movieBoxIsSeries) {
        try {
          final rawSeasons = await seasonsFuture;
          _movieBoxSeasons = (rawSeasons as List)
              .whereType<Map>()
              .map((season) => Map<String, dynamic>.from(season))
              .toList(growable: false);
          final normalizedSeasons = _movieBoxSeasons
              .map((season) {
                final episodes = (season['episodes'] as List? ?? const [])
                    .map(_toInt)
                    .where((number) => number > 0)
                    .toList(growable: false);
                return <String, dynamic>{
                  'season_number': _toInt(season['se']),
                  'episode_count': _toInt(season['maxEp']),
                  'episodes': episodes,
                };
              })
              .where((season) => _toInt(season['season_number']) > 0)
              .toList(growable: false)
            ..sort((a, b) => _toInt(a['season_number'])
                .compareTo(_toInt(b['season_number'])));

          if (normalizedSeasons.isNotEmpty) {
            final hasSavedSeason = normalizedSeasons.any((season) =>
                _toInt(season['season_number']) == targetSeason);
            if (!hasSavedSeason) {
              targetSeason = _toInt(normalizedSeasons.first['season_number']);
              final firstEpisodes =
                  normalizedSeasons.first['episodes'] as List? ?? const [];
              targetEpisode = firstEpisodes.isNotEmpty
                  ? _toInt(firstEpisodes.first)
                  : 1;
            } else {
              final selectedSeason = normalizedSeasons.firstWhere((season) =>
                  _toInt(season['season_number']) == targetSeason);
              final validEpisodes =
                  selectedSeason['episodes'] as List? ?? const [];
              if (!validEpisodes.contains(targetEpisode)) {
                targetEpisode = validEpisodes.isNotEmpty
                    ? _toInt(validEpisodes.first)
                    : 1;
              }
            }

            final selectedSeason = normalizedSeasons.firstWhere((season) =>
                _toInt(season['season_number']) == targetSeason);
            final episodeNumbers =
                selectedSeason['episodes'] as List? ?? const [];
            final episodeItems = episodeNumbers
                .map((number) => <String, dynamic>{
                      'episode_number': _toInt(number),
                      'name': 'Episode ${_toInt(number)}',
                    })
                .toList(growable: false);

            if (mounted && !_isDisposed) {
              setState(() {
                _tvSeasons = normalizedSeasons;
                _selectedSeasonNumber = targetSeason;
                _selectedEpisodeNumber = targetEpisode;
                _tvEpisodes = episodeItems;
              });
            }
            await _persistLastEpisodeSelection(targetSeason, targetEpisode);

            // Correct an unavailable saved/default episode only after the
            // metadata confirms the valid first episode for that season.
            final initialSelectionWasCorrect =
                savedSelection == null
                    ? targetSeason == 1 && targetEpisode == 1
                    : savedSelection[0] == targetSeason &&
                        savedSelection[1] == targetEpisode;
            if (!initialSelectionWasCorrect) {
              await _loadMovieBoxStreams(
                season: targetSeason,
                episode: targetEpisode,
                openPlayer: true,
                playerConfiguration: playerConfiguration,
              );
            }
          }
        } catch (error) {
          // A slow season-list request must not prevent the stream from playing.
          debugPrint('MovieBox season metadata unavailable during startup: $error');
        }
      }

      await streamFuture;
    } catch (error) {
      if (allowStartupRetry && mounted && !_isDisposed) {
        debugPrint('MovieBox startup failed; retrying with fresh playback details: $error');
        await _prepareMovieBoxPlayback(
          playerConfiguration: playerConfiguration,
          forceRefreshDetail: true,
          allowStartupRetry: false,
        );
        return;
      }
      debugPrint('MovieBox playback preparation failed: $error');
      if (mounted && !_isDisposed && !_initialized) {
        setState(() {
          _errorMessage = 'Unable to load this video right now. Please retry.';
          _tvEpisodeError = error.toString();
        });
      }
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _loadingQualities = false);
      }
    }
  }

  Future<void> _loadMovieBoxSeasonEpisodes(
    int seasonNumber, {
    required bool resolveStreams,
    int? preferredEpisode,
  }) async {
    if (_isDisposed) return;
    final requestToken = resolveStreams
        ? ++_movieBoxPlaybackRequestToken
        : _movieBoxPlaybackRequestToken;
    if (resolveStreams && _initialized) {
      _playbackErrorTimer?.cancel();
      try {
        await _player.pause();
      } catch (_) {}
      if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) return;
    }

    final season = _movieBoxSeasons.cast<Map<String, dynamic>?>().firstWhere(
      (item) => _toInt(item?['se']) == seasonNumber,
      orElse: () => null,
    );
    final episodeNumbers = (season?['episodes'] as List? ?? const [])
        .map(_toInt)
        .where((number) => number > 0)
        .toList(growable: false);
    final episodes = episodeNumbers
        .map((number) => <String, dynamic>{
              'episode_number': number,
              'name': 'Episode $number',
            })
        .toList(growable: false);
    final firstEpisode = episodeNumbers.isNotEmpty ? episodeNumbers.first : 1;
    final selectedEpisode = preferredEpisode != null &&
            episodeNumbers.contains(preferredEpisode)
        ? preferredEpisode
        : firstEpisode;

    if (!mounted || _isDisposed) return;
    // Keep the previous episode's timestamp under its original season/episode key.
    unawaited(_saveResumePosition(_position));
    setState(() {
      _selectedSeasonNumber = seasonNumber;
      _selectedEpisodeNumber = selectedEpisode;
      _tvEpisodes = episodes;
      _loadingTvEpisodes = false;
      _tvEpisodeError = episodes.isEmpty
          ? 'No episode list was returned for this season.'
          : null;
      if (resolveStreams) {
        _loadingQualities = true;
        _errorMessage = null;
      }
    });
    await _persistLastEpisodeSelection(seasonNumber, selectedEpisode);

    if (resolveStreams) {
      await _loadMovieBoxStreams(
        season: seasonNumber,
        episode: selectedEpisode,
        openPlayer: true,
      );
    }
  }

  String _movieBoxVariant(Map<String, dynamic> link) {
    final label = (link['label'] ?? '').toString();
    return label.split(' · ').first.trim();
  }

  List<Map<String, String>> _prioritizeMovieBoxQualities(
    Iterable<Map<String, String>> values,
  ) {
    // Preserve MovieBox's original source order and all valid qualities.
    // Do not filter or reorder streams based on resolution.
    return values.toList(growable: false);
  }

  List<Map<String, String>> _movieBoxOptionsForLanguage(String language) {
    final options = _movieBoxAllLinks.where((link) {
      return _movieBoxVariant(link) == language;
    }).map((link) {
      final headers = link['headers'] is Map
          ? Map<String, String>.from(
              (link['headers'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            )
          : <String, String>{};
      return <String, String>{
        'quality': (link['label'] ?? 'Original').toString(),
        'video_url': (link['url'] ?? '').toString(),
        'headers': jsonEncode(headers),
      };
    }).where((item) => item['video_url']!.isNotEmpty);
    return _prioritizeMovieBoxQualities(options);
  }

  Future<void> _loadMovieBoxStreams({
    required int season,
    required int episode,
    required bool openPlayer,
    Future<void>? playerConfiguration,
  }) async {
    if (openPlayer) {
      _bufferingRecoveryTimer?.cancel();
      _bufferingRecoveryAttempts = 0;
      _recoveringFromBuffering = false;
    }
    final detail = _movieBoxDetail;
    if (detail == null || _isDisposed) return;
    if (widget.movie.movieBoxIsSeries && season > 0 && episode > 0) {
      unawaited(_persistLastEpisodeSelection(season, episode));
    }
    final requestToken = ++_movieBoxPlaybackRequestToken;

    if (openPlayer && _initialized) {
      _playbackErrorTimer?.cancel();
      try {
        await _player.pause();
      } catch (_) {}
      if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) return;
      if (mounted) {
        setState(() {
          _updatePosition(Duration.zero);
          _duration = Duration.zero;
          _errorMessage = null;
          _tvEpisodeError = null;
        });
      }
    }

    if (mounted) {
      setState(() {
        _loadingQualities = true;
        _tvEpisodeError = null;
        // Never expose a previous episode's MovieBox subtitle URLs while the
        // newly selected episode is resolving its own stream metadata.
        _movieBoxSubtitles = [];
        _automaticSubtitleOptions = [];
        _automaticSubtitleMessage = 'Loading available subtitles…';
      });
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    }

    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        Map<String, dynamic> result;
        try {
          result = await MovieBoxService.streamsFast(
            detail,
            season: season,
            episode: episode,
            isSeries: widget.movie.movieBoxIsSeries,
            forceRefresh: attempt > 0,
          ).timeout(const Duration(seconds: 12));
        } catch (error) {
          if (attempt == 0) {
            debugPrint('MovieBox stream request failed; refreshing once: $error');
            continue;
          }
          rethrow;
        }
        if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) return;

        final rawLinks = result['links'] as List? ?? const [];
        final links = rawLinks
            .whereType<Map>()
            .map((link) => Map<String, dynamic>.from(link))
            .where((link) {
              final uri = Uri.tryParse((link['url'] ?? '').toString());
              return uri != null &&
                  (uri.scheme == 'http' || uri.scheme == 'https') &&
                  uri.host.isNotEmpty;
            })
            .toList(growable: false);
        if (links.isEmpty) {
          throw StateError('No HLS, DASH or MP4 streams were returned for this episode.');
        }

        // MovieBox/WeFeed subtitle metadata is not consistent across
        // client/API versions. Normalize the supported list containers here
        // instead of requiring one exact "subtitles" + "url" shape.
        final subtitles = _extractMovieBoxSubtitleItems(result);
        final languages = <String>[];
        _movieBoxHeadersByUrl.clear();
        for (final link in links) {
          final language = _movieBoxVariant(link);
          if (language.isNotEmpty && !languages.contains(language)) {
            languages.add(language);
          }
          final url = (link['url'] ?? '').toString();
          final rawHeaders = link['headers'];
          if (url.isNotEmpty && rawHeaders is Map) {
            _movieBoxHeadersByUrl[url] = Map<String, String>.from(
              rawHeaders.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
            );
          }
        }

        final selectedLanguage = _selectedMovieBoxLanguage != null &&
                languages.contains(_selectedMovieBoxLanguage)
            ? _selectedMovieBoxLanguage!
            : (languages.contains('Original') ? 'Original' : languages.first);
        final options = _prioritizeMovieBoxQualities(
          links.where((link) {
            return _movieBoxVariant(link) == selectedLanguage;
          }).map((link) {
            final headers = link['headers'] is Map
                ? Map<String, String>.from(
                    (link['headers'] as Map).map(
                      (key, value) =>
                          MapEntry(key.toString(), value.toString()),
                    ),
                  )
                : <String, String>{};
            return <String, String>{
              'quality': (link['label'] ?? 'Original').toString(),
              'video_url': (link['url'] ?? '').toString(),
              'headers': jsonEncode(headers),
            };
          }).where((item) => item['video_url']!.isNotEmpty),
        );
        if (options.isEmpty) {
          throw StateError('No playable quality was returned for $selectedLanguage.');
        }

        if (!mounted || _isDisposed ||
            requestToken != _movieBoxPlaybackRequestToken) return;
        setState(() {
          _movieBoxAllLinks = links;
          _movieBoxSubtitles = subtitles;
          _automaticSubtitleOptions = _movieBoxSubtitleOptions(subtitles);
          _movieBoxLanguages = languages;
          _selectedMovieBoxLanguage = selectedLanguage;
          _availableQualities = options;
          _selectedQuality = options.first['quality'];
          _errorMessage = null;
        });

        if (!openPlayer) return;
        final opened = await _openMovieBoxEpisode(
          options.first,
          requestToken,
          playerConfiguration: playerConfiguration,
        );
        if (opened) {
          unawaited(_enrichMovieBoxStreamsInBackground(
            detail,
            season: season,
            episode: episode,
            requestToken: requestToken,
          ));
          return;
        }
        if (attempt == 1) {
          throw StateError('Fresh MovieBox links were also unavailable.');
        }
      }
    } catch (error) {
      debugPrint('MovieBox stream resolution failed: $error');
      if (mounted && !_isDisposed &&
          requestToken == _movieBoxPlaybackRequestToken) {
        setState(() {
          _tvEpisodeError = error.toString();
          _errorMessage = 'Unable to play this video right now.';
        });
        if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
      }
    } finally {
      if (mounted && !_isDisposed &&
          requestToken == _movieBoxPlaybackRequestToken) {
        setState(() => _loadingQualities = false);
        if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
      }
    }
  }

  Future<void> _enrichMovieBoxStreamsInBackground(
    Map<String, dynamic> detail, {
    required int season,
    required int episode,
    required int requestToken,
  }) async {
    try {
      final result = await MovieBoxService.streams(
        detail,
        season: season,
        episode: episode,
        isSeries: widget.movie.movieBoxIsSeries,
      ).timeout(const Duration(seconds: 30));
      if (!mounted || _isDisposed ||
          requestToken != _movieBoxPlaybackRequestToken) return;

      final links = (result['links'] as List? ?? const [])
          .whereType<Map>()
          .map((link) => Map<String, dynamic>.from(link))
          .where((link) {
            final uri = Uri.tryParse((link['url'] ?? '').toString());
            return uri != null &&
                (uri.scheme == 'http' || uri.scheme == 'https') &&
                uri.host.isNotEmpty;
          }).toList(growable: false);
      if (links.isEmpty) return;

      final subtitles = _extractMovieBoxSubtitleItems(result);
      final languages = <String>[];
      for (final link in links) {
        final language = _movieBoxVariant(link);
        if (language.isNotEmpty && !languages.contains(language)) {
          languages.add(language);
        }
        final url = (link['url'] ?? '').toString();
        final rawHeaders = link['headers'];
        if (url.isNotEmpty && rawHeaders is Map) {
          _movieBoxHeadersByUrl[url] = Map<String, String>.from(
            rawHeaders.map((key, value) =>
                MapEntry(key.toString(), value.toString())),
          );
        }
      }
      final selectedLanguage = _selectedMovieBoxLanguage != null &&
              languages.contains(_selectedMovieBoxLanguage)
          ? _selectedMovieBoxLanguage!
          : (languages.contains('Original') ? 'Original' : languages.first);
      final options = _prioritizeMovieBoxQualities(
        links.where((link) => _movieBoxVariant(link) == selectedLanguage)
            .map((link) {
          final headers = link['headers'] is Map
              ? Map<String, String>.from((link['headers'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value.toString())))
              : <String, String>{};
          return <String, String>{
            'quality': (link['label'] ?? 'Original').toString(),
            'video_url': (link['url'] ?? '').toString(),
            'headers': jsonEncode(headers),
          };
        }).where((item) => item['video_url']!.isNotEmpty),
      );
      if (!mounted || _isDisposed ||
          requestToken != _movieBoxPlaybackRequestToken) return;
      setState(() {
        _movieBoxAllLinks = links;
        _movieBoxSubtitles = subtitles;
        _automaticSubtitleOptions = _movieBoxSubtitleOptions(subtitles);
        _movieBoxLanguages = languages;
        _selectedMovieBoxLanguage = selectedLanguage;
        if (options.isNotEmpty) _availableQualities = options;
      });
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    } catch (error) {
      // Playback is already running; optional language/subtitle enrichment
      // must never interrupt or replace the active stream.
      debugPrint('MovieBox background enrichment unavailable: $error');
    }
  }

  Future<bool> _openMovieBoxEpisode(
    Map<String, String> item,
    int requestToken, {
    Future<void>? playerConfiguration,
  }) async {
    final candidates = <Map<String, String>>[
      item,
      ..._availableQualities.where(
        (quality) => quality['video_url'] != item['video_url'],
      ),
    ].take(4).toList(growable: false);
    Object? lastError;

    _isOpening = true;
    _automaticSubtitleRequestToken++;
    _automaticSubtitleLoading = false;
    _automaticEnglishTrack = null;
    _automaticSubtitleMessage = null;
    _subtitleManuallySelected = false;
    _tracks = Tracks(
      video: [VideoTrack.auto()],
      audio: [AudioTrack.auto()],
      subtitle: [SubtitleTrack.auto()],
    );
    _currentVideoUrl = '';
    _playbackErrorTimer?.cancel();
    if (mounted) {
      setState(() {
        _initialized = false;
        _errorMessage = null;
        _tvEpisodeError = null;
      });
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    }
    try {
      // Resolve MovieBox stream metadata while MPV network settings are
      // applied. Wait only immediately before opening the native stream.
      if (playerConfiguration != null) await playerConfiguration;
      if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) {
        return false;
      }
      for (final candidate in candidates) {
        if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) {
          return false;
        }

        final url = candidate['video_url']?.trim() ?? '';
        final uri = Uri.tryParse(url);
        if (url.isEmpty ||
            uri == null ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.host.isEmpty) {
          lastError = StateError('The selected episode returned an invalid stream URL.');
          continue;
        }

        try {
          await _player.open(
            Media(url, httpHeaders: _headersForQuality(candidate)),
            play: true,
          );
          if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) {
            return false;
          }

          _currentVideoUrl = url;
          _updatePosition(Duration.zero);
          _duration = Duration.zero;
          _selectedAudioTrackIndex = 0;
          if (_isDisposed || requestToken != _movieBoxPlaybackRequestToken) {
            return false;
          }
          if (mounted) {
            setState(() {
              _initialized = true;
              _selectedQuality = candidate['quality'];
              _errorMessage = null;
              _tvEpisodeError = null;
            });
            if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
          }
          await _restoreResumePosition();
          _subtitleManuallySelected = false;
          _automaticEnglishTrack = null;
          _automaticSubtitleMessage = null;
          unawaited(_ensureAutomaticEnglishSubtitle());
          _startHideTimer();
          _prewarmNextMovieBoxEpisode();
          return true;
        } catch (error) {
          lastError = error;
          try {
            await _player.stop();
          } catch (_) {}
        }
      }

      throw lastError ?? StateError('No working stream quality was returned.');
    } catch (error) {
      if (mounted &&
          !_isDisposed &&
          requestToken == _movieBoxPlaybackRequestToken) {
        setState(() {
          _errorMessage = 'Could not start playback. Please try again.';
          _tvEpisodeError = error.toString();
        });
        if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
      }
      return false;
    } finally {
      if (requestToken == _movieBoxPlaybackRequestToken) {
        _isOpening = false;
      }
    }
  }

  void _prewarmNextMovieBoxEpisode() {
    if (!_playerIsOnline ||
        !widget.movie.movieBoxIsSeries ||
        _movieBoxDetail == null ||
        _movieBoxSeasons.isEmpty) {
      return;
    }

    final seasons = _movieBoxSeasons.toList()
      ..sort((a, b) => _toInt(a['se']).compareTo(_toInt(b['se'])));
    final currentIndex = seasons.indexWhere(
      (season) => _toInt(season['se']) == _selectedSeasonNumber,
    );
    if (currentIndex < 0) return;

    var nextSeason = _selectedSeasonNumber;
    var nextEpisode = 0;
    final currentEpisodes = (seasons[currentIndex]['episodes'] as List? ?? const [])
        .map(_toInt)
        .where((number) => number > 0)
        .toList(growable: false);
    for (final number in currentEpisodes) {
      if (number > _selectedEpisodeNumber) {
        nextEpisode = number;
        break;
      }
    }

    if (nextEpisode == 0 && currentIndex + 1 < seasons.length) {
      nextSeason = _toInt(seasons[currentIndex + 1]['se']);
      final nextEpisodes =
          (seasons[currentIndex + 1]['episodes'] as List? ?? const [])
              .map(_toInt)
              .where((number) => number > 0)
              .toList(growable: false);
      if (nextEpisodes.isNotEmpty) nextEpisode = nextEpisodes.first;
    }
    if (nextSeason <= 0 || nextEpisode <= 0) return;

    final detail = _movieBoxDetail!;
    unawaited(() async {
      try {
        await MovieBoxService.streamsFast(
          detail,
          season: nextSeason,
          episode: nextEpisode,
          isSeries: true,
        ).timeout(const Duration(seconds: 18));
      } catch (_) {}
    }());
  }

  Future<void> _selectMovieBoxLanguage(String language) async {
    if (language == _selectedMovieBoxLanguage || _isDisposed) return;
    final options = _movieBoxOptionsForLanguage(language);
    if (options.isEmpty) return;
    setState(() {
      _selectedMovieBoxLanguage = language;
      _availableQualities = options;
      _selectedQuality = options.first['quality'];
    });
    if (_initialized) {
      await _changeVideoQuality(options.first);
    }
  }

  Widget _movieBoxLanguageSelector() {
    if (!widget.movie.isMovieBox || _movieBoxLanguages.length < 2) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: playerPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.translate_rounded, color: playerGoldLight, size: 18),
          const SizedBox(width: 9),
          const Text(
            'Language',
            style: TextStyle(
              color: playerWhite,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _movieBoxLanguages.contains(_selectedMovieBoxLanguage)
                    ? _selectedMovieBoxLanguage
                    : _movieBoxLanguages.first,
                isExpanded: true,
                dropdownColor: playerPanel,
                style: const TextStyle(
                  color: playerGoldLight,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                items: _movieBoxLanguages.map((language) {
                  return DropdownMenuItem<String>(
                    value: language,
                    child: Text(language, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: _loadingQualities
                    ? null
                    : (language) {
                        if (language != null) {
                          _selectMovieBoxLanguage(language);
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareAndInitializePlayer() async {
    // Start MPV network configuration immediately and overlap it with source
    // and quality resolution. It is awaited only before the native player opens.
    final playerConfiguration = _configureVolumeBoost();
    if (_isDisposed) return;

    // A downloaded MovieBox movie/episode must play from local storage without
    // trying to resolve online seasons or CDN streams again.
    if (widget.localFilePath != null) {
      await playerConfiguration;
      if (_isDisposed) return;
      await _initializePlayer();
      return;
    }

    if (widget.movie.isMovieBox) {
      await _prepareMovieBoxPlayback(
        playerConfiguration: playerConfiguration,
      );
      return;
    }

    if (widget.movie.mediaType == 'tv') {
      final savedSelection = await _readLastEpisodeSelection();
      if (savedSelection != null && mounted && !_isDisposed) {
        _selectedSeasonNumber = savedSelection[0];
        _selectedEpisodeNumber = savedSelection[1];
      }
    }

    // Start a valid direct source immediately while quality metadata loads.
    // If the movie has no legacy URL, retry once the quality list is ready.
    final qualitiesFuture = _loadVideoQualities();
    await playerConfiguration;
    if (_isDisposed) return;
    await _initializePlayer();
    if (!mounted || _isDisposed) return;
    await qualitiesFuture;
    if (!mounted || _isDisposed) return;
    if (!_initialized && _validVideoUrl) {
      await _initializePlayer();
      if (!mounted || _isDisposed) return;
    }

    if (!_validVideoUrl && widget.localFilePath == null && _errorMessage == null) {
      setState(() {
        _errorMessage =
            'No playable video source is available for this title.';
      });
    }
  }

  Future<void> _loadVideoQualities() async {
    final client = supabaseClient;
    final movieId = widget.movie.sourceId;
    if (client == null || movieId <= 0 || widget.localFilePath != null) return;

    if (mounted) setState(() => _loadingQualities = true);
    try {
      final rows = await client
          .from('movie_video_qualities')
          .select('quality, video_url')
          .eq('movie_id', movieId);

      final qualities = (rows as List)
          .whereType<Map>()
          .map((row) => {
                'quality': (row['quality'] ?? '').toString(),
                'video_url': (row['video_url'] ?? '').toString(),
              })
          .where((row) =>
              row['quality']!.isNotEmpty && row['video_url']!.isNotEmpty)
          .toList();

      final sortedQualities = VideoQualityService.sort(
        qualities, (item) => item['quality']!,
      );

      if (!mounted || _isDisposed) return;
      setState(() {
        _availableQualities = sortedQualities;
        if (sortedQualities.isNotEmpty) {
          final current = sortedQualities.where(
            (item) => item['video_url'] == widget.movie.videoUrl,
          );
          _selectedQuality = current.isNotEmpty
              ? current.first['quality']
              : null;
        }
      });
    } catch (e) {
      debugPrint('Could not load video qualities: $e');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _loadingQualities = false);
      }
    }
  }

  Map<String, String> _headersForQuality(Map<String, String> item) {
    try {
      final decoded = jsonDecode(item['headers'] ?? '{}');
      if (decoded is Map) {
        return Map<String, String>.from(
          decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
        );
      }
    } catch (_) {}
    return const <String, String>{};
  }

  Future<void> _changeVideoQuality(Map<String, String> item) async {
    _playbackErrorTimer?.cancel();
    final url = item['video_url']?.trim() ?? '';
    if (url.isEmpty || _isDisposed || widget.localFilePath != null) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return;
    }

    if (_isOpening || url == _currentVideoUrl) return;
    _bufferingRecoveryTimer?.cancel();
    _bufferingRecoveryAttempts = 0;
    _recoveringFromBuffering = false;
    final requestToken = _movieBoxPlaybackRequestToken;
    final previousQuality = _selectedQuality;
    final previousUrl = _currentVideoUrl;
    final wasPlaying = _isPlaying;
    final resumeAt = _position;
    _isOpening = true;

    try {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _initialized = false;
        });
      }

      await _player.open(
        Media(url, httpHeaders: _headersForQuality(item)),
        play: false,
      );
      if (!mounted || _isDisposed ||
          requestToken != _movieBoxPlaybackRequestToken) return;
      if (resumeAt > Duration.zero) await _player.seek(resumeAt);
      if (requestToken != _movieBoxPlaybackRequestToken) return;
      if (wasPlaying) {
        await _player.play();
      } else {
        await _player.pause();
      }
      if (requestToken != _movieBoxPlaybackRequestToken) return;

      _currentVideoUrl = url;
      if (mounted && !_isDisposed) {
        setState(() {
          _selectedQuality = item['quality'];
          _initialized = true;
        });
      }
    } catch (error) {
      // A newer episode selection cancels this quality request; it must not
      // restore or restart the previous episode over the user's selection.
      if (requestToken != _movieBoxPlaybackRequestToken) return;

      var restored = false;
      if (previousUrl.isNotEmpty && !_isDisposed) {
        try {
          await _player.open(
            Media(
              previousUrl,
              httpHeaders: _movieBoxHeadersByUrl[previousUrl] ??
                  const <String, String>{},
            ),
            play: false,
          );
          if (requestToken != _movieBoxPlaybackRequestToken) return;
          if (resumeAt > Duration.zero) await _player.seek(resumeAt);
          if (requestToken != _movieBoxPlaybackRequestToken) return;
          if (wasPlaying) {
            await _player.play();
          } else {
            await _player.pause();
          }
          if (requestToken != _movieBoxPlaybackRequestToken) return;
          _currentVideoUrl = previousUrl;
          restored = true;
        } catch (_) {
          restored = false;
        }
      }

      if (mounted && !_isDisposed &&
          requestToken == _movieBoxPlaybackRequestToken) {
        setState(() {
          _selectedQuality = previousQuality;
          _initialized = restored;
          _errorMessage = restored
              ? 'Could not switch quality. Previous playback was restored.'
              : 'Could not switch quality or restore the previous video.';
        });
      }
    } finally {
      if (requestToken == _movieBoxPlaybackRequestToken) {
        _isOpening = false;
      }
    }
  }

  void _startPlayerConnectionMonitor() {
    _refreshPlayerConnection();
    _playerConnectionTimer?.cancel();
    _playerConnectionTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshPlayerConnection(),
    );
  }

  Future<void> _refreshPlayerConnection() async {
    if (!mounted || _isDisposed) return;

    final online = await InternetService.isOnline();
    if (!mounted || _isDisposed || online == _playerIsOnline) return;

    setState(() => _playerIsOnline = online);
    if (online &&
        widget.localFilePath == null &&
        widget.movie.isMovieBox &&
        !_validVideoUrl) {
      unawaited(_prepareAndInitializePlayer());
    }
  }

  String _friendlyPlaybackError(String raw) {
    final message = raw.toLowerCase();
    final int code;
    if (message.contains('401') ||
        message.contains('403') ||
        message.contains('forbidden')) {
      code = 6;
    } else if (message.contains('timeout') || message.contains('timed out')) {
      code = 3;
    } else if (message.contains('subtitle')) {
      code = 7;
    } else if (message.contains('404') || message.contains('not found')) {
      code = 2;
    } else if (message.contains('unsupported') ||
        message.contains('demuxer') ||
        message.contains('format')) {
      code = 1;
    } else if (message.contains('decode') || message.contains('codec')) {
      code = 5;
    } else if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('broken pipe')) {
      code = 4;
    } else {
      code = 0;
    }
    return RustPlaybackCore.playbackError(code);
  }

  Future<void> _recoverFromStalledBuffering() async {
    if (_isDisposed ||
        !_playerIsOnline ||
        !_isBuffering ||
        !_isPlaying ||
        _isOpening ||
        _recoveringFromBuffering ||
        _bufferingRecoveryAttempts >= 1 ||
        widget.localFilePath != null ||
        _currentVideoUrl.isEmpty) {
      return;
    }

    final position = _pendingSeekPosition ??
        (_player.state.position > Duration.zero
            ? _player.state.position
            : _position);
    _bufferingRecoveryAttempts++;
    _recoveringFromBuffering = true;
    debugPrint('FLIXORA buffering watchdog: attempting in-place playback recovery.');
    try {
      // Keep the active source, headers, audio/subtitle tracks and Player
      // settings intact; do not reopen the stream or replace its provider.
      await _saveResumePosition(position);
      // Reassert playback in place. Pause/reopen/seek cycles can issue another
      // network request and make an existing stream stall worse.
      if (!mounted || _isDisposed) return;
      await _player.play();
    } catch (error) {
      debugPrint('FLIXORA buffering recovery failed: $error');
    } finally {
      _recoveringFromBuffering = false;
    }
  }

  void _handlePlayerError(String value) {
    debugPrint('FLIXORA playback event: $value');
    _playbackErrorTimer?.cancel();
    final positionAtError = _position;
    _playbackErrorTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted || _isDisposed) return;
      if (_isOpening) {
        _handlePlayerError(value);
        return;
      }
      final recentResume = _lastBackgroundResumeAt != null &&
          DateTime.now().difference(_lastBackgroundResumeAt!) <
              const Duration(seconds: 7);
      if (_recoveringFromBackground || recentResume) {
        debugPrint('Deferring transient playback error during background recovery.');
        return;
      }
      final shouldShow = PlaybackErrorPolicy.shouldShowError(
        isOpening: _isOpening,
        isPlaying: _isPlaying,
        positionAtError: positionAtError,
        currentPosition: _position,
      );
      if (!shouldShow) {
        debugPrint('Ignoring non-fatal player error while playback continues.');
        if (_errorMessage != null) setState(() => _errorMessage = null);
        return;
      }
      setState(() => _errorMessage = _friendlyPlaybackError(value));
    });
  }

  // Listeners are attached once. Retrying playback will not create
  // duplicate stream subscriptions.
  void _updatePosition(Duration value) {
    _position = value;
    _positionNotifier.value = value;
  }

  void _attachPlayerListeners() {
    _positionSubscription = _player.stream.position.listen((value) {
      if (!mounted || _isDisposed || _isSeeking) return;

      final safePosition = _duration > Duration.zero && value > _duration
          ? _duration
          : value;
      final pendingSeek = _pendingSeekPosition;
      if (pendingSeek != null) {
        final difference = (safePosition - pendingSeek).inMilliseconds.abs();
        // Ignore stale time-pos events until mpv has reached the requested
        // seek target. This prevents the timeline snapping back or jumping
        // to the end while a network seek is still resolving.
        if (difference > 2500) return;
        _pendingSeekPosition = null;
        _seekSyncTimer?.cancel();
      }

      // Some streams emit a stale/end position while the demuxer is
      // buffering. Keep the last stable position until playback resumes.
      if (_isBuffering &&
          (safePosition - _position).inMilliseconds.abs() > 2500) {
        return;
      }

      _updatePosition(safePosition);
      if (_errorMessage != null && safePosition > Duration.zero) {
        setState(() => _errorMessage = null);
      }

      if (!_restoringResumePosition && _duration.inSeconds > 0) {
        unawaited(_saveResumePosition(safePosition));
      }
    });

    _durationSubscription = _player.stream.duration.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _duration = value);
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    });

    _playingSubscription = _player.stream.playing.listen((value) {
      if (!mounted || _isDisposed) return;

      setState(() {
        _isPlaying = value;
        if (value && _errorMessage != null) _errorMessage = null;
      });
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
      // Android system PiP is enabled only after the user first
      // minimizes the video inside FLIXORA's own Player.
      unawaited(PictureInPictureService.setEnabled(
        value && widget.enablePip && _isMiniPlayer,
      ));

      if (value) {
        _startHideTimer();
      } else {
        _cancelHideTimer();
        if (!_isMiniPlayer) setState(() => _showControls = true);
      }
    });

    _bufferingSubscription = _player.stream.buffering.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() => _isBuffering = value);
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
      if (value) {
        _bufferingRecoveryTimer?.cancel();
        _bufferingRecoveryTimer = Timer(const Duration(seconds: 10), () {
          if (!mounted || _isDisposed || !_isBuffering) return;
          unawaited(_recoverFromStalledBuffering());
        });
      } else {
        _bufferingRecoveryTimer?.cancel();
        _bufferingRecoveryTimer = null;
      }
    });

    _errorSubscription = _player.stream.error.listen((value) {
      if (!mounted || _isDisposed) return;
      _handlePlayerError(value);
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    });

    _tracksSubscription = _player.stream.tracks.listen((value) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _tracks = value;
        if (_selectedAudioTrackIndex >= value.audio.length) {
          _selectedAudioTrackIndex = 0;
        }
      });
      // Some network streams publish subtitle tracks after playback starts.
      if (value.subtitle.any((track) => track.id != 'auto' && track.id != 'no')) {
        unawaited(_activateEmbeddedSubtitleIfAvailable());
      }
      // Re-apply the user's audio sync preference when a new media exposes
      // its tracks. This only changes the active Player's audio-delay property.
      if (_audioDelay.abs() >= 0.01) {
        unawaited(_applyAudioDelay(
          _audioDelay,
          persist: false,
          showFeedback: false,
        ));
      }
    });

    // Recover gracefully if an active audio track is unexpectedly disabled
    // by a stream/decoder reconfiguration while playable audio tracks remain.
    _activeTrackSubscription = _player.stream.track.listen((track) {
      if (!mounted || _isDisposed) return;
      if (track.audio.id == 'no' && _tracks.audio.isNotEmpty) {
        unawaited(_restoreAudioTrackAfterDropout());
      }
    });

    // If the selected Bluetooth/output route disappears during playback,
    // fall back to Android's automatic audio device instead of remaining silent.
    _audioDevicesSubscription =
        _player.stream.audioDevices.listen((devices) {
      if (!mounted || _isDisposed) return;
      final selectedDevice = _player.state.audioDevice;
      if (selectedDevice.name != 'auto' &&
          !devices.any((device) => device.name == selectedDevice.name)) {
        unawaited(_restoreAudioDeviceAfterDisconnect());
      }
    });

    _completedSubscription = _player.stream.completed.listen((completed) {
      if (!completed || !mounted || _isDisposed) return;

      setState(() {
        _isPlaying = false;
        _showControls = true;
      });

      _clearResumePosition();
    });
  }

  Future<void> _restoreAudioTrackAfterDropout() async {
    if (_isDisposed || _tracks.audio.isEmpty) return;
    try {
      await _player.setAudioTrack(AudioTrack.auto());
      if (!_isDisposed && _audioDelay.abs() >= 0.01) {
        await _applyAudioDelay(
          _audioDelay,
          persist: false,
          showFeedback: false,
        );
      }
    } catch (error) {
      debugPrint('FLIXORA audio-track recovery failed: $error');
    }
  }

  Future<void> _restoreAudioDeviceAfterDisconnect() async {
    if (_isDisposed) return;
    try {
      await _player.setAudioDevice(AudioDevice.auto());
    } catch (error) {
      debugPrint('FLIXORA audio-device recovery failed: $error');
    }
  }

  Future<void> _initializePlayer() async {
    if (_isOpening || _isDisposed) return;
    _playbackErrorTimer?.cancel();

    if (!_validVideoUrl) {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _initialized = false;
        });
      }
      return;
    }

    _isOpening = true;
    _automaticSubtitleRequestToken++;
    _automaticSubtitleLoading = false;
    _automaticEnglishTrack = null;
    _automaticSubtitleMessage = null;
    _subtitleManuallySelected = false;
    _tracks = Tracks(
      video: [VideoTrack.auto()],
      audio: [AudioTrack.auto()],
      subtitle: [SubtitleTrack.auto()],
    );
    _seekSyncTimer?.cancel();
    _bufferingRecoveryTimer?.cancel();
    _bufferingRecoveryAttempts = 0;
    _recoveringFromBuffering = false;
    _seekRequestToken++;
    _isSeeking = false;
    _seekPreviewPosition = null;
    _pendingSeekPosition = null;
    // A new media item must not inherit the previous item's duration or time.
    _duration = Duration.zero;
    _updatePosition(Duration.zero);
    try {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _initialized = false;
        });
      }

      final candidates = <Map<String, String>>[];
      if (widget.localFilePath != null) {
        if (!await File(widget.localFilePath!).exists()) {
          throw Exception('Downloaded file is missing.');
        }
        candidates.add({
          'quality': 'Offline',
          'video_url': widget.localFilePath!,
          'headers': '{}',
        });
      } else {
        final preferredUrl = _resolveInitialNetworkUrl();
        if (preferredUrl.trim().isNotEmpty) {
          candidates.add({
            'quality': _selectedQuality ?? 'Original',
            'video_url': preferredUrl,
            'headers': '{}',
          });
        }
        for (final quality in _availableQualities) {
          final url = quality['video_url']?.trim() ?? '';
          if (url.isNotEmpty &&
              !candidates.any((candidate) => candidate['video_url'] == url)) {
            candidates.add(quality);
          }
        }
      }

      Object? lastError;
      for (final candidate in candidates.take(4)) {
        final playbackSource = candidate['video_url']?.trim() ?? '';
        final uri = Uri.tryParse(playbackSource);
        final isLocal = widget.localFilePath != null;
        if (playbackSource.isEmpty ||
            (!isLocal &&
                (uri == null ||
                    (uri.scheme != 'http' && uri.scheme != 'https') ||
                    uri.host.isEmpty))) {
          lastError = Exception('No playable video URL is available.');
          continue;
        }

        try {
          await _player.open(
            Media(
              playbackSource,
              httpHeaders: isLocal
                  ? const <String, String>{}
                  : _headersForQuality(candidate),
            ),
            play: true,
          );
          if (!mounted || _isDisposed) return;

          if (!isLocal) _currentVideoUrl = playbackSource;
          setState(() {
            _selectedQuality = candidate['quality'];
            _initialized = true;
            _errorMessage = null;
          });
          if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;

          // Playback starts as soon as the native media open completes.
          if (!mounted || _isDisposed) return;
          await _restoreResumePosition();
          if (!mounted || _isDisposed) return;
          _subtitleManuallySelected = false;
          _automaticEnglishTrack = null;
          _automaticSubtitleMessage = null;
          unawaited(_ensureAutomaticEnglishSubtitle());
          _startHideTimer();
          return;
        } catch (error) {
          lastError = error;
          try {
            await _player.stop();
          } catch (_) {}
        }
      }

      throw lastError ?? Exception('No working video source was available.');
    } catch (e) {
      if (!mounted || _isDisposed) return;
      setState(() {
        _errorMessage =
            'Unable to play this video. Please check the video link and try again.';
      });
      if (_isMiniPlayer) _miniPlayerOverlayRevision.value++;
    } finally {
      _isOpening = false;
    }
  }

  Future<void> _restoreResumePosition() async {
    if (_isDisposed) return;
    _restoringResumePosition = true;
    try {
      final lastEpisode = await _readLastEpisodeSelection();
      if (lastEpisode != null && mounted && !_isDisposed) {
        _selectedSeasonNumber = lastEpisode[0];
        _selectedEpisodeNumber = lastEpisode[1];
      }
      final prefs = await SharedPreferences.getInstance();
      final resumeKeys = _resumeKeys;
      var savedMilliseconds = 0;
      String? savedKey;
      for (final key in resumeKeys) {
        final legacySeconds = prefs.getInt(key) ?? 0;
        final candidate = prefs.getInt('${key}_ms') ??
            (legacySeconds * 1000);
        if (candidate > savedMilliseconds) {
          savedMilliseconds = candidate;
          savedKey = key;
        }
      }
      if (savedMilliseconds <= 5000) return;
      final savedPosition = Duration(milliseconds: savedMilliseconds);

      // Network streams may expose duration only after MPV has started.
      var mediaDuration = _player.state.duration > Duration.zero
          ? _player.state.duration
          : _duration;
      for (var attempt = 0;
          mediaDuration <= Duration.zero && attempt < 25;
          attempt++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted || _isDisposed) return;
        mediaDuration = _player.state.duration > Duration.zero
            ? _player.state.duration
            : _duration;
      }

      if (mediaDuration > Duration.zero &&
          savedPosition >= mediaDuration - const Duration(seconds: 15)) {
        for (final key in resumeKeys) {
          await prefs.remove(key);
          await prefs.remove('${key}_ms');
          await prefs.remove('${key}_duration');
          await prefs.remove('${key}_duration_ms');
        }
        return;
      }

      // Use frame-accurate seeking for resume restoration. Normal interactive
      // seeks remain keyframe-optimized to reduce network wait.
      final nativePlayer = _player.platform;
      if (nativePlayer is NativePlayer) {
        try {
          await nativePlayer.setProperty('hr-seek', 'yes');
        } catch (_) {}
      }
      try {
        for (var pass = 0; pass < 2; pass++) {
          await _player.seek(savedPosition);
          for (var attempt = 0; attempt < 12; attempt++) {
            await Future.delayed(const Duration(milliseconds: 250));
            if (!mounted || _isDisposed) return;
            final actual = _player.state.position;
            if ((actual - savedPosition).inMilliseconds.abs() <= 1500) break;
          }
          final actual = _player.state.position;
          if ((actual - savedPosition).inMilliseconds.abs() <= 1500) break;
        }
      } finally {
        if (nativePlayer is NativePlayer) {
          try {
            await nativePlayer.setProperty('hr-seek', 'no');
          } catch (_) {}
        }
      }

      if (savedKey != null && savedKey != _resumeKey) {
        await prefs.setInt(_resumeKey, (savedMilliseconds / 1000).floor());
        await prefs.setInt('${_resumeKey}_ms', savedMilliseconds);
        final savedDurationMs = prefs.getInt('${savedKey}_duration_ms') ??
            ((prefs.getInt('${savedKey}_duration') ?? 0) * 1000);
        if (savedDurationMs > 0) {
          await prefs.setInt('${_resumeKey}_duration_ms', savedDurationMs);
          await prefs.setInt('${_resumeKey}_duration', (savedDurationMs / 1000).floor());
        }
      }
      if (mounted && !_isDisposed) {
        final actual = _player.state.position;
        final restoredPosition =
            actual > Duration.zero &&
                    (actual - savedPosition).inMilliseconds.abs() <= 1500
                ? actual
                : savedPosition;
        setState(() => _updatePosition(restoredPosition));
      }
    } catch (error) {
      debugPrint('FLIXORA resume restoration failed: $error');
    } finally {
      _restoringResumePosition = false;
    }
  }

  Future<void> _saveResumePosition(Duration position) {
    if (_isDisposed || position.inMilliseconds < 5000) {
      return Future<void>.value();
    }

    // Capture the key immediately. If the user changes episode while a
    // preference write is pending, the old timestamp must stay with its
    // original movie/season/episode.
    final keys = _resumeKeys;
    final recentKeys = <String>{
      if (widget.movie.tmdbId > 0)
        'flixora_recent_resume_${widget.movie.mediaType}_${widget.movie.tmdbId}',
      if (widget.movie.id != 0)
        'flixora_recent_resume_${widget.movie.mediaType}_${widget.movie.id.abs()}',
    };
    final milliseconds = position.inMilliseconds;
    final seconds = position.inSeconds;
    final durationMilliseconds = _duration.inMilliseconds;
    final durationSeconds = _duration.inSeconds;
    _resumeSaveQueue = _resumeSaveQueue.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      for (final key in keys) {
        await prefs.setInt(key, seconds);
        await prefs.setInt('${key}_ms', milliseconds);
        await prefs.setInt('${key}_duration', durationSeconds);
        await prefs.setInt('${key}_duration_ms', durationMilliseconds);
      }
      for (final recentKey in recentKeys) {
        await prefs.setInt(recentKey, seconds);
        await prefs.setInt('${recentKey}_ms', milliseconds);
        await prefs.setInt('${recentKey}_duration', durationSeconds);
        await prefs.setInt('${recentKey}_duration_ms', durationMilliseconds);
      }
    }).catchError((error) {
      debugPrint('Could not persist FLIXORA resume position: $error');
    });
    return _resumeSaveQueue;
  }

  Future<void> _clearResumePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _resumeKeys) {
        await prefs.remove(key);
        await prefs.remove('${key}_ms');
        await prefs.remove('${key}_duration');
        await prefs.remove('${key}_duration_ms');
      }
    } catch (_) {}
  }

  void _startHideTimer() {
    _cancelHideTimer();

    if (!_isPlaying || _isLocked) return;

    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || _isDisposed) return;
      setState(() => _showControls = false);
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _toggleControls() {
    if (_isLocked) return;

    setState(() => _showControls = !_showControls);

    if (_showControls) {
      _startHideTimer();
    } else {
      _cancelHideTimer();
    }
  }

  Future<void> _togglePlay() async {
    if (_isDisposed) return;

    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }

    _startHideTimer();
  }

  Future<void> _loadGesturePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || _isDisposed) return;
      setState(() {
        _volumeGestureEnabled = prefs.getBool('flixora_gesture_volume') ?? true;
        _brightnessGestureEnabled = prefs.getBool('flixora_gesture_brightness') ?? true;
        _doubleTapSkipEnabled = prefs.getBool('flixora_gesture_double_tap') ?? true;
        _doubleTapSkipSeconds = prefs.getInt('flixora_gesture_skip_seconds') ?? 10;
        _gestureSensitivity = (prefs.getDouble('flixora_gesture_sensitivity') ?? 1.0)
            .clamp(0.5, 2.0)
            .toDouble();
      });
    } catch (error) {
      debugPrint('Could not load player gesture preferences: $error');
    }
  }

  Future<void> _saveGesturePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('flixora_gesture_volume', _volumeGestureEnabled);
      await prefs.setBool('flixora_gesture_brightness', _brightnessGestureEnabled);
      await prefs.setBool('flixora_gesture_double_tap', _doubleTapSkipEnabled);
      await prefs.setInt('flixora_gesture_skip_seconds', _doubleTapSkipSeconds);
      await prefs.setDouble('flixora_gesture_sensitivity', _gestureSensitivity);
    } catch (error) {
      debugPrint('Could not save player gesture preferences: $error');
    }
  }

  void _handlePlayerGestureStart(ScaleStartDetails details) {
    _gestureFeedbackTimer?.cancel();
    final topSystemGestureArea =
        MediaQuery.of(context).viewPadding.top + 24.0;
    if (details.localFocalPoint.dy <= topSystemGestureArea) {
      _gestureStartPoint = null;
      _gestureMode = 'system';
      _gesturePreviewPosition = null;
      return;
    }
    _gestureStartPoint = details.localFocalPoint;
    _gestureStartPosition = _position;
    _gestureStartBrightness = _screenBrightness;
    _gestureStartVolume = _volume;
    _gestureStartZoom = _videoZoom;
    _gestureMode = null;
    _gesturePreviewPosition = null;
  }

  void _handlePlayerGestureUpdate(ScaleUpdateDetails details) {
    if (!_initialized || _isLocked || _errorMessage != null) return;

    // Two-finger pinch controls video zoom without changing the stream.
    if (details.pointerCount >= 2) {
      if (_gestureMode != 'zoom') {
        _cancelHideTimer();
        setState(() {          _gestureMode = 'zoom';
        });
      }

      final nextZoom =
          (_gestureStartZoom * details.scale).clamp(1.0, 3.0).toDouble();
      if ((nextZoom - _videoZoom).abs() > 0.005) {
        setState(() {
          _videoZoom = nextZoom;
          _gestureFeedback = '${(nextZoom * 100).round()}%';
        });
      }
      return;
    }

    // Once a pinch has started, lifting one finger must not turn it into a
    // brightness, volume, or seek gesture.
    if (_gestureMode == 'zoom') return;

    final start = _gestureStartPoint;
    if (start == null) return;

    final delta = details.localFocalPoint - start;
    if (_gestureMode == null) {
      if (delta.distance < 10) return;

      final isHorizontal = delta.dx.abs() >= delta.dy.abs();
      final isLeftSide =
          start.dx < MediaQuery.of(context).size.width / 2;
      final mode = isHorizontal
          ? 'seek'
          : isLeftSide
              ? (_brightnessGestureEnabled ? 'brightness' : 'disabled')
              : (_volumeGestureEnabled ? 'volume' : 'disabled');

      _cancelHideTimer();
      setState(() {
        _gestureMode = mode;
      });
    }

    if (_gestureMode == 'seek') {
      if (_duration.inMilliseconds <= 0) return;

      // A full player-width drag represents up to two minutes of seeking.
      final width = MediaQuery.of(context).size.width;
      final secondsDelta = (delta.dx / width * 120).round();
      final targetMilliseconds = (_gestureStartPosition.inMilliseconds +
              (delta.dx / width * 120000).round())
          .clamp(0, _duration.inMilliseconds)
          .toInt();

      setState(() {
        _gesturePreviewPosition =
            Duration(milliseconds: targetMilliseconds);
        _gestureFeedback =
            '${secondsDelta >= 0 ? '+' : ''}${secondsDelta}s';
      });
    } else if (_gestureMode == 'brightness') {
      final height = MediaQuery.of(context).size.height;
      final brightness = (_gestureStartBrightness -
              delta.dy / height * _gestureSensitivity)
          .clamp(0.0, 1.0)
          .toDouble();
      _changeApplicationBrightness(brightness);
      if (mounted && !_isDisposed) {
        setState(() {
          _gestureFeedback = '${(brightness * 100).round()}%';
        });
      }
    } else if (_gestureMode == 'volume') {
      final height = MediaQuery.of(context).size.height;
      final volume = (_gestureStartVolume -
              delta.dy / height * 200 * _gestureSensitivity)
          .clamp(0.0, 200.0)
          .toDouble();
      _changeVolume(volume);
      if (mounted && !_isDisposed) {
        setState(() {
          _gestureFeedback = '${volume.round()}%';
        });
      }
    }
  }

  Future<void> _handlePlayerGestureEnd(ScaleEndDetails details) async {
    final mode = _gestureMode;
    final previewPosition = _gesturePreviewPosition;

    if (mode == 'seek' && previewPosition != null) {
      await _performSeek(previewPosition);
    }

    _gestureStartPoint = null;
    _gestureFeedbackTimer?.cancel();

    if (!mounted || _isDisposed) return;
    _gestureFeedbackTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted || _isDisposed) return;
      setState(() {
        _gestureMode = null;
        _gestureFeedback = '';
        _gesturePreviewPosition = null;
      });
    });
    _startHideTimer();
  }

  Future<void> _performSeek(Duration requested) async {
    if (_duration.inMilliseconds <= 0 || _isDisposed) return;

    final target = Duration(
      milliseconds: requested.inMilliseconds
          .clamp(0, _duration.inMilliseconds)
          .toInt(),
    );
    final requestToken = ++_seekRequestToken;

    _seekSyncTimer?.cancel();
    _isSeeking = false;
    _seekPreviewPosition = null;
    _pendingSeekPosition = target;
    _positionNotifier.value = target;

    // If the stream cannot seek (for example, a server without byte ranges),
    // release the preview after a bounded wait and show mpv's actual position.
    _seekSyncTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted || _isDisposed || requestToken != _seekRequestToken) return;
      _pendingSeekPosition = null;
      final actual = _player.state.position;
      final safeActual = _duration > Duration.zero && actual > _duration
          ? _duration
          : actual;
      _updatePosition(safeActual);
    });

    try {
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted || _isDisposed || requestToken != _seekRequestToken) return;
      await _player.seek(target);
    } catch (error) {
      if (!mounted || _isDisposed || requestToken != _seekRequestToken) return;
      _seekSyncTimer?.cancel();
      _pendingSeekPosition = null;
      final actual = _player.state.position;
      _updatePosition(
        _duration > Duration.zero && actual > _duration ? _duration : actual,
      );
      debugPrint('FLIXORA seek failed: $error');
    }
  }

  Future<void> _seekBy(int seconds) async {
    if (_duration.inMilliseconds <= 0) return;
    final base = _pendingSeekPosition ?? _position;
    final next = base + Duration(seconds: seconds);
    await _performSeek(next);
    _startHideTimer();
  }

  Future<void> _seekTo(double value) async {
    await _performSeek(Duration(milliseconds: value.round()));
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _changeSpeed(double speed) async {
    await _player.setRate(speed);

    if (!mounted || _isDisposed) return;

    setState(() => _speed = speed);
    _startHideTimer();
  }

  Future<void> _configureVolumeBoost() async {
    final platformPlayer = _player.platform;
    if (platformPlayer is! NativePlayer) return;

    try {
      // mpv's software volume ceiling: 200% permits up to 2x amplification.
      await platformPlayer.setProperty('volume-max', '200');

      if (widget.localFilePath == null) {
        // Explicitly enable the network demuxer cache for MovieBox/WeFeed and
        // direct network streams. Keep immediate initial playback, but let
        // playback rebuffer briefly before resuming after an underrun.
        await platformPlayer.setProperty('cache', 'yes');
        await platformPlayer.setProperty('cache-pause', 'yes');
        await platformPlayer.setProperty('demuxer-readahead-secs', '45');
        await platformPlayer.setProperty('cache-secs', '45');
        await platformPlayer.setProperty('demuxer-max-bytes', '128MiB');
        await platformPlayer.setProperty('demuxer-max-back-bytes', '32MiB');
        await platformPlayer.setProperty('cache-pause-wait', '1.0');
        // Prefer keyframe seeks for faster response on network streams.
        // This can land a fraction earlier/later than frame-accurate seeking.
        await platformPlayer.setProperty('hr-seek', 'no');
        // Drop only late video-output frames so video can stay synchronized
        // with audio when decoding/rendering briefly falls behind.
        await platformPlayer.setProperty('framedrop', 'vo');
        // Keep libmpv subtitle output enabled for embedded and external tracks.
        await platformPlayer.setProperty('sub-visibility', 'yes');
      }
    } catch (error) {
      debugPrint('FLIXORA native playback configuration failed: $error');
    }
  }

  Future<void> _changeVolume(double value) async {
    final volume = value.clamp(0.0, 200.0).toDouble();

    await _player.setVolume(volume);

    if (!mounted || _isDisposed) return;

    setState(() => _volume = volume);
  }

  Future<void> _toggleMiniPlayer() async {
    if (_isDisposed) return;
    if (_isMiniPlayer) {
      _expandMiniPlayer();
      return;
    }

    if (_isFullscreen) {
      await _toggleFullscreen();
      if (!mounted || _isDisposed) return;
    }

    setState(() {
      _isMiniPlayer = true;
      _showControls = false;
      _miniPlayerOffset = null;
    });
    _activeMiniPlayerState.value = this;
    _miniPlayerOverlayRevision.value++;
    unawaited(PictureInPictureService.setEnabled(
      _isPlaying && widget.enablePip && _isMiniPlayer,
    ));
    _cancelHideTimer();
  }

  void _expandMiniPlayer() {
    final route = _activePlayerRoute;
    final navigator = _activePlayerNavigator;
    if (route != null &&
        navigator != null &&
        navigator.mounted &&
        route.isActive) {
      try {
        navigator.popUntil((candidate) => identical(candidate, route));
      } catch (error) {
        debugPrint('Could not restore the full FLIXORA Player: $error');
      }
    }
    if (!mounted || _isDisposed) return;
    _activeMiniPlayerState.value = null;
    setState(() {
      _isMiniPlayer = false;
      _showControls = true;
      _miniPlayerOffset = null;
    });
    unawaited(PictureInPictureService.setEnabled(false));
    _miniPlayerOverlayRevision.value++;
    _startHideTimer();
  }

  void _closeMiniPlayer() {
    final route = _activePlayerRoute;
    final navigator = _activePlayerNavigator;
    _activeMiniPlayerState.value = null;
    if (route != null &&
        navigator != null &&
        navigator.mounted &&
        route.isActive) {
      try {
        navigator.removeRoute(route);
        return;
      } catch (error) {
        debugPrint('Could not close the FLIXORA mini-player route: $error');
      }
    }
    if (mounted && !_isDisposed) {
      Navigator.of(context).maybePop();
    }
  }

  void _moveMiniPlayer(
    DragUpdateDetails details, {
    required double maxRight,
    required double maxBottom,
  }) {
    if (!mounted || !_isMiniPlayer) return;
    final current = _miniPlayerOffset ?? const Offset(14, 92);
    final rightLimit = maxRight < 8 ? 8.0 : maxRight;
    final bottomLimit = maxBottom < 8 ? 8.0 : maxBottom;
    setState(() {
      _miniPlayerOffset = Offset(
        (current.dx - details.delta.dx).clamp(8.0, rightLimit).toDouble(),
        (current.dy - details.delta.dy).clamp(8.0, bottomLimit).toDouble(),
      );
    });
    _miniPlayerOverlayRevision.value++;
  }

  Widget _buildMiniPlayerOverlay(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _miniPlayerOverlayRevision,
      builder: (context, revision, _) {
        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final viewPadding = media.viewPadding;
        final viewInsets = media.viewInsets;
        final requestedWidth = (screenSize.width * 0.58)
            .clamp(180.0, 280.0)
            .toDouble();
        final availableWidth = screenSize.width -
            viewPadding.left - viewPadding.right - 16;
        final miniWidth = requestedWidth > availableWidth
            ? (availableWidth < 150 ? 150.0 : availableWidth)
            : requestedWidth;
        final miniHeight = miniWidth * 9 / 16 + 32;
        final maxRight = screenSize.width -
            viewPadding.horizontal - miniWidth - 8;
        final maxBottom = screenSize.height -
            viewPadding.vertical - viewInsets.bottom - miniHeight - 8;
        final rightLimit = maxRight < 8 ? 8.0 : maxRight;
        final bottomLimit = maxBottom < 8 ? 8.0 : maxBottom;
        final miniRight = (_miniPlayerOffset?.dx ?? 14.0)
            .clamp(8.0, rightLimit)
            .toDouble();
        final miniBottom = (_miniPlayerOffset?.dy ?? 92.0)
            .clamp(8.0, bottomLimit)
            .toDouble();
        final miniTitle = widget.movie.movieBoxIsSeries
            ? '${widget.movie.title} · S$_selectedSeasonNumber E$_selectedEpisodeNumber'
            : widget.movie.title;

        return Positioned(
          right: viewPadding.right + miniRight,
          bottom: viewPadding.bottom + viewInsets.bottom + miniBottom,
          child: Material(
            color: Colors.black,
            elevation: 20,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: const BorderSide(color: Color(0x55D9B45B)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: miniWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 32,
                    color: const Color(0xFF171717),
                    padding: const EdgeInsets.only(left: 6, right: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _expandMiniPlayer,
                            onPanUpdate: (details) => _moveMiniPlayer(
                              details,
                              maxRight: rightLimit,
                              maxBottom: bottomLimit,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.drag_indicator_rounded,
                                  color: playerGold,
                                  size: 18,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    miniTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        StreamBuilder<bool>(
                          stream: _player.stream.playing,
                          initialData: _isPlaying,
                          builder: (context, snapshot) {
                            final playing = snapshot.data ?? _isPlaying;
                            return IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 28,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: playing ? 'Pause' : 'Play',
                              onPressed: _togglePlay,
                              icon: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            );
                          },
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 30,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Expand player',
                          onPressed: _expandMiniPlayer,
                          icon: const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 30,
                          ),
                          padding: EdgeInsets.zero,
                          tooltip: 'Close mini player',
                          onPressed: _closeMiniPlayer,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _playerBody(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleFullscreen() async {
    if (!mounted) return;

    if (!_isFullscreen) {
      if (_isMiniPlayer) setState(() => _isMiniPlayer = false);
      // Entering landscape always starts in Normal fit so characters are not cropped.
      _videoFitMode = 2;
      _videoZoom = 1.0;
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    }

    if (!mounted) return;

    setState(() => _isFullscreen = !_isFullscreen);
  }

  Future<void> _selectAudioTrack(
    AudioTrack track, {bool closeSheet = true}
  ) async {
    try {
      await _player.setAudioTrack(track);
      if (!mounted || _isDisposed) return;
      final index = _tracks.audio.indexOf(track);
      setState(() => _selectedAudioTrackIndex = index < 0 ? 0 : index);
      if (closeSheet) Navigator.pop(context);
      _startHideTimer();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change audio language: $error')),
        );
      }
    }
  }

  Future<void> _selectMovieBoxSubtitle(Map<String, dynamic> subtitle) async {
    final options = _movieBoxSubtitleOptions([subtitle]);
    if (options.isEmpty) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This subtitle link is unavailable.')),
        );
      }
      return;
    }
    final option = options.first;
    final url = (option['downloadUrl'] ?? '').toString();
    final language = (option['language'] ?? 'und').toString();
    final release = (option['releaseName'] ?? 'Subtitle').toString();
    await _selectSubtitleTrack(SubtitleTrack.uri(
      url,
      title: '${_subtitleLanguageName(language)} · $release',
      language: language,
    ));
  }

  Future<void> _activateSubtitleTrack(SubtitleTrack track) async {
    if (_isDisposed) throw StateError('The video player is no longer active.');
    await _player.setSubtitleTrack(track);
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('sub-visibility', 'yes');
      await native.setProperty('sub-ass-override', 'force');
    }
    await _applySubtitleDelay(_subtitleDelay, showFeedback: false);
    // Allow the native player to publish the selected external/embedded track.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (_isDisposed) throw StateError('The video player was closed while loading subtitles.');
    final activeId = _player.state.track.subtitle.id;
    if (track.id != 'auto' && track.id != 'no' && activeId != track.id) {
      debugPrint('FLIXORA subtitle activation mismatch: requested=${track.id}, active=$activeId');
      throw StateError('Subtitle file was added but the player did not activate its track.');
    }
  }

  Future<void> _selectSubtitleTrack(SubtitleTrack track) async {
    try {
      await _activateSubtitleTrack(track);
      _subtitleManuallySelected = true;
      if (!mounted || _isDisposed) return;
      setState(() {
        _selectedSubtitleLanguageCode = (track.language ?? '').toLowerCase();
        _subtitleVisibilityEnabled = track.id != 'no';
        _automaticEnglishTrack = track;
        _automaticSubtitleMessage = 'Subtitle track active';
      });
      Navigator.of(context).maybePop();
      _startHideTimer();
    } catch (_) {
      // Keep subtitle activation feedback silent; do not show internal player errors to visitors.
    }
  }

  Future<void> _loadSubtitlePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedSubtitleFontSize = prefs.getDouble('flixora_sub_font_size') ?? 20;
      _subtitleFontSize = storedSubtitleFontSize.clamp(12, 60).toDouble();
      _subtitleTextColor = prefs.getString('flixora_sub_text_color') ?? '#FFFFFF';
      _subtitleBackgroundColor = prefs.getString('flixora_sub_background_color') ?? '#000000';
      _subtitleBackgroundOpacity = prefs.getDouble('flixora_sub_background_opacity') ?? 0.24;
      _subtitlePosition = prefs.getDouble('flixora_sub_position') ?? 92;
      _subtitleDelay = prefs.getDouble('flixora_sub_delay') ?? 0;
      _subtitleOutlineSize = prefs.getDouble('flixora_sub_outline_size') ?? 1.5;
      _subtitleShadowOffset = prefs.getDouble('flixora_sub_shadow_offset') ?? 1;
      if (mounted && !_isDisposed) setState(() {});
      // Apply the saved subtitle timing offset to libmpv, not just the UI.
      unawaited(_applySubtitleDelay(_subtitleDelay, showFeedback: false));
    } catch (error) {
      debugPrint('Subtitle preferences load failed: $error');
    }
  }

  Future<bool> _applySubtitleDelay(
    double value, {
    bool showFeedback = true,
  }) async {
    final nextDelay = value.clamp(-10.0, 10.0).toDouble();
    final platformPlayer = _player.platform;
    if (platformPlayer is! NativePlayer) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subtitle sync is not supported by this playback platform.'),
          ),
        );
      }
      return false;
    }

    try {
      // libmpv measures sub-delay in seconds; positive delays subtitles and
      // negative values bring them forward relative to the dialogue.
      await platformPlayer.setProperty(
        'sub-delay',
        nextDelay.toStringAsFixed(2),
      );
      await platformPlayer.setProperty('sub-visibility', 'yes');
      if (!mounted || _isDisposed) return false;
      setState(() => _subtitleDelay = nextDelay);
      return true;
    } catch (error) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not adjust subtitle sync: $error')),
        );
      }
      return false;
    }
  }

  SubtitleViewConfiguration _subtitleViewConfiguration() {
    final backgroundHex = _subtitleBackgroundColor.replaceFirst('#', '');
    final backgroundRgb = int.parse(backgroundHex, radix: 16);
    final backgroundAlpha = (_subtitleBackgroundOpacity * 255)
        .round().clamp(0, 255).toInt();
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height;
    final requestedBottomPadding = (screenHeight * (1 - _subtitlePosition / 100) - 10.0)
        .clamp(8.0, screenHeight * 0.85).toDouble();
    // When landscape controls are visible, reserve space above the seek bar.
    // This only moves the subtitle overlay; it does not alter any controls.
    final landscapeControlsClearance =
        (screenHeight * 0.22 - 10.0).clamp(54.0, 102.0).toDouble();
    final bottomPadding = screenSize.width > screenSize.height &&
            _showControls &&
            requestedBottomPadding < landscapeControlsClearance
        ? landscapeControlsClearance
        : requestedBottomPadding;

    return SubtitleViewConfiguration(
      visible: true,
      style: TextStyle(
        fontFamily: 'Arial',
        fontSize: _subtitleFontSize.clamp(12, 60).toDouble(),
        color: _subtitleColorFromHex(_subtitleTextColor),
        backgroundColor: Color((backgroundAlpha << 24) | backgroundRgb),
        fontWeight: FontWeight.w600,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
      textAlign: TextAlign.center,
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomPadding),
    );
  }

  Future<void> _saveSubtitlePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('flixora_sub_font_size', _subtitleFontSize);
    await prefs.setString('flixora_sub_text_color', _subtitleTextColor);
    await prefs.setString('flixora_sub_background_color', _subtitleBackgroundColor);
    await prefs.setDouble('flixora_sub_background_opacity', _subtitleBackgroundOpacity);
    await prefs.setDouble('flixora_sub_position', _subtitlePosition);
    await prefs.setDouble('flixora_sub_delay', _subtitleDelay);
    await prefs.setDouble('flixora_sub_outline_size', _subtitleOutlineSize);
    await prefs.setDouble('flixora_sub_shadow_offset', _subtitleShadowOffset);
  }

  Color _subtitleColorFromHex(String value) {
    final hex = value.replaceFirst('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  void _showSubtitleStyleSettings() {
    _cancelHideTimer();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      backgroundColor: playerPanel.withValues(alpha: 0.48),
      builder: (sheetContext) {
        var fontSize = _subtitleFontSize;
        var textColor = _subtitleTextColor;
        var backgroundColor = _subtitleBackgroundColor;
        var opacity = _subtitleBackgroundOpacity;
        var position = _subtitlePosition;
        var delay = _subtitleDelay;
        var outline = _subtitleOutlineSize;
        var shadow = _subtitleShadowOffset;
        const colors = <String, String>{
          'White': '#FFFFFF', 'Yellow': '#FFFF00', 'Green': '#00FF80',
          'Cyan': '#00D5FF', 'Orange': '#FFB347', 'Red': '#FF7070',
        };
        const backgrounds = <String, String>{
          'Black': '#000000', 'Dark Grey': '#333333', 'Navy': '#101827',
        };

        return StatefulBuilder(
          builder: (context, updateSheet) {
            Widget sectionLabel(String label) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 4),
              child: Text(label, style: const TextStyle(
                color: playerGoldLight, fontSize: 13, fontWeight: FontWeight.w800,
              )),
            );
            Widget sliderRow({
              required String label, required double value,
              required double min, required double max, required int divisions,
              required String display, required ValueChanged<double> onChanged,
            }) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(color: playerWhite, fontSize: 12))),
                  Text(display, style: const TextStyle(color: playerGoldLight, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
                Slider(value: value.clamp(min, max).toDouble(), min: min, max: max,
                  divisions: divisions, activeColor: playerGold,
                  inactiveColor: const Color(0x33FFFFFF), onChanged: onChanged),
              ],
            );

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Subtitle Appearance', style: TextStyle(
                        color: playerWhite, fontSize: 18, fontWeight: FontWeight.w800,
                      )),
                      const SizedBox(height: 4),
                      const Text('Font: Arial', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12)),
                      sectionLabel('TEXT SIZE'),
                      sliderRow(label: 'Font size', value: fontSize, min: 12, max: 60,
                        divisions: 48, display: '${fontSize.round()}',
                        onChanged: (v) => updateSheet(() => fontSize = v)),
                      sectionLabel('TEXT COLOUR'),
                      DropdownButtonFormField<String>(
                        initialValue: colors.containsValue(textColor) ? textColor : '#FFFFFF',
                        dropdownColor: playerPanel,
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        items: colors.entries.map((entry) => DropdownMenuItem(
                          value: entry.value,
                          child: Row(children: [
                            Container(width: 16, height: 16, decoration: BoxDecoration(
                              color: _subtitleColorFromHex(entry.value), shape: BoxShape.circle,
                            )),
                            const SizedBox(width: 10),
                            Text(entry.key, style: const TextStyle(color: playerWhite)),
                          ]),
                        )).toList(),
                        onChanged: (v) { if (v != null) updateSheet(() => textColor = v); },
                      ),
                      sectionLabel('BACKGROUND'),
                      DropdownButtonFormField<String>(
                        initialValue: backgrounds.containsValue(backgroundColor) ? backgroundColor : '#000000',
                        dropdownColor: playerPanel,
                        decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                        items: backgrounds.entries.map((entry) => DropdownMenuItem(
                          value: entry.value,
                          child: Text(entry.key, style: const TextStyle(color: playerWhite)),
                        )).toList(),
                        onChanged: (v) { if (v != null) updateSheet(() => backgroundColor = v); },
                      ),
                      sliderRow(label: 'Background opacity', value: opacity, min: 0, max: 1,
                        divisions: 20, display: '${(opacity * 100).round()}%',
                        onChanged: (v) => updateSheet(() => opacity = v)),
                      sectionLabel('POSITION'),
                      sliderRow(label: 'Vertical position', value: position, min: 5, max: 95,
                        divisions: 18, display: '${position.round()}%',
                        onChanged: (v) => updateSheet(() => position = v)),
                      sectionLabel('SYNC'),
                      sliderRow(label: 'Subtitle delay', value: delay, min: -10, max: 10,
                        divisions: 200, display: '${delay >= 0 ? '+' : ''}${delay.toStringAsFixed(1)}s',
                        onChanged: (v) => updateSheet(() => delay = v)),
                      sectionLabel('READABILITY'),
                      sliderRow(label: 'Outline', value: outline, min: 0, max: 5,
                        divisions: 10, display: outline.toStringAsFixed(1),
                        onChanged: (v) => updateSheet(() => outline = v)),
                      sliderRow(label: 'Shadow', value: shadow, min: 0, max: 5,
                        divisions: 10, display: shadow.toStringAsFixed(1),
                        onChanged: (v) => updateSheet(() => shadow = v)),
                      const SizedBox(height: 12),
                      SizedBox(width: double.infinity, child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: playerGold, foregroundColor: Colors.black),
                        onPressed: () async {
                          setState(() {
                            _subtitleFontSize = fontSize;
                            _subtitleTextColor = textColor;
                            _subtitleBackgroundColor = backgroundColor;
                            _subtitleBackgroundOpacity = opacity;
                            _subtitlePosition = position;
                            _subtitleDelay = delay;
                            _subtitleOutlineSize = outline;
                            _subtitleShadowOffset = shadow;
                          });
                          await _applySubtitleDelay(delay, showFeedback: false);
                          await _saveSubtitlePreferences();
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          _startHideTimer();
                        },
                        child: const Text('Save Subtitle Settings', style: TextStyle(fontWeight: FontWeight.w800)),
                      )),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_startHideTimer);
  }

  Future<void> _addExternalSubtitle() async {
    final controller = TextEditingController();

    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: playerPanel,
          title: const Text(
            'External Subtitle',
            style: TextStyle(color: playerWhite),
          ),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: playerWhite),
            decoration: const InputDecoration(
              hintText: 'Enter subtitle URL',
              hintStyle: TextStyle(color: Color(0x61FFFFFF)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter a valid subtitle URL.'),
          ),
        );
      }
      return;
    }

    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          url,
          title: 'External Subtitle',
          language: 'external',
        ),
      );
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('sub-visibility', 'yes');
      }
      await _applySubtitleDelay(_subtitleDelay, showFeedback: false);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('External subtitle added.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load this subtitle.'),
          ),
        );
      }
    }
  }

  Future<void> _importSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'ass', 'ssa', 'vtt', 'sub', 'smi', 'ttml'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      final sourceFile = path == null || path.isEmpty ? null : File(path);
      final bytes = picked.bytes ??
          (sourceFile != null && await sourceFile.exists()
              ? await sourceFile.readAsBytes()
              : null);
      if (bytes == null) {
        throw StateError('Android could not read the selected subtitle. Please select the file again.');
      }
      if (bytes.length < 8 || bytes.length > 10 * 1024 * 1024) {
        throw StateError('Subtitle file must be between 8 bytes and 10 MB.');
      }
      final ext = picked.extension?.toLowerCase() ?? '';
      final decodedText = _decodeSubtitleText(bytes);
      final detectedExtension = _detectSubtitleExtension(decodedText, ext);
      if (detectedExtension == 'sub') {
        throw StateError('MicroDVD .sub subtitles are not supported reliably. Please use SRT or ASS.');
      }
      final normalizedBytes = utf8.encode(decodedText.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));

      // Keep imported subtitles in app-private storage. File-picker paths can
      // be temporary content-provider paths on Android and may expire later.
      final support = await getApplicationSupportDirectory();
      final importDir = Directory('${support.path}/flixora_subtitles/imported');
      if (!await importDir.exists()) {
        await importDir.create(recursive: true);
      }
      final safeName = picked.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final baseName = safeName.contains('.')
          ? safeName.substring(0, safeName.lastIndexOf('.'))
          : safeName;
      final storedFile = File(
        '${importDir.path}/${DateTime.now().microsecondsSinceEpoch}_${baseName}.$detectedExtension',
      );
      await storedFile.writeAsBytes(normalizedBytes, flush: true);

      final match = RegExp(r'(?:^|[._ -])(en|bn|hi|ur|ar|es|fr|de|pt|ru|ja|ko|zh|tr|it|nl|pl|th|id|ms|fa)(?:[._ -]|$)',
          caseSensitive: false).firstMatch(picked.name);
      final language = match?.group(1)?.toLowerCase() ?? 'external';
      final track = SubtitleTrack.uri(Uri.file(storedFile.path).toString(),
          title: picked.name, language: language);
      await _activateSubtitleTrack(track);
      _subtitleManuallySelected = true;
      _automaticSubtitleRequestToken++;
      if (mounted && !_isDisposed) {
        setState(() {
          _selectedSubtitleLanguageCode = language;
          _subtitleVisibilityEnabled = true;
          _automaticEnglishTrack = track;
          _automaticSubtitleMessage = 'Imported and loaded: ${picked.name}';
        });
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subtitle loaded: ${picked.name}')));
      }
    } catch (error) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import subtitle: $error')));
      }
    }
  }

  String _audioTrackDetails(AudioTrack track) {
    final details = <String>[];
    final codec = track.codec?.trim();
    if (codec != null && codec.isNotEmpty) {
      details.add(codec.toUpperCase());
    }

    final channelLayout = track.channels?.trim() ?? '';
    if (channelLayout.isNotEmpty) {
      details.add(channelLayout);
    } else {
      final channelCount = track.channelscount ?? track.audiochannels;
      if (channelCount != null && channelCount > 0) {
        final label = switch (channelCount) {
          1 => 'Mono',
          2 => 'Stereo',
          6 => '5.1',
          8 => '7.1',
          _ => '$channelCount channels',
        };
        details.add(label);
      }
    }

    final sampleRate = track.samplerate;
    if (sampleRate != null && sampleRate > 0) {
      final rate = sampleRate / 1000;
      details.add('${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1)} kHz');
    }

    final bitrate = track.bitrate;
    if (bitrate != null && bitrate > 0) {
      details.add('${(bitrate / 1000).round()} kbps');
    }

    return details.join(' • ');
  }

  Future<void> _loadAudioDelayPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDelay = (prefs.getDouble('flixora_audio_delay') ?? 0.0)
          .clamp(-5.0, 5.0)
          .toDouble();
      if (!mounted || _isDisposed) return;
      _audioDelay = savedDelay;
      if (savedDelay.abs() >= 0.01) {
        await _applyAudioDelay(
          savedDelay,
          persist: false,
          showFeedback: false,
        );
      }
    } catch (error) {
      debugPrint('Audio delay preference load failed: $error');
    }
  }

  Future<bool> _applyAudioDelay(
    double value, {
    bool persist = true,
    bool showFeedback = true,
  }) async {
    final nextDelay = value.clamp(-5.0, 5.0).toDouble();
    final platformPlayer = _player.platform;
    if (platformPlayer is! NativePlayer) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio sync is not supported by this playback platform.')),
        );
      }
      return false;
    }

    try {
      // NativePlayer exposes libmpv's audio-delay property. Positive values
      // delay audio; negative values advance it relative to the video.
      await platformPlayer.setProperty(
        'audio-delay',
        nextDelay.toStringAsFixed(2),
      );
      if (!mounted || _isDisposed) return false;
      setState(() => _audioDelay = nextDelay);
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('flixora_audio_delay', nextDelay);
      }
      return true;
    } catch (error) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not adjust audio sync: $error')),
        );
      }
      return false;
    }
  }

  void _showAudioTracks() {
    final audioTracks = _tracks.audio;
    final selectedIndex = audioTracks.isEmpty
        ? -1
        : _selectedAudioTrackIndex.clamp(0, audioTracks.length - 1).toInt();

    _cancelHideTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        var showOutputDevices = false;
        var sheetAudioDelay = _audioDelay;

        return StatefulBuilder(
          builder: (sheetContext, updateSheet) {
            final availableDevices = _player.state.audioDevices;
            final outputDevices = <AudioDevice>[
              AudioDevice.auto(),
              ...availableDevices.where((device) => device.name != 'auto'),
            ];
            final selectedDeviceName = _player.state.audioDevice.name;

            Future<void> changeAudioDelay(double value) async {
              final next = value.clamp(-5.0, 5.0).toDouble();
              final applied = await _applyAudioDelay(next);
              if (applied) {
                updateSheet(() => sheetAudioDelay = next);
              }
            }

            Future<void> selectOutputDevice(AudioDevice device) async {
              try {
                await _player.setAudioDevice(device);
                if (!mounted || _isDisposed) return;
                setState(() {});
                updateSheet(() => showOutputDevices = false);
                final label = device.name == 'auto'
                    ? 'System default'
                    : (device.description.trim().isNotEmpty
                        ? device.description
                        : device.name);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Audio output: $label')),
                );
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not change audio output: $error')),
                  );
                }
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: playerPanel,
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0x66FFFFFF),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (showOutputDevices)
                            IconButton(
                              onPressed: () => updateSheet(() => showOutputDevices = false),
                              icon: const Icon(Icons.arrow_back_rounded, color: playerWhite),
                              tooltip: 'Back to audio tracks',
                            )
                          else
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: playerGold.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.graphic_eq_rounded,
                                color: playerGoldLight,
                                size: 23,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  showOutputDevices ? 'Audio output' : 'Audio language',
                                  style: const TextStyle(
                                    color: playerWhite,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  showOutputDevices
                                      ? 'Choose an available output device'
                                      : 'Choose the audio track for this movie',
                                  style: const TextStyle(
                                    color: Color(0x99FFFFFF),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (showOutputDevices)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(sheetContext).size.height * 0.52,
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: outputDevices.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final device = outputDevices[index];
                              final selected = device.name == selectedDeviceName;
                              final label = device.name == 'auto'
                                  ? 'System default'
                                  : (device.description.trim().isNotEmpty
                                      ? device.description
                                      : device.name);
                              return Material(
                                color: selected
                                    ? playerGold.withValues(alpha: 0.13)
                                    : playerBg,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => selectOutputDevice(device),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 13,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: selected
                                            ? playerGold.withValues(alpha: 0.8)
                                            : const Color(0x1FFFFFFF),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.speaker_rounded,
                                          color: playerGoldLight,
                                          size: 21,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                label,
                                                style: const TextStyle(
                                                  color: playerWhite,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (device.name != 'auto' &&
                                                  device.description.isNotEmpty &&
                                                  device.description != device.name)
                                                Text(
                                                  device.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0x80FFFFFF),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (selected)
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            color: playerGoldLight,
                                            size: 21,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      else ...[
                        if (audioTracks.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                'This stream does not expose alternate audio tracks.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0x99FFFFFF),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(sheetContext).size.height * 0.38,
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: audioTracks.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final track = audioTracks[index];
                                final selected = index == selectedIndex;
                                final label = _audioTrackLabel(track, index);
                                final rawTitle = track.title?.trim() ?? '';
                                final showTrackTitle = rawTitle.isNotEmpty &&
                                    rawTitle.toLowerCase() != label.toLowerCase() &&
                                    !RegExp(
                                      r'^(audio|track)\\s*#?\\s*\\d*$',
                                      caseSensitive: false,
                                    ).hasMatch(rawTitle);
                                final technicalDetails = _audioTrackDetails(track);

                                return Material(
                                  color: selected
                                      ? playerGold.withValues(alpha: 0.13)
                                      : playerBg,
                                  borderRadius: BorderRadius.circular(14),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _selectAudioTrack(track),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 13,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: selected
                                              ? playerGold.withValues(alpha: 0.8)
                                              : const Color(0x1FFFFFFF),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? playerGold.withValues(alpha: 0.18)
                                                  : const Color(0x14FFFFFF),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.audiotrack_rounded,
                                              color: selected
                                                  ? playerGoldLight
                                                  : const Color(0xB3FFFFFF),
                                              size: 19,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: playerWhite,
                                                    fontSize: 14,
                                                    fontWeight: selected
                                                        ? FontWeight.w800
                                                        : FontWeight.w600,
                                                  ),
                                                ),
                                                if (showTrackTitle) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    rawTitle,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0x80FFFFFF),
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                                if (technicalDetails.isNotEmpty) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    technicalDetails,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Color(0x80FFFFFF),
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(
                                              Icons.check_circle_rounded,
                                              color: playerGoldLight,
                                              size: 22,
                                            )
                                          else
                                            const Icon(
                                              Icons.circle_outlined,
                                              color: Color(0x55FFFFFF),
                                              size: 21,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        Container(
                          margin: const EdgeInsets.only(top: 14),
                          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                          decoration: BoxDecoration(
                            color: playerBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0x1FFFFFFF)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Audio sync',
                                          style: TextStyle(
                                            color: playerWhite,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          '− earlier  •  + later',
                                          style: TextStyle(
                                            color: Color(0x80FFFFFF),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: sheetAudioDelay > -5.0
                                        ? () => changeAudioDelay(sheetAudioDelay - 0.1)
                                        : null,
                                    icon: const Icon(Icons.remove_circle_outline_rounded),
                                    color: playerGoldLight,
                                    tooltip: 'Audio earlier by 0.1 seconds',
                                  ),
                                  Text(
                                    '${sheetAudioDelay >= 0 ? '+' : ''}${sheetAudioDelay.toStringAsFixed(1)}s',
                                    style: const TextStyle(
                                      color: playerGoldLight,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: sheetAudioDelay < 5.0
                                        ? () => changeAudioDelay(sheetAudioDelay + 0.1)
                                        : null,
                                    icon: const Icon(Icons.add_circle_outline_rounded),
                                    color: playerGoldLight,
                                    tooltip: 'Audio later by 0.1 seconds',
                                  ),
                                ],
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: sheetAudioDelay.abs() >= 0.01
                                      ? () => changeAudioDelay(0)
                                      : null,
                                  child: const Text('Reset sync'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Material(
                          color: playerBg,
                          borderRadius: BorderRadius.circular(13),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () => updateSheet(() => showOutputDevices = true),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.speaker_group_rounded,
                                    color: playerGoldLight,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Audio output device',
                                      style: TextStyle(
                                        color: playerWhite,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    selectedDeviceName == 'auto'
                                        ? 'System default'
                                        : selectedDeviceName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0x99FFFFFF),
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: Color(0x99FFFFFF),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_startHideTimer);
  }


  bool _isBanglaSubtitleTrack(SubtitleTrack track) {
    final language = (track.language ?? '').toLowerCase();
    final title = (track.title ?? '').toLowerCase();
    return language == 'bn' || language == 'ben' ||
        language.contains('bangla') || language.contains('bengali') ||
        title.contains('বাংলা');
  }

  bool _isEnglishSubtitleTrack(SubtitleTrack track) {
    final language = (track.language ?? '').toLowerCase();
    final title = (track.title ?? '').toLowerCase();
    return language == 'en' || language == 'eng' ||
        language.contains('english') || title.contains('english') ||
        title.startsWith('eng ') || title == 'eng';
  }

  int _automaticSubtitleMediaId() =>
      widget.movie.tmdbId > 0 ? widget.movie.tmdbId : widget.movie.id;

  String _automaticSubtitleCacheKey([String languageCode = 'en']) {
    final isSeries = widget.movie.mediaType == 'tv' || widget.movie.movieBoxIsSeries;
    final episode = isSeries
        ? '_s${_selectedSeasonNumber}_e${_selectedEpisodeNumber}'
        : '';
    final language = languageCode.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return '${language.isEmpty ? 'en' : language}_${widget.movie.mediaType}_${_automaticSubtitleMediaId()}$episode';
  }

  int _stableSubtitleCacheHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  String _subtitleLanguageName(String code) {
    const names = <String, String>{
      'bn+en': 'বাংলা + English',
      'en': 'English', 'eng': 'English',
      'bn': 'বাংলা', 'ben': 'বাংলা',
      'hi': 'Hindi', 'hin': 'Hindi',
      'ur': 'Urdu', 'urd': 'Urdu',
      'ar': 'Arabic', 'ara': 'Arabic',
      'es': 'Spanish', 'spa': 'Spanish',
      'fr': 'French', 'fre': 'French', 'fra': 'French',
      'de': 'German', 'ger': 'German', 'deu': 'German',
      'pt': 'Portuguese', 'por': 'Portuguese',
      'ru': 'Russian', 'rus': 'Russian',
      'ja': 'Japanese', 'jpn': 'Japanese',
      'ko': 'Korean', 'kor': 'Korean',
      'zh': 'Chinese', 'chi': 'Chinese', 'zho': 'Chinese',
      'tr': 'Turkish', 'tur': 'Turkish',
      'it': 'Italian', 'ita': 'Italian',
      'nl': 'Dutch', 'nld': 'Dutch',
      'pl': 'Polish', 'pol': 'Polish',
      'th': 'Thai', 'tha': 'Thai',
      'id': 'Indonesian', 'ind': 'Indonesian',
      'ms': 'Malay', 'may': 'Malay', 'msa': 'Malay',
      'fa': 'Persian', 'per': 'Persian', 'fas': 'Persian',
      'ta': 'Tamil', 'tam': 'Tamil',
      'te': 'Telugu', 'tel': 'Telugu',
      'kn': 'Kannada', 'kan': 'Kannada',
      'ml': 'Malayalam', 'mal': 'Malayalam',
      'vi': 'Vietnamese', 'vie': 'Vietnamese',
      'tl': 'Filipino', 'tgl': 'Filipino',
      'uk': 'Ukrainian', 'ukr': 'Ukrainian',
      'el': 'Greek', 'ell': 'Greek',
      'he': 'Hebrew', 'heb': 'Hebrew',
      'sv': 'Swedish', 'swe': 'Swedish',
      'no': 'Norwegian', 'nor': 'Norwegian',
      'da': 'Danish', 'dan': 'Danish',
      'fi': 'Finnish', 'fin': 'Finnish',
      'cs': 'Czech', 'ces': 'Czech', 'cze': 'Czech',
      'hu': 'Hungarian', 'hun': 'Hungarian',
      'ro': 'Romanian', 'ron': 'Romanian', 'rum': 'Romanian',
      'bg': 'Bulgarian', 'bul': 'Bulgarian',
      'hr': 'Croatian', 'hrv': 'Croatian',
      'sr': 'Serbian', 'srp': 'Serbian',
      'sk': 'Slovak', 'slk': 'Slovak', 'slo': 'Slovak',
      'sl': 'Slovenian', 'slv': 'Slovenian',
      'et': 'Estonian', 'est': 'Estonian',
      'lv': 'Latvian', 'lav': 'Latvian',
      'lt': 'Lithuanian', 'lit': 'Lithuanian',
    };
    final normalized = code.trim().toLowerCase().replaceAll('_', '-');
    final key = normalized.split(RegExp('[-_]')).first;
    return names[key] ?? (code.isEmpty ? 'Unknown language' : code.toUpperCase());
  }

  String _subtitleExtensionForOption(Map<String, dynamic> option) {
    const supported = <String>{'srt','ass','ssa','vtt','sub','smi','ttml','scc','lrc','rt','sup'};
    const aliases = <String, String>{
      'subrip':'srt','webvtt':'vtt','advanced substation alpha':'ass',
      'substation alpha':'ssa','microdvd':'sub','sami':'smi','timed text':'ttml',
      'realtext':'rt',
    };
    String normalize(dynamic raw) {
      final value = (raw ?? '').toString().trim().toLowerCase();
      if (value.isEmpty) return '';
      final filename = value.split('?').first.split('#').first;
      final match = RegExp(r'\.([a-z0-9]{2,8})$').firstMatch(filename);
      final token = (match?.group(1) ??
          value.replaceFirst(RegExp(r'^\.'), '').split(RegExp(r'[\s(/]')).first).trim();
      return aliases[token] ?? token;
    }
    for (final value in <dynamic>[option['format'], option['fileName'], option['downloadUrl']]) {
      final extension = normalize(value);
      if (supported.contains(extension)) return extension;
    }
    return 'srt';
  }

  String _decodeSubtitleText(List<int> bytes) {
    if (bytes.isEmpty) return '';
    // Subtitle packs frequently use UTF-16 LE/BE despite the .srt extension.
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    // Some subtitle files are UTF-16 without a BOM. Detect the common
    // ASCII-timestamp pattern by checking which byte lane contains NULs.
    if (bytes.length >= 8 && bytes.length.isEven) {
      var evenZeros = 0;
      var oddZeros = 0;
      final samplePairs = (bytes.length ~/ 2).clamp(1, 512);
      for (var i = 0; i < samplePairs * 2; i += 2) {
        if (bytes[i] == 0) evenZeros++;
        if (bytes[i + 1] == 0) oddZeros++;
      }
      final threshold = (samplePairs * 0.30).ceil();
      if (oddZeros >= threshold || evenZeros >= threshold) {
        final littleEndian = oddZeros > evenZeros;
        final units = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          units.add(littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(units).replaceAll('\u0000', '');
      }
    }
    var start = bytes.length >= 3 &&
            bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
        ? 3
        : 0;
    final text = utf8.decode(bytes.sublist(start), allowMalformed: true);
    return text.replaceAll('\u0000', '').replaceFirst('\uFEFF', '');
  }

  String _detectSubtitleExtension(String source, String preferred) {
    final text = source.replaceFirst('\uFEFF', '').trim();
    final lower = text.toLowerCase();
    if (text.isEmpty) throw StateError('The downloaded subtitle file is empty.');
    if (lower.startsWith('<!doctype html') || lower.startsWith('<html') ||
        lower.startsWith('{') ||
        (lower.startsWith('[') && !lower.startsWith('[script info]'))) {
      throw StateError('The provider returned a web page or data response, not a subtitle file.');
    }
    if (lower.startsWith('webvtt')) return 'vtt';
    if (lower.contains('[script info]') || lower.contains('[v4+ styles]') || lower.contains(r'{\an')) {
      if (!lower.contains('[events]') || !lower.contains('dialogue:')) {
        throw StateError('The ASS/SSA subtitle is missing dialogue events.');
      }
      return preferred == 'ssa' ? 'ssa' : 'ass';
    }
    if (lower.contains('<sami') || lower.contains('<sync')) return 'smi';
    if (lower.contains('<tt') || lower.contains('<ttml')) return 'ttml';
    if (text.contains('-->')) {
      final hasCueTime = RegExp(
        r'^\s*(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}\s+-->\s+(?:\d{1,2}:)?\d{2}:\d{2}[,.]\d{3}',
        multiLine: true,
      ).hasMatch(text);
      if (!hasCueTime) {
        throw StateError('The selected subtitle has no valid SRT/VTT cue timestamps.');
      }
      return lower.contains('webvtt') ? 'vtt' : 'srt';
    }
    if (RegExp(r'\{\d+\}\{\d+\}').hasMatch(text) || lower.contains('[subtitle]')) return 'sub';
    if (RegExp(r'^\s*\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]', multiLine: true).hasMatch(text)) return 'lrc';
    if (RegExp(r'^\s*\d{2}:\d{2}:\d{2};\d{2}', multiLine: true).hasMatch(text) || lower.contains('scenarist_scc')) return 'scc';
    if (lower.contains('<time') || lower.contains('<window')) return 'rt';
    if (preferred == 'sub' || preferred == 'smi' || preferred == 'ttml' ||
        preferred == 'scc' || preferred == 'lrc' || preferred == 'rt' ||
        preferred == 'ass' || preferred == 'ssa' || preferred == 'srt' || preferred == 'vtt') {
      return preferred;
    }
    throw StateError('Unsupported subtitle format: $preferred');
  }

  Future<File> _downloadAutomaticSubtitle(Map<String, dynamic> option) async {
    final languageCode = (option['language'] ?? 'en').toString().toLowerCase();
    final downloadUrl = (option['downloadUrl'] ?? '').toString();
    final uri = Uri.tryParse(downloadUrl);
    final provider = (option['provider'] ?? '').toString().toLowerCase();
    final isSubSource = provider == 'subsource';
    final isISubtitles = provider == 'isubtitles';
    final isBollyNook = provider == 'bollynook';
    final isGestdown = provider == 'gestdown';
    final isTVSubtitles = provider == 'tvsubtitles';
    final isSubDl = uri?.host == 'dl.subdl.com';
    final isOpenSubtitles = uri != null &&
        (uri.host == 'opensubtitles.com' || uri.host.endsWith('.opensubtitles.com'));
    final isMovieBoxSubtitle = provider == 'moviebox';
    final isProviderDownload = (isSubSource || isISubtitles || isBollyNook ||
        isGestdown || isTVSubtitles || isSubDl || isOpenSubtitles);
    if (isMovieBoxSubtitle) {
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
        throw StateError('MovieBox returned an invalid HTTPS subtitle link.');
      }
    } else if (isSubSource) {
      final id = int.tryParse((option['subsourceId'] ?? '').toString()) ?? 0;
      if (id <= 0) throw StateError('SubSource returned an invalid subtitle ID.');
    } else if (isISubtitles) {
      if (uri == null || uri.scheme != 'https' ||
          !(uri.host == 'isubtitles.org' || uri.host == 'www.isubtitles.org') ||
          !uri.path.startsWith('/download/')) {
        throw StateError('iSubtitles returned an invalid download link.');
      }
    } else if (isBollyNook) {
      if (uri == null || uri.scheme != 'https' ||
          !(uri.host == 'bollynook.com' || uri.host == 'www.bollynook.com')) {
        throw StateError('BollyNook returned an invalid download link.');
      }
    } else if (isGestdown) {
      if (uri == null || uri.scheme != 'https' ||
          uri.host != 'api.gestdown.info' || !uri.path.startsWith('/')) {
        throw StateError('Gestdown returned an invalid download link.');
      }
    } else if (isTVSubtitles) {
      if (uri == null || uri.scheme != 'https' ||
          uri.host != 'www.tvsubtitles.net') {
        throw StateError('TVSubtitles returned an invalid download link.');
      }
    } else if (uri == null || uri.scheme != 'https' ||
        !(isSubDl || isOpenSubtitles) ||
        (isSubDl && !uri.path.startsWith('/subtitle/'))) {
      throw StateError('Subtitle provider returned an invalid file link.');
    }

    final preferredExtension = _subtitleExtensionForOption(option);
    final support = await getApplicationSupportDirectory();
    final cacheDir = Directory('${support.path}/flixora_subtitles');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    // Do not include expiring signed download URLs in the cache key.
    // The same release should reuse its validated local subtitle after relaunch.
    // Deduplicate equivalent releases across independent extensions. The
    // media/language cache prefix already isolates each movie or episode.
    final releaseIdentity = [
      option['releaseName'] ?? '',
      option['fileName'] ?? '',
      if ((option['releaseName'] ?? '').toString().isEmpty && (option['fileName'] ?? '').toString().isEmpty) uri?.path ?? '',
    ].join('_').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final cacheBase = '${_automaticSubtitleCacheKey(languageCode)}_${_stableSubtitleCacheHash(releaseIdentity)}';
    final preferredCache = File('${cacheDir.path}/${cacheBase}.$preferredExtension');
    if (await preferredCache.exists() && await preferredCache.length() > 16) {
      try {
        final cachedBytes = await preferredCache.readAsBytes();
        if (preferredExtension == 'sup' ||
            _detectSubtitleExtension(_decodeSubtitleText(cachedBytes), preferredExtension) == preferredExtension) {
          return preferredCache;
        }
      } catch (_) {}
      await preferredCache.delete();
    }

    late http.Response download;
    if (isProviderDownload) {
      final client = supabaseClient;
      if (client == null) throw StateError('Subtitle service is unavailable.');
      final result = await client.functions.invoke(
        'flixora-subtitles',
        body: {
          'action': isSubSource ? 'download_subsource' : 'download_provider_subtitle',
          'provider': provider,
          if (isSubSource) 'subtitleId': option['subsourceId'],
          if (!isSubSource) 'downloadUrl': downloadUrl,
          if (!isSubSource) 'pageUrl': option['pageUrl'] ?? '',
          'releaseName': option['releaseName'] ?? '',
          'language': languageCode,
          'mediaType': (widget.movie.mediaType == 'tv' || widget.movie.movieBoxIsSeries) ? 'tv' : 'movie',
          if (widget.movie.mediaType == 'tv' || widget.movie.movieBoxIsSeries) ...{
            'season': _selectedSeasonNumber,
            'episode': _selectedEpisodeNumber,
          },
        },
      ).timeout(const Duration(seconds: 35));
      final payload = result.data;
      if (payload is! Map || (payload['contentBase64'] ?? '').toString().isEmpty) {
        final message = payload is Map
            ? (payload['error'] ?? 'Subtitle provider download failed.')
            : 'Subtitle provider download failed.';
        throw StateError(message.toString());
      }
      final bytes = base64Decode(payload['contentBase64'].toString());
      download = http.Response.bytes(bytes, 200, headers: {
        'content-type': 'application/octet-stream',
      });
    } else {
      download = await http.get(uri!, headers: const {
        'Accept': 'text/plain, text/vtt, application/octet-stream, */*',
        'User-Agent': 'FLIXORA Subtitle Client/1.0',
      }).timeout(const Duration(seconds: 25));
      if (isMovieBoxSubtitle && download.request?.url.scheme != 'https') throw StateError('MovieBox subtitle download redirected to an insecure URL.');
      // Providers may briefly rate-limit a valid subtitle link. Respect their
      // Retry-After hint once, then let the caller fall back to another result.
      if (download.statusCode == 429) {
        final retryAfter = int.tryParse(download.headers['retry-after'] ?? '');
        final waitSeconds = (retryAfter ?? 2).clamp(1, 8).toInt();
        await Future<void>.delayed(Duration(seconds: waitSeconds));
        download = await http.get(uri, headers: const {
          'Accept': 'text/plain, text/vtt, application/octet-stream, */*',
          'User-Agent': 'FLIXORA Subtitle Client/1.0',
        }).timeout(const Duration(seconds: 25));
      }
    }
    if (download.statusCode != 200 || download.bodyBytes.length < 16 ||
        download.bodyBytes.length > 10 * 1024 * 1024) {
      throw StateError('Could not download the selected subtitle (HTTP ${download.statusCode}).');
    }
    final bytes = download.bodyBytes;
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
      throw StateError('The provider returned a ZIP archive instead of an unpacked subtitle file.');
    }
    final contentType = (download.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('text/html') || contentType.contains('application/json')) {
      throw StateError('The provider returned an error page, not a subtitle file.');
    }
    final isPgs = preferredExtension == 'sup' &&
        bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x47;
    final subtitleText = _decodeSubtitleText(bytes);
    final actualExtension = isPgs ? 'sup' : _detectSubtitleExtension(subtitleText, preferredExtension);
    if (actualExtension == 'sup' && !isPgs) {
      throw StateError('The PGS subtitle data is incomplete or invalid.');
    }
    final cachedFile = File('${cacheDir.path}/${cacheBase}.$actualExtension');
    if (await cachedFile.exists()) await cachedFile.delete();
    if (actualExtension == 'sup') {
      await cachedFile.writeAsBytes(bytes, flush: true);
    } else {
      await cachedFile.writeAsString(
        subtitleText.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
        encoding: utf8,
        flush: true,
      );
    }
    return cachedFile;
  }

  Future<bool> _activateEmbeddedSubtitleIfAvailable() async {
    if (_isDisposed || widget.localFilePath != null ||
        _subtitleManuallySelected || _automaticSubtitleLoading ||
        _automaticEnglishTrack != null) return false;
    final embeddedTracks = _tracks.subtitle
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList(growable: false);
    if (embeddedTracks.isEmpty) return false;
    final orderedTracks = <SubtitleTrack>[
      ...embeddedTracks.where(_isBanglaSubtitleTrack),
      ...embeddedTracks.where(_isEnglishSubtitleTrack),
      ...embeddedTracks.where((track) =>
          !_isBanglaSubtitleTrack(track) && !_isEnglishSubtitleTrack(track)),
    ];
    for (final track in orderedTracks) {
      if (_isDisposed || _subtitleManuallySelected) return false;
      try {
        await _player.setSubtitleTrack(track);
        final native = _player.platform;
        if (native is NativePlayer) {
          await native.setProperty('sub-visibility', 'yes');
        }
        await _applySubtitleDelay(_subtitleDelay, showFeedback: false);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (_isDisposed) return false;
        final activeId = _player.state.track.subtitle.id;
        if (activeId != track.id) {
          debugPrint('FLIXORA embedded subtitle not active: requested=${track.id}, active=$activeId');
          continue;
        }
        if (mounted) {
          setState(() {
            _automaticEnglishTrack = track;
            _subtitleVisibilityEnabled = true;
            _selectedSubtitleLanguageCode = (track.language ?? '').toLowerCase();
            _automaticSubtitleMessage =
                'Available in this video · ${_subtitleLanguageName(track.language ?? '')}';
          });
        }
        debugPrint('FLIXORA embedded subtitle activated: id=${track.id}, language=${track.language}');
        return true;
      } catch (error) {
        debugPrint('FLIXORA embedded subtitle selection failed for ${track.id}: $error');
      }
    }
    return false;
  }

  String _movieBoxSubtitleLanguage(Map<String, dynamic> subtitle) {
    // WeFeed has returned multiple metadata shapes across MovieBox releases.
    // Prefer ISO language codes, then display-name fields such as lanName.
    final rawValue = <dynamic>[
      subtitle['language'],
      subtitle['lang'],
      subtitle['lan'],
      subtitle['languageCode'],
      subtitle['langCode'],
      subtitle['lanCode'],
      subtitle['languageName'],
      subtitle['langName'],
      subtitle['lanName'],
      subtitle['language_name'],
      subtitle['lang_name'],
      subtitle['lan_name'],
      subtitle['label'],
      subtitle['name'],
      subtitle['fileName'],
      subtitle['filename'],
    ].firstWhere(
      (value) => value != null && value.toString().trim().isNotEmpty,
      orElse: () => '',
    );
    final raw = (rawValue is Map
            ? (rawValue['code'] ?? rawValue['lang'] ?? rawValue['name'] ?? '')
            : rawValue)
        .toString()
        .trim()
        .toLowerCase();
    final parts = raw
        .split(RegExp(r'[+/,;|]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    String normalize(String value) {
      final token = value
          .split(RegExp(r'[-_\\s]'))
          .firstWhere((part) => part.isNotEmpty, orElse: () => value)
          .toLowerCase();
      const aliases = <String, String>{
        'english': 'en', 'eng': 'en', 'en': 'en',
        'bengali': 'bn', 'bangla': 'bn', 'ben': 'bn', 'beng': 'bn', 'bn': 'bn',
        'hindi': 'hi', 'hin': 'hi', 'hi': 'hi',
        'urdu': 'ur', 'urd': 'ur', 'ur': 'ur',
        'arabic': 'ar', 'ara': 'ar', 'ar': 'ar',
        'japanese': 'ja', 'jpn': 'ja', 'ja': 'ja',
        'korean': 'ko', 'kor': 'ko', 'ko': 'ko',
        'chinese': 'zh', 'chi': 'zh', 'zho': 'zh', 'zh': 'zh',
        'spanish': 'es', 'spa': 'es', 'es': 'es',
        'french': 'fr', 'fre': 'fr', 'fra': 'fr', 'fr': 'fr',
        'german': 'de', 'ger': 'de', 'deu': 'de', 'de': 'de',
        'portuguese': 'pt', 'por': 'pt', 'pt': 'pt',
        'russian': 'ru', 'rus': 'ru', 'ru': 'ru',
        'turkish': 'tr', 'tur': 'tr', 'tr': 'tr',
        'italian': 'it', 'ita': 'it', 'it': 'it',
        'dutch': 'nl', 'nld': 'nl', 'nl': 'nl',
        'polish': 'pl', 'pol': 'pl', 'pl': 'pl',
        'thai': 'th', 'tha': 'th', 'th': 'th',
        'indonesian': 'id', 'ind': 'id', 'id': 'id',
        'malay': 'ms', 'may': 'ms', 'msa': 'ms', 'ms': 'ms',
        'persian': 'fa', 'per': 'fa', 'fas': 'fa', 'fa': 'fa',
        'tamil': 'ta', 'tam': 'ta', 'ta': 'ta',
        'telugu': 'te', 'tel': 'te', 'te': 'te',
        'kannada': 'kn', 'kan': 'kn', 'kn': 'kn',
        'malayalam': 'ml', 'mal': 'ml', 'ml': 'ml',
        'vietnamese': 'vi', 'vie': 'vi', 'vi': 'vi',
        'filipino': 'tl', 'tagalog': 'tl', 'tgl': 'tl', 'tl': 'tl',
        'ukrainian': 'uk', 'ukr': 'uk', 'uk': 'uk',
        'greek': 'el', 'ell': 'el', 'el': 'el',
        'hebrew': 'he', 'heb': 'he', 'he': 'he',
        'swedish': 'sv', 'swe': 'sv', 'sv': 'sv',
        'norwegian': 'no', 'nor': 'no', 'no': 'no',
        'danish': 'da', 'dan': 'da', 'da': 'da',
        'finnish': 'fi', 'fin': 'fi', 'fi': 'fi',
        'czech': 'cs', 'ces': 'cs', 'cze': 'cs', 'cs': 'cs',
        'hungarian': 'hu', 'hun': 'hu', 'hu': 'hu',
        'romanian': 'ro', 'ron': 'ro', 'rum': 'ro', 'ro': 'ro',
        'bulgarian': 'bg', 'bul': 'bg', 'bg': 'bg',
        'croatian': 'hr', 'hrv': 'hr', 'hr': 'hr',
        'serbian': 'sr', 'srp': 'sr', 'sr': 'sr',
        'slovak': 'sk', 'slk': 'sk', 'slo': 'sk', 'sk': 'sk',
        'slovenian': 'sl', 'slv': 'sl', 'sl': 'sl',
        'estonian': 'et', 'est': 'et', 'et': 'et',
        'latvian': 'lv', 'lav': 'lv', 'lv': 'lv',
        'lithuanian': 'lt', 'lit': 'lt', 'lt': 'lt',
      };
      return aliases[token] ?? token;
    }
    final normalized = parts.map(normalize).toSet().toList(growable: false);
    if (normalized.length > 1 && normalized.contains('bn') && normalized.contains('en')) {
      return 'bn+en';
    }
    if (normalized.isNotEmpty) return normalized.first;
    return 'und';
  }

  List<Map<String, dynamic>> _extractMovieBoxSubtitleItems(
    Map<String, dynamic> response,
  ) {
    const listKeys = <String>{
      'subtitles',
      'subtitle',
      'subTitleList',
      'subtitleList',
      'subtitle_list',
      'subtitle_list_data',
      'captions',
      'captionList',
      'caption_list',
      'externalSubtitles',
      'external_subtitles',
    };
    const nestedKeys = <String>{
      'data',
      'result',
      'results',
      'stream',
      'playInfo',
      'play_info',
      'payload',
      'response',
    };

    List<Map<String, dynamic>> asSubtitleMaps(dynamic value) {
      if (value is! List) return const <Map<String, dynamic>>[];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    List<Map<String, dynamic>>? find(dynamic value, int depth) {
      if (depth > 5 || value is! Map) return null;
      final map = Map<String, dynamic>.from(value);
      for (final entry in map.entries) {
        if (listKeys.contains(entry.key.toString())) {
          final items = asSubtitleMaps(entry.value);
          if (items.isNotEmpty) return items;
          if (entry.value is Map) {
            final nested = find(entry.value, depth + 1);
            if (nested != null && nested.isNotEmpty) return nested;
          }
        }
      }
      for (final key in nestedKeys) {
        final child = map[key];
        if (child is Map) {
          final items = find(child, depth + 1);
          if (items != null && items.isNotEmpty) return items;
        }
      }
      // Some wrappers place the play-info object under an unlabelled key.
      for (final child in map.values) {
        if (child is Map) {
          final items = find(child, depth + 1);
          if (items != null && items.isNotEmpty) return items;
        }
      }
      return null;
    }

    final items = find(response, 0) ?? const <Map<String, dynamic>>[];
    return items.where((item) => _movieBoxSubtitleUrl(item).isNotEmpty)
        .toList(growable: false);
  }

  String _movieBoxSubtitleUrl(Map<String, dynamic> subtitle) {
    const urlKeys = <String>[
      'url',
      'downloadUrl',
      'download_url',
      'subtitleUrl',
      'subtitle_url',
      'fileUrl',
      'file_url',
      'captionUrl',
      'caption_url',
      'srtUrl',
      'vttUrl',
      'src',
      'link',
      'path',
    ];
    for (final key in urlKeys) {
      final value = subtitle[key];
      final candidate = value is Map
          ? (value['url'] ?? value['uri'] ?? value['link'] ?? '').toString().trim()
          : (value ?? '').toString().trim();
      if (candidate.isEmpty) continue;
      final uri = Uri.tryParse(candidate);
      if (uri != null &&
          (uri.scheme == 'https' || uri.scheme == 'http') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        return candidate;
      }
    }
    return '';
  }

  List<Map<String, dynamic>> _movieBoxSubtitleOptions([List<Map<String, dynamic>>? source]) {
    final subtitles = source ?? _movieBoxSubtitles;
    final options = <Map<String, dynamic>>[];
    for (var index = 0; index < subtitles.length; index++) {
      final subtitle = subtitles[index];
      final url = _movieBoxSubtitleUrl(subtitle);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      final language = _movieBoxSubtitleLanguage(subtitle);
      final fileName = (subtitle['fileName'] ??
              subtitle['filename'] ??
              subtitle['file_name'] ??
              subtitle['releaseName'] ??
              subtitle['title'] ??
              (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : ''))
          .toString()
          .trim();
      final releaseName = (subtitle['releaseName'] ??
              subtitle['name'] ??
              subtitle['title'] ??
              subtitle['label'] ??
              fileName)
          .toString()
          .trim()
          .replaceAll(RegExp('moviebox', caseSensitive: false), 'FLIXORA');
      final format = (subtitle['format'] ??
              (fileName.contains('.') ? fileName.split('.').last : 'srt'))
          .toString()
          .toLowerCase();
      options.add(<String, dynamic>{
        'provider': 'moviebox',
        'providerSource': 'moviebox',
        'language': language,
        'releaseName': releaseName.isEmpty
            ? '${_subtitleLanguageName(language)} · Subtitle ${index + 1}'
            : releaseName,
        'fileName': fileName,
        'downloadUrl': url,
        'format': format,
        'movieBoxSubtitle': subtitle,
        'movieBoxIndex': index,
      });
    }
    options.sort((a, b) {
      int priority(Map<String, dynamic> option) {
        final code = (option['language'] ?? '').toString();
        return code == 'bn' ? 0 : (code == 'bn+en' ? 1 : (code == 'en' ? 2 : 3));
      }
      return priority(a).compareTo(priority(b));
    });
    return options;
  }

  Future<void> _ensureAutomaticEnglishSubtitle() async {
    if (_isDisposed || widget.localFilePath != null || !_playerIsOnline || _automaticSubtitleLoading || _subtitleManuallySelected) return;
    final requestToken = ++_automaticSubtitleRequestToken;
    if (mounted) setState(() { _automaticSubtitleLoading = true; _automaticSubtitleMessage = 'Loading available subtitles…'; });
    try {
      var embeddedTrackSelected = false;
      for (var attempt = 0; attempt < 12; attempt++) {
        if (requestToken != _automaticSubtitleRequestToken || _isDisposed) return;
        embeddedTrackSelected = await _activateEmbeddedSubtitleIfAvailable();
        if (embeddedTrackSelected) break;
        if (attempt < 11) await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (requestToken != _automaticSubtitleRequestToken || _isDisposed) return;
      final available = widget.movie.isMovieBox ? _movieBoxSubtitleOptions() : <Map<String,dynamic>>[];
      if (mounted && !_isDisposed) setState(() {
        _automaticSubtitleOptions = available;
        _automaticSubtitleMessage = available.isNotEmpty ? available.length.toString() + ' subtitle(s) available' : (widget.movie.isMovieBox ? 'No subtitles were returned for this title or episode.' : (embeddedTrackSelected ? 'Embedded subtitle track is active' : 'No embedded subtitle tracks are available. You can import a subtitle file.'));
      });
    } catch (error) {
      debugPrint('FLIXORA MovieBox subtitles: $error');
      if (mounted && !_isDisposed && requestToken == _automaticSubtitleRequestToken) setState(() { _automaticSubtitleMessage = 'Subtitles could not be loaded. You can import a subtitle file.'; });
    } finally {
      if (mounted && !_isDisposed && requestToken == _automaticSubtitleRequestToken) setState(() => _automaticSubtitleLoading = false);
    }
  }
  Future<void> _selectAutomaticSubtitleLanguage(Map<String, dynamic> option) async {
    final code = (option['language'] ?? 'en').toString().toLowerCase();
    try {
      // Keep the chosen language, but try its other provider/release results
      // if the selected link is expired or rate-limited.
      final candidates = <Map<String, dynamic>>[
        option,
        ..._automaticSubtitleOptions.where((candidate) =>
            (candidate['language'] ?? '').toString().toLowerCase() == code &&
            (candidate['downloadUrl'] ?? '') != (option['downloadUrl'] ?? '')),
      ];
      File? file;
      Object? lastDownloadError;
      for (final candidate in candidates) {
        try {
          file = await _downloadAutomaticSubtitle(candidate);
          break;
        } catch (error) {
          lastDownloadError = error;
          debugPrint('FLIXORA subtitle language fallback failed: $error');
        }
      }
      if (file == null) {
        throw StateError(
          'No usable ${_subtitleLanguageName(code)} subtitle could be downloaded. ${lastDownloadError ?? ''}',
        );
      }
      if (!mounted || _isDisposed) return;
      final track = SubtitleTrack.uri(
        Uri.file(file.path).toString(),
        title: _subtitleLanguageName(code), language: code);
      _subtitleManuallySelected = true;
      _automaticSubtitleRequestToken++;
      await _activateSubtitleTrack(track);
      if (mounted && !_isDisposed) {
        setState(() {
          _selectedSubtitleLanguageCode = code;
          _subtitleVisibilityEnabled = true;
          _automaticEnglishTrack = track;
          _automaticSubtitleMessage = '${_subtitleLanguageName(code)} track active';
        });
        Navigator.of(context).maybePop();
        _startHideTimer();
      }
    } catch (error) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load subtitle: $error')));
      }
    }
  }

  Future<void> _setSubtitleVisibility(bool enabled) async {
    try {
      final currentTrack = _player.state.track.subtitle;
      final selectedTrack = enabled
          ? (_automaticEnglishTrack ??
              (currentTrack.id != 'no' ? currentTrack : SubtitleTrack.auto()))
          : SubtitleTrack.no();

      // Apply visibility through the player track API on every platform,
      // then mirror it to libmpv on Android so the switch always controls
      // the active subtitle track as well as native subtitle rendering.
      await _player.setSubtitleTrack(selectedTrack);
      final native = _player.platform;
      if (native is NativePlayer) {
        await native.setProperty('sub-visibility', enabled ? 'yes' : 'no');
      }

      if (!mounted || _isDisposed) return;
      setState(() {
        if (enabled && selectedTrack.id != 'auto' && selectedTrack.id != 'no') {
          _automaticEnglishTrack = selectedTrack;
        }
        _subtitleVisibilityEnabled = enabled;
      });
    } catch (error) {
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not change subtitle visibility: $error')),
        );
      }
    }
  }

  String _subtitleTrackDisplayName(SubtitleTrack track) {
    final language = (track.language ?? '').trim();
    final title = (track.title ?? '').trim();
    final generic = RegExp(r'^(subtitle|subtitles?|track)\s*#?\s*\d*$',
        caseSensitive: false);
    if (language.isNotEmpty) return _subtitleLanguageName(language);
    if (title.isNotEmpty && !generic.hasMatch(title)) return title;
    return 'Other language';
  }


  void _showSubtitleDelaySettings() {
    _cancelHideTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: playerPanel.withValues(alpha: 0.48),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: Color(0x66D6AD45)),
      ),
      builder: (sheetContext) {
        var delay = _subtitleDelay;
        return StatefulBuilder(
          builder: (context, updateSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Subtitle Delay',
                            style: TextStyle(
                              color: playerGoldLight,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close, color: playerWhite),
                        ),
                      ],
                    ),
                    const Text(
                      'Adjust subtitle timing to match the dialogue.',
                      style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        '${delay >= 0 ? '+' : ''}${delay.toStringAsFixed(1)} s',
                        style: const TextStyle(
                          color: playerGoldLight,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Slider(
                      value: delay.clamp(-10.0, 10.0).toDouble(),
                      min: -10,
                      max: 10,
                      divisions: 200,
                      activeColor: playerGold,
                      inactiveColor: const Color(0x55FFFFFF),
                      onChanged: (value) => updateSheet(() => delay = value),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('-10s Earlier', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                        Text('10s Later', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: playerGoldLight,
                              side: const BorderSide(color: playerGold),
                            ),
                            onPressed: () => updateSheet(() => delay = 0),
                            child: const Text('Reset'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: playerGold,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () async {
                              final applied = await _applySubtitleDelay(delay);
                              if (!applied || !mounted || _isDisposed) return;
                              await _saveSubtitlePreferences();
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              _startHideTimer();
                            },
                            child: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_startHideTimer);
  }

  void _showSubtitleTracks() {
    _cancelHideTimer();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close subtitles',
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final landscape = screen.width >= screen.height;
        final panelWidth = landscape
            ? (screen.width * 0.44).clamp(340.0, 500.0).toDouble()
            : screen.width * 0.94;
        final panelHeight = landscape ? screen.height * 0.94 : screen.height * 0.78;
        return SafeArea(
          child: Align(
            alignment: landscape ? Alignment.centerRight : Alignment.bottomCenter,
            child: SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: StatefulBuilder(
                builder: (sheetContext, updateSheet) {
                  final embedded = _tracks.subtitle
                      .where((track) => track.id != 'auto' && track.id != 'no')
                      .toList(growable: false);
                  final entries = <String, Map<String, dynamic>>{};
                  for (final track in embedded) {
                    final code = (track.language ?? '').trim().toLowerCase();
                    if (code.isNotEmpty) {
                      entries.putIfAbsent(code, () => {
                        'kind': 'embedded', 'language': code, 'track': track,
                        'releaseName': _subtitleTrackDisplayName(track),
                      });
                    }
                  }
                  if (!widget.movie.isMovieBox) {
                    for (final option in _automaticSubtitleOptions) {
                      final code = (option['language'] ?? '').toString().toLowerCase();
                      if (code.isNotEmpty) entries.putIfAbsent(code, () => {...option, 'kind': 'automatic'});
                    }
                  }
                  final movieBoxOptions = _movieBoxSubtitleOptions();
                  for (var index = 0; index < movieBoxOptions.length; index++) {
                    final option = movieBoxOptions[index];
                    final code = (option['language'] ?? 'und').toString();
                    final subtitle = option['movieBoxSubtitle'] as Map<String, dynamic>;
                    entries['moviebox:' + index.toString() + ':' + code] = {...option, 'kind':'moviebox','language':code,'subtitle':subtitle};
                  }

                  Future<void> choose(Map<String, dynamic> item) async {
                    final code = (item['language'] ?? '').toString().toLowerCase();
                    if (item['kind'] == 'embedded' && item['track'] is SubtitleTrack) {
                      await _selectSubtitleTrack(item['track'] as SubtitleTrack);
                      if (!mounted || _isDisposed) return;
                      setState(() {
                        _selectedSubtitleLanguageCode = code;
                        _subtitleVisibilityEnabled = true;
                      });
                    } else if (item['kind'] == 'moviebox' && item['subtitle'] is Map) {
                      await _selectMovieBoxSubtitle(Map<String, dynamic>.from(item['subtitle'] as Map));
                      if (!mounted || _isDisposed) return;
                      setState(() {
                        _selectedSubtitleLanguageCode = code;
                        _subtitleVisibilityEnabled = true;
                      });
                    } else {
                      await _selectAutomaticSubtitleLanguage(item);
                    }
                    if (sheetContext.mounted) updateSheet(() {});
                  }

                  Widget row(String title, String code, VoidCallback onTap, {
                    bool selected = false, String? detail, Widget? trailing,
                  }) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      decoration: BoxDecoration(
                        color: selected ? playerGold.withValues(alpha: 0.12) : const Color(0x33141414),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? playerGold : const Color(0x25FFFFFF)),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 1),
                        title: Text(title, style: TextStyle(
                          color: selected ? playerGoldLight : playerWhite,
                          fontSize: 14, fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        )),
                        subtitle: detail == null || detail.isEmpty ? null : Text(
                          detail, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 10),
                        ),
                        trailing: trailing ?? (selected
                          ? const Icon(Icons.check_rounded, color: playerGoldLight)
                          : const Icon(Icons.circle_outlined, color: Color(0x55FFFFFF))),
                        onTap: onTap,
                      ),
                    );
                  }

                  return Material(
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0x66101010),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: playerGold.withValues(alpha: 0.48)),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 28)],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(17, 13, 12, 8),
                              child: Row(
                                children: [
                                  const Expanded(child: Text('Subtitle', style: TextStyle(
                                    color: playerWhite, fontSize: 21, fontWeight: FontWeight.w800,
                                  ))),
                                  Switch.adaptive(
                                    value: _subtitleVisibilityEnabled,
                                    activeThumbColor: Colors.black,
                                    activeTrackColor: playerGold,
                                    inactiveThumbColor: Colors.white70,
                                    inactiveTrackColor: const Color(0xFF454545),
                                    onChanged: (value) async {
                                      await _setSubtitleVisibility(value);
                                      if (sheetContext.mounted) updateSheet(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0x28FFFFFF)),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(15, 12, 15, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text('Choose language', style: TextStyle(
                                      color: Color(0x99FFFFFF), fontSize: 11,
                                    )),
                                    const SizedBox(height: 9),
                                    if (entries.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 18),
                                        child: Text(
                                          (_automaticSubtitleLoading && !widget.movie.isMovieBox) ? 'Finding available languages…' :
                                            (_automaticSubtitleMessage ?? (widget.movie.isMovieBox ? 'No subtitle tracks are available for this episode.' : 'No subtitle tracks are available.')),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                                        ),
                                      )
                                    else
                                      ...entries.entries.map((entry) {
                                        final item = entry.value;
                                        final code = entry.key;
                                        final active = _selectedSubtitleLanguageCode.toLowerCase() == code &&
                                            _subtitleVisibilityEnabled;
                                        return row(
                                          _subtitleLanguageName((item['language'] ?? code).toString()), code,
                                          () => choose(item),
                                          selected: active,
                                          detail: (item['releaseName'] ?? '').toString(),
                                        );
                                      }),
                                    const SizedBox(height: 8),
                                    row('Import subtitle file', 'import', () {
                                      Navigator.of(sheetContext).pop();
                                      _importSubtitleFile();
                                    }, detail: 'Load a subtitle from your device',
                                      trailing: const Icon(Icons.file_upload_outlined, color: playerGoldLight)),
                                    row('Add subtitle URL', 'external', () {
                                      Navigator.of(sheetContext).pop();
                                      _addExternalSubtitle();
                                    }, detail: 'Load a subtitle from a web URL',
                                      trailing: const Icon(Icons.link_rounded, color: playerGoldLight)),
                                    row('Download Subtitle', 'download', () {
                                      Navigator.of(sheetContext).pop();
                                      _showSubtitleDownloadPanel();
                                    }, detail: 'Browse available subtitles',
                                      trailing: const Icon(Icons.download_rounded, color: playerGoldLight)),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(height: 1, color: Color(0x28FFFFFF)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              child: Row(
                                children: [
                                  Expanded(child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _showSubtitleStyleSettings();
                                    },
                                    icon: const Icon(Icons.palette_outlined, size: 17),
                                    label: const Text('Style'),
                                    style: TextButton.styleFrom(foregroundColor: playerGoldLight),
                                  )),
                                  Container(width: 1, height: 23, color: const Color(0x33FFFFFF)),
                                  Expanded(child: TextButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _showSubtitleDelaySettings();
                                    },
                                    icon: const Icon(Icons.sync_alt_rounded, size: 17),
                                    label: const Text('Delay'),
                                    style: TextButton.styleFrom(foregroundColor: playerGoldLight),
                                  )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
      },
    ).whenComplete(_startHideTimer);
    if (_automaticSubtitleOptions.isEmpty && !_automaticSubtitleLoading) {
      _ensureAutomaticEnglishSubtitle();
    }
  }

  void _showSubtitleDownloadPanel() {
    _cancelHideTimer();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close subtitle downloads',
      barrierColor: Colors.black.withValues(alpha: 0.62),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final landscape = screen.width >= screen.height;
        final panelWidth = landscape
            ? (screen.width * 0.46).clamp(360.0, 540.0).toDouble()
            : screen.width * 0.95;
        final panelHeight = landscape ? screen.height * 0.94 : screen.height * 0.84;
        var selectedLanguage = 'all';
        var downloading = '';
        var message = _automaticSubtitleMessage ?? '';
        var subtitleRefreshStarted = false;
        return SafeArea(
          child: Align(
            alignment: landscape ? Alignment.centerRight : Alignment.bottomCenter,
            child: SizedBox(
              width: panelWidth,
              height: panelHeight,
              child: StatefulBuilder(
                builder: (sheetContext, updateSheet) {
                  if (widget.movie.isMovieBox && !subtitleRefreshStarted) {
                    subtitleRefreshStarted = true;
                    unawaited(() async {
                      if (_automaticSubtitleOptions.isEmpty &&
                          !_automaticSubtitleLoading) {
                        await _ensureAutomaticEnglishSubtitle();
                      } else {
                        for (var attempt = 0;
                            attempt < 50 && _automaticSubtitleLoading;
                            attempt++) {
                          await Future<void>.delayed(
                            const Duration(milliseconds: 100),
                          );
                        }
                      }
                      if (sheetContext.mounted) updateSheet(() {});
                    }());
                  }
                  final languages = <Map<String, String>>[
                    {'code': 'all', 'label': 'All'},
                  ];
                  final seenLanguages = <String>{'all'};
                  for (final option in _automaticSubtitleOptions) {
                    final code = (option['language'] ?? '')
                        .toString()
                        .trim()
                        .toLowerCase();
                    if (code.isEmpty || !seenLanguages.add(code)) continue;
                    languages.add({
                      'code': code,
                      'label': _subtitleLanguageName(code),
                    });
                  }
                  final results = _automaticSubtitleOptions.where((option) {
                    final code = (option['language'] ?? '').toString().toLowerCase();
                    final languageOk = selectedLanguage == 'all' || code == selectedLanguage ||
                      (selectedLanguage == 'bn' && code == 'ben') ||
                      (selectedLanguage == 'en' && code == 'eng') ||
                      (selectedLanguage == 'hi' && code == 'hin');
                    return languageOk;
                  }).toList(growable: false);

                  return Material(
                    color: Colors.transparent,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xF20A0A0A),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: playerGold.withValues(alpha: 0.48)),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 28)],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.of(sheetContext).pop(),
                                    icon: const Icon(Icons.arrow_back_rounded, color: playerWhite),
                                  ),
                                  const Expanded(child: Text('Download Subtitle', style: TextStyle(
                                    color: playerWhite, fontSize: 19, fontWeight: FontWeight.w800,
                                  ))),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  widget.movie.isMovieBox ? 'Available subtitles' : 'Available subtitle tracks',
                                  style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 42,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                scrollDirection: Axis.horizontal,
                                itemCount: languages.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 7),
                                itemBuilder: (context, index) {
                                  final item = languages[index];
                                  final active = selectedLanguage == item['code'];
                                  return ChoiceChip(
                                    label: Text(item['label']!),
                                    selected: active,
                                    showCheckmark: false,
                                    selectedColor: playerGold,
                                    backgroundColor: const Color(0xFF202020),
                                    side: BorderSide(color: active ? playerGoldLight : const Color(0x22FFFFFF)),
                                    labelStyle: TextStyle(
                                      color: active ? Colors.black : playerWhite,
                                      fontSize: 11, fontWeight: FontWeight.w700,
                                    ),
                                    onSelected: (_) => updateSheet(() => selectedLanguage = item['code']!),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_automaticSubtitleLoading) const LinearProgressIndicator(
                              minHeight: 2, color: playerGold, backgroundColor: Color(0x22FFFFFF),
                            ),
                            Expanded(
                              child: results.isEmpty
                                  ? Center(child: Padding(
                                      padding: const EdgeInsets.all(22),
                                      child: Text(
                                        _automaticSubtitleLoading ? 'Loading available subtitles…' :
                                          (message.isNotEmpty ? message : 'No subtitles are available for this title or episode.'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                                      ),
                                    ))
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(15, 8, 15, 18),
                                      itemCount: results.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0x20FFFFFF)),
                                      itemBuilder: (context, index) {
                                        final option = results[index];
                                        final code = (option['language'] ?? '').toString();
                                        final release = (option['releaseName'] ?? option['fileName'] ?? 'Subtitle release').toString();
                                        final identity = code + '_' + release;
                                        final busy = downloading == identity;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 11),
                                          child: Row(
                                            children: [
                                              Expanded(child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(release, maxLines: 3, overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(color: playerWhite, fontSize: 13, fontWeight: FontWeight.w600)),
                                                  const SizedBox(height: 4),
                                                  Text(_subtitleLanguageName(code),
                                                    style: const TextStyle(color: Color(0x88FFFFFF), fontSize: 10)),
                                                ],
                                              )),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                tooltip: 'Download and apply subtitle',
                                                onPressed: downloading.isNotEmpty ? null : () async {
                                                  updateSheet(() => downloading = identity);
                                                  await _selectAutomaticSubtitleLanguage(option);
                                                  if (mounted && !_isDisposed &&
                                                      _selectedSubtitleLanguageCode == code &&
                                                      _subtitleVisibilityEnabled &&
                                                      (_automaticSubtitleMessage ?? '').contains('track active')) {
                                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                      content: Text(_subtitleLanguageName(code) + ' subtitle downloaded and applied.'),
                                                    ));
                                                  }
                                                  if (sheetContext.mounted) updateSheet(() => downloading = '');
                                                },
                                                icon: busy ? const SizedBox(
                                                  width: 19, height: 19,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: playerGoldLight),
                                                ) : const Icon(Icons.file_download_outlined, color: playerGoldLight, size: 24),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
      },
    ).whenComplete(_startHideTimer);
  }

  Future<void> _loadApplicationBrightness() async {
    try {
      final value = await ScreenBrightness.instance.application;
      if (!mounted || _isDisposed) return;
      setState(() {
        _screenBrightness = value.clamp(0.0, 1.0).toDouble();
      });
    } catch (e) {
      debugPrint('Could not read app brightness: $e');
    }
  }

  Future<void> _changeApplicationBrightness(double value) async {
    final brightness = value.clamp(0.0, 1.0).toDouble();
    if (mounted && !_isDisposed) {
      setState(() => _screenBrightness = brightness);
    }
    try {
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(brightness);
    } catch (e) {
      debugPrint('Could not change app brightness: $e');
    }
  }

  Future<void> _resetApplicationBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (e) {
      debugPrint('Could not reset app brightness: $e');
    }
  }

  Future<void> _showQualitySelector() async {
    if (_availableQualities.isEmpty || _loadingQualities) return;
    _cancelHideTimer();

    final selected = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: playerPanel,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select video quality',
                style: TextStyle(
                  color: playerWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Changes the encoded resolution of this same movie.',
                style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableQualities.map((item) {
                  final quality = item['quality']!;
                  final active = quality == _selectedQuality;
                  final label = VideoQualityService.displayName(quality);
                  return ChoiceChip(
                    label: Text(label),
                    selected: active,
                    selectedColor: playerGold,
                    backgroundColor: playerBg,
                    labelStyle: TextStyle(
                      color: active ? Colors.black : playerWhite,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: (_) => Navigator.pop(sheetContext, item),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || _isDisposed) return;
    if (selected != null && selected['quality'] != _selectedQuality) {
      await _changeVideoQuality(selected);
    }
    _startHideTimer();
  }

  void _showSettings() {
    _cancelHideTimer();

    showModalBottomSheet(
      context: context,
      backgroundColor: playerPanel,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      builder: (context) {
        const speeds = [
          0.25,
          0.5,
          0.75,
          1.0,
          1.25,
          1.5,
          1.75,
          2.0,
        ];

        // Keep the modal slider state independent for immediate drag feedback.
        double sheetBrightness =
            _screenBrightness.clamp(0.0, 1.0).toDouble();

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 25),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Playback Settings',
                      style: TextStyle(
                        color: playerWhite,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.brightness_6_outlined, color: playerGold, size: 20),
                        const SizedBox(width: 9),
                        const Expanded(
                          child: Text(
                            'Screen Brightness',
                            style: TextStyle(color: playerWhite, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: playerBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: playerGold.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            '${(sheetBrightness * 100).round()}%',
                            style: const TextStyle(
                              color: playerGoldLight,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SliderTheme(
                      data: SliderTheme.of(sheetContext).copyWith(
                        trackHeight: 4,
                        activeTrackColor: playerGold,
                        inactiveTrackColor: Color(0x3DFFFFFF),
                        thumbColor: playerWhite,
                        overlayColor: playerGold.withValues(alpha: 0.18),
                        showValueIndicator: ShowValueIndicator.never,
                        trackShape: const RoundedRectSliderTrackShape(),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: sheetBrightness,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (value) {
                          final nextBrightness =
                              value.clamp(0.0, 1.0).toDouble();

                          // Update the thumb, active track, and percentage immediately.
                          setSheetState(() {
                            sheetBrightness = nextBrightness;
                          });

                          // Apply the selected value to the actual app brightness.
                          _changeApplicationBrightness(nextBrightness);
                        },
                      ),
                    ),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dim', style: TextStyle(color: Color(0x8AFFFFFF), fontSize: 11)),
                        Text('Bright', style: TextStyle(color: Color(0x8AFFFFFF), fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Playback Speed',
                      style: TextStyle(
                        color: playerGold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: speeds.map((speed) {
                        final selected = _speed == speed;

                        return ChoiceChip(
                          label: Text('${speed}x'),
                          selected: selected,
                          selectedColor: playerGold,
                          backgroundColor: playerBg,
                          labelStyle: TextStyle(
                            color: selected ? Colors.black : playerWhite,
                          ),
                          onSelected: (_) async {
                            await _changeSpeed(speed);

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.audiotrack,
                        color: playerGold,
                      ),
                      title: const Text(
                        'Audio language',
                        style: TextStyle(color: playerWhite),
                      ),
                      subtitle: Text(
                        _tracks.audio.isEmpty
                            ? 'No alternate audio tracks detected'
                            : _audioTrackLabel(
                                _tracks.audio[_selectedAudioTrackIndex
                                    .clamp(0, _tracks.audio.length - 1)
                                    .toInt()],
                                _selectedAudioTrackIndex
                                    .clamp(0, _tracks.audio.length - 1)
                                    .toInt(),
                              ),
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0x8AFFFFFF),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showAudioTracks();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.subtitles,
                        color: playerGold,
                      ),
                      title: const Text(
                        'Subtitles',
                        style: TextStyle(color: playerWhite),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0x8AFFFFFF),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showSubtitleTracks();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.gesture_rounded,
                        color: playerGold,
                      ),
                      title: const Text(
                        'Gesture controls',
                        style: TextStyle(color: playerWhite),
                      ),
                      subtitle: const Text(
                        'Swipe sensitivity and double-tap skip',
                        style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0x8AFFFFFF),
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _showGestureSettings();
                      },
                    ),
                  ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_startHideTimer);
  }

  void _showGestureSettings() {
    _cancelHideTimer();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: playerPanel,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.90,
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          Future<void> persist() => _saveGesturePreferences();

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gesture Controls',
                    style: TextStyle(
                      color: playerWhite,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Customize touch gestures while watching videos.',
                    style: TextStyle(color: Color(0x99FFFFFF), fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: playerGold,
                    title: const Text('Right-side volume swipe', style: TextStyle(color: playerWhite)),
                    subtitle: const Text('Swipe up or down on the right side', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                    value: _volumeGestureEnabled,
                    onChanged: (value) {
                      setState(() => _volumeGestureEnabled = value);
                      updateSheet(() {});
                      persist();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: playerGold,
                    title: const Text('Left-side brightness swipe', style: TextStyle(color: playerWhite)),
                    subtitle: const Text('Swipe up or down on the left side', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                    value: _brightnessGestureEnabled,
                    onChanged: (value) {
                      setState(() => _brightnessGestureEnabled = value);
                      updateSheet(() {});
                      persist();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: playerGold,
                    title: const Text('Double-tap to skip', style: TextStyle(color: playerWhite)),
                    subtitle: const Text('Double-tap left or right to seek', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
                    value: _doubleTapSkipEnabled,
                    onChanged: (value) {
                      setState(() => _doubleTapSkipEnabled = value);
                      updateSheet(() {});
                      persist();
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Swipe sensitivity', style: TextStyle(color: playerWhite, fontWeight: FontWeight.w700)),
                      ),
                      Text('${_gestureSensitivity.toStringAsFixed(2)}x', style: const TextStyle(color: playerGoldLight, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  Slider(
                    value: _gestureSensitivity,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    activeColor: playerGold,
                    inactiveColor: const Color(0x3DFFFFFF),
                    onChanged: (value) {
                      setState(() => _gestureSensitivity = value);
                      updateSheet(() {});
                    },
                    onChangeEnd: (_) => persist(),
                  ),
                  const SizedBox(height: 8),
                  const Text('Double-tap skip duration', style: TextStyle(color: playerWhite, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [5, 10, 15, 20, 30].map((seconds) {
                      final selected = _doubleTapSkipSeconds == seconds;
                      return ChoiceChip(
                        label: Text('${seconds}s'),
                        selected: selected,
                        selectedColor: playerGold,
                        backgroundColor: playerBg,
                        labelStyle: TextStyle(color: selected ? Colors.black : playerWhite),
                        onSelected: (_) {
                          setState(() => _doubleTapSkipSeconds = seconds);
                          updateSheet(() {});
                          persist();
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your gesture preferences are saved on this device.',
                    style: TextStyle(color: Color(0x80FFFFFF), fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(_startHideTimer);
  }

  Widget _centerControls() {
    // Keep the large center controls only in landscape/fullscreen.
    // Portrait uses double-tap for 10-second seeking and has no center buttons.
    if (!_isFullscreen) return const SizedBox.shrink();

    Widget skipControl({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.48),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x55FFFFFF)),
        ),
        child: IconButton(
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(icon, color: playerWhite, size: 25),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        skipControl(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          onPressed: () => _seekBy(-10),
        ),
        const SizedBox(width: 22),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [playerGoldLight, playerGold],
            ),
            border: Border.all(color: const Color(0xCCFFFFFF), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: playerGold.withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlay,
            iconSize: 34,
            color: playerWhite,
            icon: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: 22),
        skipControl(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          onPressed: () => _seekBy(10),
        ),
      ],
    );
  }

  Widget _bottomControls() {
    final max = _duration.inMilliseconds.toDouble();
    final compact = !_isFullscreen;

    Widget compactAction({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
      bool enabled = true,
      Color color = playerWhite,
    }) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 42, height: 38),
        padding: EdgeInsets.zero,
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          color: enabled ? color : color.withValues(alpha: 0.32),
          size: 24,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 18,
        0,
        compact ? 10 : 66,
        compact ? 6 : 18,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          gradient: null,
          borderRadius: BorderRadius.circular(compact ? 12 : 18),
          border: Border.all(color: const Color(0x2EFFFFFF)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 1 : 7,
            compact ? 8 : 12,
            compact ? 1 : 5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<Duration>(
                valueListenable: _positionNotifier,
                builder: (context, position, _) {
                  final displayPosition =
                      _isSeeking && _seekPreviewPosition != null
                          ? _seekPreviewPosition!
                          : position;
                  final current = displayPosition.inMilliseconds
                      .toDouble()
                      .clamp(0.0, max > 0 ? max : 1.0)
                      .toDouble();

                  return Row(
                    children: [
                      Text(
                        _formatDuration(displayPosition),
                        style: const TextStyle(
                          color: playerWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: compact ? 1.8 : 3,
                            activeTrackColor: playerGold,
                            inactiveTrackColor: const Color(0x55FFFFFF),
                            thumbColor: playerWhite,
                            overlayColor: playerGold.withValues(alpha: 0.14),
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: compact ? 4 : 5.5,
                            ),
                            overlayShape: RoundSliderOverlayShape(
                              overlayRadius: compact ? 8 : 10,
                            ),
                          ),
                          child: Slider(
                            value: current,
                            min: 0,
                            max: max > 0 ? max : 1,
                            onChangeStart: max > 0
                                ? (value) {
                                    _isSeeking = true;
                                    _seekPreviewPosition =
                                        Duration(milliseconds: value.round());
                                    _positionNotifier.value =
                                        _seekPreviewPosition!;
                                  }
                                : null,
                            onChanged: max > 0
                                ? (value) {
                                    _seekPreviewPosition =
                                        Duration(milliseconds: value.round());
                                    _positionNotifier.value =
                                        _seekPreviewPosition!;
                                  }
                                : null,
                            onChangeEnd: max > 0 ? _seekTo : null,
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                          color: playerWhite,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  );
                },
              ),
              Row(
                children: [
                  compactAction(
                    tooltip: _isPlaying ? 'Pause' : 'Play',
                    icon: _isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    onPressed: _togglePlay,
                  ),
                  if (_hasEpisodeNavigation) ...[
                    compactAction(
                      tooltip: 'Previous episode',
                      icon: Icons.skip_previous_rounded,
                      enabled: _canChangeEpisode(-1),
                      onPressed: () => _changeEpisodeBy(-1),
                    ),
                    compactAction(
                      tooltip: 'Next episode',
                      icon: Icons.skip_next_rounded,
                      enabled: _canChangeEpisode(1),
                      onPressed: () => _changeEpisodeBy(1),
                    ),
                  ],
                  const Spacer(),
                  if (compact)
                    compactAction(
                      tooltip: 'Picture-in-picture',
                      icon: Icons.picture_in_picture_alt_rounded,
                      color: playerGoldLight,
                      onPressed: _toggleMiniPlayer,
                    ),
                  if (!compact) ...[
                    compactAction(
                      tooltip: 'Video fit: ${_videoFitMode == 0 ? 'Crop' : _videoFitMode == 1 ? 'Full 100%' : 'Normal'}',
                      icon: Icons.aspect_ratio_rounded,
                      color: _videoFitMode == 2 ? playerWhite : playerGoldLight,
                      onPressed: () {
                        setState(() {
                          _videoFitMode = (_videoFitMode + 1) % 3;
                          _videoZoom = 1.0;
                        });
                        _startHideTimer();
                      },
                    ),
                    Tooltip(
                      message: 'Subtitles',
                      child: OutlinedButton(
                        onPressed: _showSubtitleTracks,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: playerGoldLight,
                          backgroundColor: Colors.black.withValues(alpha: 0.38),
                          side: BorderSide(
                            color: playerGold.withValues(alpha: 0.68),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(54, 38),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.closed_caption_rounded,
                              color: playerGoldLight,
                              size: 18,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'CC',
                              style: TextStyle(
                                color: playerGoldLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  compactAction(
                    tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                    icon: _isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topControls() {
    final audioIndex = _tracks.audio.isEmpty
        ? -1
        : _selectedAudioTrackIndex.clamp(0, _tracks.audio.length - 1).toInt();
    final audioLabel = audioIndex >= 0
        ? _audioTrackLabel(_tracks.audio[audioIndex], audioIndex)
        : 'Audio';
    final showEpisodeIndicator = _isFullscreen &&
        (widget.movie.mediaType == 'tv' || widget.movie.movieBoxIsSeries);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                if (_isFullscreen) {
                  _toggleFullscreen();
                } else {
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.arrow_back_rounded, color: playerWhite),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.movie.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: playerWhite,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (showEpisodeIndicator) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: playerGold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: playerGold.withValues(alpha: 0.58),
                          ),
                        ),
                        child: Text(
                          'S${_selectedSeasonNumber.toString().padLeft(2, '0')} · E${_selectedEpisodeNumber.toString().padLeft(2, '0')}',
                          maxLines: 1,
                          style: const TextStyle(
                            color: playerGoldLight,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'FLIXORA CINEMA',
                  style: TextStyle(
                    color: playerGoldLight,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.7,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: playerGoldLight,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              minimumSize: const Size(38, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: _showSettings,
            child: Text(
              '${_speed}x',
              style: const TextStyle(
                color: playerGoldLight,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          if (widget.localFilePath == null) ...[
            const SizedBox(width: 2),
            _playerTopAction(
              icon: Icons.high_quality_rounded,
              label: _loadingQualities
                  ? '...'
                  : _selectedQuality == null
                      ? 'Quality'
                      : VideoQualityService.displayName(_selectedQuality!),
              tooltip: 'Video quality',
              enabled: _availableQualities.isNotEmpty,
              onPressed: _showQualitySelector,
            ),
          ],
          if (_tracks.audio.isNotEmpty) ...[
            const SizedBox(width: 2),
            Material(
              color: Colors.black.withValues(alpha: 0.48),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Audio language: $audioLabel',
                visualDensity: VisualDensity.compact,
                onPressed: _showAudioTracks,
                icon: const Icon(
                  Icons.audiotrack_rounded,
                  color: playerGoldLight,
                  size: 20,
                ),
              ),
            ),
          ],
          if (_isFullscreen) ...[
            const SizedBox(width: 2),
            Material(
              color: Colors.black.withValues(alpha: 0.48),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: _isMiniPlayer ? 'Expand player' : 'Mini player',
                visualDensity: VisualDensity.compact,
                onPressed: _toggleMiniPlayer,
                icon: Icon(
                  _isMiniPlayer
                      ? Icons.open_in_full_rounded
                      : Icons.picture_in_picture_alt_rounded,
                  color: playerGoldLight,
                  size: 20,
                ),
              ),
            ),
          ],
          const SizedBox(width: 2),
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Playback settings',
              visualDensity: VisualDensity.compact,
              onPressed: _showSettings,
              icon: const Icon(Icons.tune_rounded, color: playerWhite, size: 21),
            ),
          ),
          Material(
            color: Colors.black.withValues(alpha: 0.48),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Lock controls',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() {
                  _isLocked = true;
                  _showControls = false;
                });
                _cancelHideTimer();
              },
              icon: const Icon(Icons.lock_outline_rounded, color: playerWhite, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerTopAction({
    required IconData icon,
    required String label,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: playerWhite,
          disabledForegroundColor: const Color(0x66FFFFFF),
          backgroundColor: Colors.black.withValues(alpha: 0.42),
          side: BorderSide(
            color: enabled
                ? playerGold.withValues(alpha: 0.68)
                : const Color(0x3DFFFFFF),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: enabled ? playerGoldLight : playerWhite,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: playerGold,
              size: 55,
            ),
            const SizedBox(height: 15),
            Text(
              _errorMessage ?? 'Playback error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: playerWhite),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: playerGold,
                foregroundColor: Colors.black,
              ),
              onPressed: widget.movie.isMovieBox
                  ? _prepareAndInitializePlayer
                  : _initializePlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBody() {
    if (widget.movie.isMovieBox && _loadingQualities && !_initialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: playerGold,
                  strokeWidth: 2.4,
                ),
              ),
              SizedBox(height: 12),
              // Keep the lightweight progress indicator without a blocking
              // "Preparing stream..." label while the source is resolving.
            ],
          ),
        ),
      );
    }

    if (widget.movie.isMovieBox && _errorMessage != null) {
      return Container(color: Colors.black, child: _playerError());
    }

    if (widget.localFilePath == null && !_validVideoUrl) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(22),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline_rounded,
                  color: playerGold, size: 48),
              SizedBox(height: 10),
              Text('No playable stream is available',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: playerWhite,
                      fontSize: 15, fontWeight: FontWeight.w800)),
              SizedBox(height: 5),
              Text('This title needs a valid video source to play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (!_initialized && widget.movie.backdropUrl.isNotEmpty)
          Positioned.fill(
            child: FlixoraCachedImage(
              imageUrl: widget.movie.backdropUrl,
              isOnline: _playerIsOnline,
              fit: BoxFit.cover,
            ),
          ),
        if (!_initialized)
          const Positioned.fill(
            child: ColoredBox(color: Color(0x55000000)),
          ),
        Positioned.fill(
          child: ClipRect(
            child: Transform.scale(
              alignment: Alignment.center,
              scale: _videoZoom,
              child: Video(
                controller: _videoController,
                // Normal is the default in portrait and fullscreen landscape.
                // Crop and Full 100% are explicit user-selected modes only.
                fit: switch (_videoFitMode) {
                  0 => BoxFit.cover,
                  1 => BoxFit.fill,
                  _ => BoxFit.contain,
                },
                controls: NoVideoControls,
                subtitleViewConfiguration: _subtitleViewConfiguration(),
              ),
            ),
          ),
        ),
        if ((_isBuffering || !_initialized) && _errorMessage == null)
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      color: playerGold,
                      strokeWidth: 2.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _initialized ? 'Buffering...' : 'Starting playback...',
                    style: const TextStyle(
                      color: Color(0xD9FFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_errorMessage != null)
          Positioned.fill(
            child: Container(
              color: Colors.black87,
              child: _playerError(),
            ),
          ),
        if (_isLocked)
          Positioned(
            left: 15,
            top: 15,
            child: IconButton(
              onPressed: () {
                setState(() {
                  _isLocked = false;
                  _showControls = true;
                });
                _startHideTimer();
              },
              icon: const Icon(
                Icons.lock,
                color: playerGold,
                size: 28,
              ),
            ),
          ),
        if (!_isLocked)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _handlePlayerGestureStart,
              onScaleUpdate: _handlePlayerGestureUpdate,
              onScaleEnd: _handlePlayerGestureEnd,
              onTap: _isMiniPlayer ? _expandMiniPlayer : _toggleControls,
              onDoubleTapDown: (details) {
                if (!_doubleTapSkipEnabled) return;
                final width = MediaQuery.of(context).size.width;
                final seconds = _doubleTapSkipSeconds;
                if (details.localPosition.dx < width / 2) {
                  _seekBy(-seconds);
                } else {
                  _seekBy(seconds);
                }
              },
              onDoubleTap: () {},
              child: const SizedBox.expand(),
            ),
          ),
        if (_showControls && !_isLocked && _errorMessage == null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _isMiniPlayer ? _expandMiniPlayer : _toggleControls,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.transparent,
                    ],
                    stops: [0, 0.28, 0.62, 1],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(top: 0, left: 0, right: 0, child: _topControls()),
                    Center(child: _centerControls()),
                    Positioned(left: 0, right: 0, bottom: 0, child: _bottomControls()),
                  ],
                ),
              ),
            ),
          ),
        if (_gestureMode != null && _gestureFeedback.isNotEmpty && !_isLocked)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: playerGold.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _gestureMode == 'brightness'
                            ? Icons.brightness_6
                            : _gestureMode == 'volume'
                                ? Icons.volume_up
                                : _gestureMode == 'zoom'
                                    ? Icons.zoom_in
                                    : (_gestureFeedback.startsWith('-')
                                        ? Icons.fast_rewind
                                        : Icons.fast_forward),
                        color: playerGold,
                        size: 25,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _gestureMode == 'seek' &&
                                _gesturePreviewPosition != null
                            ? '${_formatDuration(_gesturePreviewPosition!)}  ($_gestureFeedback)'
                            : _gestureMode == 'brightness'
                                ? 'Brightness  $_gestureFeedback'
                                : _gestureMode == 'volume'
                                    ? 'Volume  $_gestureFeedback'
                                    : 'Zoom  $_gestureFeedback',
                        style: const TextStyle(
                          color: playerWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_isBackgrounded) {
        _isBackgrounded = true;
        _wasPlayingBeforeBackground = _isPlaying;
        final nativePosition = _player.state.position;
        _backgroundResumePosition = _pendingSeekPosition ??
            (nativePosition > Duration.zero ? nativePosition : _position);
        // Flush the latest native timestamp before Android can reclaim memory.
        unawaited(_persistResumePositionNow());
      }
      _cancelHideTimer();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _isBackgrounded = false;
      if (_wasPlayingBeforeBackground) {
        _lastBackgroundResumeAt = DateTime.now();
        unawaited(_recoverPlaybackAfterBackground());
      }
    }
  }

  Future<void> _persistResumePositionNow() async {
    if (_isDisposed) return;
    try {
      final state = _player.state;
      if (state.duration > _duration) _duration = state.duration;
      final nativePosition = state.position;
      final latestPosition = _pendingSeekPosition ??
          (nativePosition > Duration.zero ? nativePosition : _position);
      if (latestPosition > Duration.zero) _updatePosition(latestPosition);
      await _saveResumePosition(latestPosition);
      await _resumeSaveQueue;
    } catch (error) {
      debugPrint('FLIXORA background resume save failed: $error');
    }
  }

  Future<void> _recoverPlaybackAfterBackground() async {
    if (!mounted || _isDisposed || _recoveringFromBackground) return;
    _recoveringFromBackground = true;

    try {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted || _isDisposed) return;

      final savedPosition = _backgroundResumePosition;
      if (!_isPlaying) {
        await _player.play();
        await Future.delayed(const Duration(milliseconds: 650));
      }

      if (!mounted || _isDisposed) return;

      // Reopen only the exact Media already held by the player, preserving
      // its existing request headers; never resolve a new MovieBox stream.
      if (!_isPlaying) {
        final playlist = _player.state.playlist;
        final medias = playlist.medias;
        final index = playlist.index;
        if (index >= 0 && index < medias.length) {
          await _player.open(medias[index], play: false);
          if (savedPosition > Duration.zero) {
            await _player.seek(savedPosition);
          }
          await _player.play();
        }
      } else if (savedPosition > Duration.zero &&
          _position + const Duration(seconds: 2) < savedPosition) {
        await _player.seek(savedPosition);
      }

      if (!mounted || _isDisposed) return;
      if (_isPlaying) {
        setState(() => _errorMessage = null);
        _startHideTimer();
      }
    } catch (error) {
      debugPrint('Background playback recovery attempt failed: $error');
    } finally {
      _recoveringFromBackground = false;
      _wasPlayingBeforeBackground = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Capture MPV's freshest timestamp before disposing the native player.
    final finalNativePosition = _player.state.position;
    if (_player.state.duration > _duration) _duration = _player.state.duration;
    final finalPosition = _pendingSeekPosition ??
        (finalNativePosition > Duration.zero ? finalNativePosition : _position);
    unawaited(_saveResumePosition(finalPosition));
    _isDisposed = true;
    if (identical(_activeMiniPlayerState.value, this)) {
      _activeMiniPlayerState.value = null;
    }
    _miniPlayerOverlayRevision.dispose();
    unawaited(PictureInPictureService.setEnabled(false));
    _gestureFeedbackTimer?.cancel();
    _seekSyncTimer?.cancel();
    _playerPointerCount = 0;
    _playerConnectionTimer?.cancel();
    _playbackErrorTimer?.cancel();
    unawaited(_resetApplicationBrightness());
    _cancelHideTimer();

    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    _tracksSubscription?.cancel();
    _activeTrackSubscription?.cancel();
    _audioDevicesSubscription?.cancel();
    _completedSubscription?.cancel();
    _positionNotifier.dispose();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    unawaited(_player.dispose());

    super.dispose();
  }

  List<Movie> get _relatedMovies {
    final candidates = widget.recommendedMovies
        .where((item) =>
            item.id != widget.movie.id &&
            item.genres.any(widget.movie.genres.contains))
        .toList();
    candidates.sort((a, b) {
      final aMatches = a.genres.where(widget.movie.genres.contains).length;
      final bMatches = b.genres.where(widget.movie.genres.contains).length;
      return bMatches.compareTo(aMatches);
    });
    return candidates.take(20).toList();
  }

  List<Movie> get _otherMovies => widget.recommendedMovies
      .where((item) => item.id != widget.movie.id)
      .toList();

  List<Movie> get _recommendedMovies {
    final relatedIds = _relatedMovies.map((movie) => movie.id).toSet();
    return _otherMovies
        .where((item) => !relatedIds.contains(item.id))
        .take(20)
        .toList();
  }

  List<Movie> _sortedMovies(Iterable<Movie> movies, int Function(Movie, Movie) compare) {
    final result = movies.toList();
    result.sort(compare);
    return result;
  }

  Widget _movieRail(String title, List<Movie> movies) {
    if (movies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: const TextStyle(
                color: playerWhite,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 188,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: movies.length,
              separatorBuilder: (_, __) => const SizedBox(width: 11),
              itemBuilder: (context, index) {
                final item = movies[index];
                return GestureDetector(
                  onTap: widget.onMovieSelected == null
                      ? null
                      : () => widget.onMovieSelected!(item),
                  child: SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                            width: 112,
                            height: 148,
                            child: item.posterUrl.isNotEmpty
                                ? FlixoraCachedImage(
                                    isOnline: _playerIsOnline,
                                    imageUrl: item.posterUrl,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: playerPanel,
                                    child: const Icon(
                                      Icons.movie,
                                      color: playerGold,
                                      size: 35,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: playerWhite,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  Widget _detailAction(IconData icon, String label, VoidCallback? onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: playerWhite,
        side: const BorderSide(color: Color(0x3DFFFFFF)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      icon: Icon(icon, color: playerGold, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  String _audioTrackLabel(AudioTrack track, int index) {
    final title = track.title?.trim() ?? '';
    final language = track.language?.trim() ?? '';

    const languageNames = <String, String>{
      'en': 'English',
      'eng': 'English',
      'english': 'English',
      'hi': 'Hindi',
      'hin': 'Hindi',
      'hindi': 'Hindi',
      'bn': 'বাংলা',
      'ben': 'বাংলা',
      'bengali': 'বাংলা',
      'bangla': 'বাংলা',
      'ta': 'Tamil',
      'tam': 'Tamil',
      'tamil': 'Tamil',
      'te': 'Telugu',
      'tel': 'Telugu',
      'telugu': 'Telugu',
      'kn': 'Kannada',
      'kan': 'Kannada',
      'kannada': 'Kannada',
      'ml': 'Malayalam',
      'mal': 'Malayalam',
      'malayalam': 'Malayalam',
      'ja': 'Japanese',
      'jpn': 'Japanese',
      'japanese': 'Japanese',
      'ko': 'Korean',
      'kor': 'Korean',
      'korean': 'Korean',
      'zh': 'Chinese',
      'zho': 'Chinese',
      'chinese': 'Chinese',
      'es': 'Spanish',
      'spa': 'Spanish',
      'spanish': 'Spanish',
      'fr': 'French',
      'fra': 'French',
      'french': 'French',
      'ar': 'Arabic',
      'ara': 'Arabic',
      'arabic': 'Arabic',
      'ur': 'Urdu',
      'urd': 'Urdu',
      'urdu': 'Urdu',
    };

    String? displayLanguage(String value) {
      final normalized = value.trim().toLowerCase().replaceAll('_', '-');
      if (normalized.isEmpty) return null;
      final firstPart = normalized.split(RegExp(r'[-\s(/]')).first;
      return languageNames[firstPart] ?? languageNames[normalized];
    }

    // Prefer actual language metadata. This handles BCP-47 values such as
    // hi-IN, bn-BD and en-US instead of showing generic "Audio 1" titles.
    final metadataLanguage = displayLanguage(language);
    if (metadataLanguage != null) return metadataLanguage;

    // Some streams put the language in the track title instead.
    final titleLanguage = displayLanguage(title);
    if (titleLanguage != null) return titleLanguage;

    final genericTitle = RegExp(
      r'^(audio|track)(\s*#?\s*\d*)?$',
      caseSensitive: false,
    );
    if (title.isNotEmpty && !genericTitle.hasMatch(title)) return title;

    final normalizedLanguage = language.toLowerCase();
    if (language.isNotEmpty &&
        !{'und', 'unknown', 'unk', 'zxx', 'null'}.contains(normalizedLanguage)) {
      return language;
    }

    return index == 0 ? 'Original / Auto' : 'Audio ${index + 1}';
  }

  Widget _playerResources() {
    final selectedIndex = _tracks.audio.isEmpty
        ? 0
        : _selectedAudioTrackIndex.clamp(0, _tracks.audio.length - 1).toInt();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: playerPanel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x3DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.language_rounded, color: playerGoldLight, size: 18),
              SizedBox(width: 7),
              Text(
                'Resources',
                style: TextStyle(
                  color: playerWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Select audio language',
            style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (_tracks.audio.isNotEmpty)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: _tracks.audio.asMap().entries.map((entry) {
                final selected = entry.key == selectedIndex;
                return ChoiceChip(
                  label: Text(_audioTrackLabel(entry.value, entry.key)),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => _selectAudioTrack(
                    entry.value,
                    closeSheet: false,
                  ),
                  selectedColor: playerGold.withValues(alpha: 0.22),
                  backgroundColor: playerBg,
                  side: BorderSide(
                    color: selected ? playerGold : const Color(0x3DFFFFFF),
                  ),
                  labelStyle: TextStyle(
                    color: selected ? playerGoldLight : playerWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            )
          else
            const Text(
              'No alternate audio languages are available.',
              style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
            ),
        ],
      ),
    );
  }

  Future<void> _showMovieInfo() async {
    _cancelHideTimer();
    final mediaType = widget.movie.mediaType == 'tv' ? 'tv' : 'movie';
    final castFuture = TmdbService.getCast(
      widget.movie.tmdbId,
      mediaType: mediaType,
    );
    final detailsFuture = _movieDetailsFuture;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: playerPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.76,
        minChildSize: 0.42,
        maxChildSize: 0.94,
        builder: (context, scrollController) => Stack(
          children: [
            SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(17, 46, 17, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: SizedBox(
                          width: 100,
                          height: 148,
                          child: widget.movie.posterUrl.isEmpty
                              ? Container(
                                  color: playerBg,
                                  child: const Icon(
                                    Icons.movie,
                                    color: playerGoldLight,
                                    size: 36,
                                  ),
                                )
                              : FlixoraCachedImage(
                                  imageUrl: widget.movie.posterUrl,
                                  isOnline: _playerIsOnline,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.movie.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: playerWhite,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              [
                                widget.movie.mediaType == 'tv' ? 'TV SERIES' : 'MOVIE',
                                if (widget.movie.year.isNotEmpty) widget.movie.year,
                              ].join('  •  '),
                              style: const TextStyle(
                                color: playerGoldLight,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            FutureBuilder<Map<String, dynamic>>(
                              future: detailsFuture,
                              builder: (context, snapshot) {
                                final data = snapshot.data;
                                if (data == null) return const SizedBox.shrink();
                                final countries = <String>[];
                                final rawCountries = data['production_countries'];
                                if (rawCountries is List) {
                                  for (final item in rawCountries.whereType<Map>()) {
                                    final name = (item['name'] ?? item['iso_3166_1'] ?? '').toString().trim();
                                    if (name.isNotEmpty && !countries.contains(name)) {
                                      countries.add(name);
                                    }
                                  }
                                }
                                if (countries.isEmpty && data['origin_country'] is List) {
                                  countries.addAll(
                                    (data['origin_country'] as List)
                                        .map((item) => item.toString())
                                        .where((item) => item.isNotEmpty),
                                  );
                                }
                                final episodeRuntimes = data['episode_run_time'];
                                final rawRuntime = data['runtime'] ??
                                    (episodeRuntimes is List && episodeRuntimes.isNotEmpty
                                        ? episodeRuntimes.first
                                        : 0);
                                final runtime = _toInt(rawRuntime);
                                final info = <String>[
                                  if (countries.isNotEmpty) 'Country: ${countries.join(', ')}',
                                  if (runtime > 0) '${runtime} min',
                                ];
                                if (info.isEmpty) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    info.join('  •  '),
                                    style: const TextStyle(
                                      color: Color(0xB3FFFFFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                            if (widget.movie.rating > 0) ...[
                              const SizedBox(height: 9),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: playerGoldLight, size: 19),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${widget.movie.rating.toStringAsFixed(1)}/10',
                                    style: const TextStyle(
                                      color: playerWhite,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'TMDB Rating',
                                    style: TextStyle(
                                      color: Color(0xB3FFFFFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (widget.movie.originCountry.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Country: ${widget.movie.originCountry}',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (widget.movie.originalLanguage.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Original language: ${widget.movie.originalLanguage.toUpperCase()}',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (widget.movie.runtime != null && widget.movie.runtime! > 0) ...[
                              const SizedBox(height: 6),
                              Text(
                                '${widget.movie.runtime!.round()} min',
                                style: const TextStyle(
                                  color: Color(0xB3FFFFFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (widget.movie.genres.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: widget.movie.genres.map((genre) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: playerBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: playerGold.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          genre,
                          style: const TextStyle(
                            color: playerGoldLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Movie Info',
                    style: TextStyle(
                      color: playerWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.movie.overview.isEmpty
                        ? 'No description available.'
                        : widget.movie.overview,
                    style: const TextStyle(
                      color: Color(0xB3FFFFFF),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (widget.movie.audioLanguages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Available Audio: ${widget.movie.audioLanguages.join(', ')}',
                      style: const TextStyle(
                        color: playerWhite,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Cast',
                    style: TextStyle(
                      color: playerWhite,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 11),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: castFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 112,
                          child: Center(
                            child: CircularProgressIndicator(color: playerGoldLight),
                          ),
                        );
                      }
                      final cast = snapshot.data ?? const <Map<String, dynamic>>[];
                      if (cast.isEmpty) {
                        return const Text(
                          'Cast photos are not available for this title.',
                          style: TextStyle(
                            color: Color(0xB3FFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      return SizedBox(
                        height: 142,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: cast.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 11),
                          itemBuilder: (context, index) {
                            final person = cast[index];
                            final profile = (person['profile_path'] ?? '').toString();
                            final name = (person['name'] ?? 'Cast member').toString();
                            final character = (person['character'] ?? '').toString();
                            return SizedBox(
                              width: 78,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 72,
                                      height: 88,
                                      child: profile.isEmpty
                                          ? Container(
                                              color: playerBg,
                                              child: const Icon(
                                                Icons.person,
                                                color: playerGoldLight,
                                                size: 34,
                                              ),
                                            )
                                          : FlixoraCachedImage(
                                              imageUrl: '${imageBase}w185$profile',
                                              isOnline: _playerIsOnline,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: playerWhite,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (character.isNotEmpty)
                                    Text(
                                      character,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xB3FFFFFF),
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Positioned(
              top: 4,
              right: 5,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: playerBg,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Close movie information',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: playerWhite,
                    size: 19,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    _startHideTimer();
  }

  void _handlePlayerPointerDown(PointerDownEvent event) {
    if (_isDisposed) return;
    _playerPointerCount++;
    if (mounted) setState(() {});
  }

  void _handlePlayerPointerEnd(PointerEvent event) {
    if (_playerPointerCount > 0) _playerPointerCount--;
    if (mounted) setState(() {});
  }

  Widget _playerPageContent() {
    final related = _relatedMovies;
    final recommended = _recommendedMovies;
    final allSuggestions = _otherMovies;
    final topRated = _sortedMovies(
      allSuggestions.where((movie) => movie.rating > 0),
      (a, b) => b.rating.compareTo(a.rating),
    ).take(20).toList();
    final latest = _sortedMovies(
      allSuggestions.where((movie) => movie.year != 'N/A'),
      (a, b) => b.year.compareTo(a.year),
    ).take(20).toList();
    final actionMovies = allSuggestions
        .where((movie) => movie.genres.any((genre) =>
            genre.toLowerCase().contains('action') ||
            genre.toLowerCase().contains('adventure')))
        .take(20).toList();
    final screenSize = MediaQuery.sizeOf(context);
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final miniWidth = (screenSize.width * 0.56)
        .clamp(180.0, 280.0)
        .toDouble();
    final miniHeight = miniWidth * 9 / 16 + 30;
    final maxMiniRight = screenSize.width - miniWidth - 8;
    final maxMiniBottom = screenSize.height - viewPadding.top -
        viewPadding.bottom - miniHeight - 8;
    final miniRight = (_miniPlayerOffset?.dx ?? 14.0)
        .clamp(8.0, maxMiniRight < 8 ? 8.0 : maxMiniRight)
        .toDouble();
    final miniBottom = (_miniPlayerOffset?.dy ?? 18.0)
        .clamp(8.0, maxMiniBottom < 8 ? 8.0 : maxMiniBottom)
        .toDouble();

    return Stack(
      children: [
        CustomScrollView(
          // A touch that starts inside the Player belongs to the Player's
          // swipe/seek/pinch controls, not the surrounding portrait page.
          physics: _playerPointerCount > 0
              ? const NeverScrollableScrollPhysics()
              : null,
          slivers: [
            SliverToBoxAdapter(
              child: _isMiniPlayer
                  ? const SizedBox(height: 8)
                  : Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: _handlePlayerPointerDown,
                      onPointerUp: _handlePlayerPointerEnd,
                      onPointerCancel: _handlePlayerPointerEnd,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _playerBody(),
                      ),
                    ),
            ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.movie.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: playerWhite,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Movie information',
                      onPressed: _showMovieInfo,
                      icon: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline_rounded, color: playerGoldLight, size: 17),
                          Icon(Icons.keyboard_arrow_down_rounded, color: playerGoldLight, size: 21),
                        ],
                      ),
                    ),
                  ],
                ),
                _playerMetadata(),
                const SizedBox(height: 16),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailAction(Icons.playlist_add, 'Add to list', widget.onSave),
                    _detailAction(
                      Icons.share_outlined,
                      'Share',
                      () => Share.share(
                        '${widget.movie.title} (${widget.movie.year}) on FLIXORA',
                      ),
                    ),
                    _detailAction(
                      Icons.download_outlined,
                      'Download',
                      widget.movie.isMovieBox && widget.movie.movieBoxIsSeries
                          ? () => widget.onDownloadEpisode?.call(
                                _selectedSeasonNumber,
                                _selectedEpisodeNumber,
                              )
                          : widget.onDownload,
                    ),
                    _detailAction(
                      Icons.video_library_outlined,
                      'View downloads',
                      widget.onViewDownloads,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _playerResources(),
                _movieBoxLanguageSelector(),
                _tvEpisodeSelector(),
                const SizedBox(height: 16),
                const Text(
                  'For You',
                  style: TextStyle(
                    color: playerWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _movieRail('Related Movies', related)),
        SliverToBoxAdapter(child: _movieRail('Recommended for You', recommended)),
        SliverToBoxAdapter(child: _movieRail('Top Rated Movies', topRated)),
        SliverToBoxAdapter(child: _movieRail('Recently Added', latest)),
        SliverToBoxAdapter(child: _movieRail('Action & Adventure', actionMovies)),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    ),
        if (_isMiniPlayer)
          Positioned(
            right: miniRight,
            bottom: miniBottom,
            child: Material(
              color: Colors.black,
              elevation: 18,
              borderRadius: BorderRadius.circular(13),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: miniWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 30,
                      color: const Color(0xFF171717),
                      padding: const EdgeInsets.only(left: 7, right: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleMiniPlayer,
                              onPanUpdate: (details) => _moveMiniPlayer(
                                details,
                                maxRight: maxMiniRight,
                                maxBottom: maxMiniBottom,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.drag_indicator_rounded,
                                    color: playerGold,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'MINI PLAYER',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: _isPlaying ? 'Pause' : 'Play',
                              onPressed: _togglePlay,
                              icon: Icon(
                                _isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 30,
                              ),
                              padding: EdgeInsets.zero,
                              tooltip: 'Expand player',
                              onPressed: _toggleMiniPlayer,
                              icon: const Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                          ),
                        ],
                      ),
                    ),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _playerBody(),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) {
          _toggleFullscreen();
        }
      },
      child: _isMiniPlayer
          ? const IgnorePointer(child: SizedBox.expand())
          : Scaffold(
              backgroundColor: playerBg,
              body: _isFullscreen
                  ? SafeArea(
                      top: false,
                      bottom: false,
                      left: false,
                      right: false,
                      child: _playerBody(),
                    )
                  : SafeArea(
                      top: true,
                      bottom: true,
                      child: _playerPageContent(),
                    ),
            ),
    );
  }
}