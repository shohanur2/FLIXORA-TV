/// Provider URL definitions ported from FLIXORA-REFERENCE.
///
/// Admin-managed direct MP4/HLS sources remain FLIXORA's first playback choice.
class ProviderEmbedSource {
  const ProviderEmbedSource({
    required this.id,
    required this.name,
    required this.url,
    required this.allowedHosts,
    this.unavailableReason,
    this.loadInIframe = false,
  });

  final String id;
  final String name;
  final String url;
  final Set<String> allowedHosts;
  final String? unavailableReason;
  final bool loadInIframe;

  bool get isAvailable => url.isNotEmpty;
}

class ProviderCatalog {
  ProviderCatalog._();

  static const String _pvrPlayHost =
      'dbhnmkjasgbvsdkjbskkvnskjbfckldsnckjbckjnxkjcsknxjvkjxnvcxknvku.pvrplay.fun';

  /// Configure this through the DAILYMOTION_PLAYER_ID GitHub Actions secret.
  static const String _dailymotionPlayerId =
      String.fromEnvironment('DAILYMOTION_PLAYER_ID');

  // Redirect destinations approved by FLIXORA-REFERENCE's playback security
  // registry. Main-frame redirects stay on this explicit HTTPS allowlist.
  static const Set<String> _approvedRedirectHosts = <String>{
    'play4u.org',
    'yapgrid.com',
    'pvrplay.fun',
    'reelsdownload.online',
    'cinesrc.st',
    'framextv.xyz',
    'framextv.cc',
    'streamrip.fun',
    'filmu.in',
    'multiembed.mov',
    'codespecters.com',
    'youtube.com',
    'youtube-nocookie.com',
    'youtu.be',
    'vimeo.com',
    'archive.org',
    'embed.vidrift.net',
    'embed.vidrift.in',
    'geo.dailymotion.com',
    'dailymotion.com',
    'dai.ly',
  };

  /// Converts an Admin-provided Dailymotion URL into the current Player-ID
  /// based embed URL. Dailymotion requires a valid Player ID for playback.
  static ProviderEmbedSource? fromDailymotionUrl(
    String rawUrl, {
    String? playerId,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final isDailymotionHost = host == 'dai.ly' ||
        host == 'dailymotion.com' ||
        host.endsWith('.dailymotion.com');
    if (!isDailymotionHost) return null;

    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    String? videoId;
    String? playlistId;
    String? embeddedPlayerId;

    if (host == 'dai.ly') {
      if (segments.isNotEmpty) videoId = segments.first;
    } else if (segments.length >= 3 &&
        segments[0] == 'embed' &&
        segments[1] == 'video') {
      videoId = segments[2];
    } else if (segments.length >= 2 && segments[0] == 'video') {
      videoId = segments[1];
    } else if (segments.length >= 3 &&
        segments[0] == 'embed' &&
        segments[1] == 'playlist') {
      playlistId = segments[2];
    } else if (segments.length >= 2 && segments[0] == 'playlist') {
      playlistId = segments[1];
    } else if (segments.length >= 2 && segments[0] == 'player') {
      final playerSegment = segments[1];
      embeddedPlayerId = playerSegment.endsWith('.html')
          ? playerSegment.substring(0, playerSegment.length - 5)
          : playerSegment;
      videoId = uri.queryParameters['video'];
      playlistId = uri.queryParameters['playlist'];
    }

    final validContentId = RegExp(r'^[A-Za-z0-9]{3,64}$');
    if ((videoId == null || !validContentId.hasMatch(videoId)) &&
        (playlistId == null || !validContentId.hasMatch(playlistId))) {
      return null;
    }

    final configuredPlayerId = (playerId ?? _dailymotionPlayerId).trim();
    final effectivePlayerId = configuredPlayerId.isNotEmpty
        ? configuredPlayerId
        : (embeddedPlayerId ?? '').trim();
    final hasPlayerId = RegExp(r'^[A-Za-z0-9]{3,64}$')
        .hasMatch(effectivePlayerId);
    final embedUrl = hasPlayerId
        ? Uri.https(
            'geo.dailymotion.com',
            '/player/$effectivePlayerId.html',
            videoId != null
                ? <String, String>{'video': videoId}
                : <String, String>{'playlist': playlistId!},
          ).toString()
        : '';

    return ProviderEmbedSource(
      id: 'dailymotion',
      name: 'Dailymotion',
      url: embedUrl,
      allowedHosts: const <String>{
        'geo.dailymotion.com',
        'dailymotion.com',
        'dai.ly',
      },
      unavailableReason: hasPlayerId
          ? null
          : 'A Dailymotion Player ID is required. Add DAILYMOTION_PLAYER_ID to GitHub Actions secrets.',
    );
  }

  /// Converts supported Admin video-page URLs into official embeddable players.
  /// Direct MP4/HLS links are intentionally left to media_kit.
  static ProviderEmbedSource? fromAdminUrl(
    String rawUrl, {
    String? dailymotionPlayerId,
  }) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();

    final dailymotion = fromDailymotionUrl(
      rawUrl,
      playerId: dailymotionPlayerId,
    );
    if (dailymotion != null) return dailymotion;

    final isYouTube = host == 'youtu.be' ||
        host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    if (isYouTube) {
      String? videoId;
      if (host == 'youtu.be') {
        if (segments.isNotEmpty) videoId = segments.first;
      } else if (segments.isNotEmpty && segments.first == 'watch') {
        videoId = uri.queryParameters['v'];
      } else if (segments.length >= 2 &&
          const <String>{'embed', 'shorts', 'live', 'v'}.contains(segments.first)) {
        videoId = segments[1];
      }
      if (videoId != null &&
          RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(videoId)) {
        return ProviderEmbedSource(
          id: 'youtube',
          name: 'YouTube',
          url: Uri.https(
            'www.youtube-nocookie.com',
            '/embed/$videoId',
            const <String, String>{'playsinline': '1'},
          ).toString(),
          allowedHosts: const <String>{
            'youtube.com',
            'youtube-nocookie.com',
            'youtu.be',
          },
        );
      }
      return null;
    }

    final isVimeo = host == 'vimeo.com' ||
        host.endsWith('.vimeo.com');
    if (isVimeo) {
      final videoId = segments.reversed
          .firstWhere(
            (part) => RegExp(r'^\d{5,12}$').hasMatch(part),
            orElse: () => '',
          );
      if (videoId.isNotEmpty) {
        return ProviderEmbedSource(
          id: 'vimeo',
          name: 'Vimeo',
          url: 'https://player.vimeo.com/video/$videoId',
          allowedHosts: const <String>{'vimeo.com'},
        );
      }
      return null;
    }

    final isArchive = host == 'archive.org' || host.endsWith('.archive.org');
    if (isArchive &&
        segments.length >= 2 &&
        const <String>{'details', 'embed'}.contains(segments.first)) {
      final identifier = segments[1];
      if (RegExp(r'^[A-Za-z0-9._-]{2,120}$').hasMatch(identifier)) {
        return ProviderEmbedSource(
          id: 'internet-archive',
          name: 'Internet Archive',
          url: 'https://archive.org/embed/${Uri.encodeComponent(identifier)}',
          allowedHosts: const <String>{'archive.org'},
        );
      }
    }

    return null;
  }

  /// Returns the built-in movie providers. Dailymotion is included only when
  /// the Admin source URL points to a Dailymotion video or playlist.
  /// Play4U requires the movie's real IMDb title ID; the others use TMDB ID.
  static List<ProviderEmbedSource> forMovie({
    required int tmdbId,
    String? imdbId,
    String? dailymotionUrl,
    String? dailymotionPlayerId,
    String? adminVideoUrl,
  }) {
    final adminSource = fromAdminUrl(
      adminVideoUrl ?? dailymotionUrl ?? '',
      dailymotionPlayerId: dailymotionPlayerId,
    );
    if (tmdbId <= 0) {
      return adminSource == null
          ? const <ProviderEmbedSource>[]
          : <ProviderEmbedSource>[adminSource];
    }

    final id = tmdbId.toString();
    final cleanImdbId = (imdbId ?? '').trim();
    final hasImdbId = RegExp(r'^tt\d+$', caseSensitive: false)
        .hasMatch(cleanImdbId);
    final nexStreamKey = _dynamicNexStreamDemoKey();

    return <ProviderEmbedSource>[
      if (adminSource != null) adminSource,
      ProviderEmbedSource(
        id: 'play4u',
        name: 'STREAM 1 · Play4U',
        url: hasImdbId
            ? 'https://play4u.org/watch/$cleanImdbId?embed=1'
            : '',
        allowedHosts: const <String>{'play4u.org'},
        unavailableReason:
            hasImdbId ? null : 'IMDb ID is not available for this movie.',
      ),
      ProviderEmbedSource(
        id: 'yapgrid',
        name: 'STREAM 2 · YapGrid',
        url: 'https://yapgrid.com/embed/movie/$id?autoplay=1',
        allowedHosts: const <String>{'yapgrid.com'},
      ),
      ProviderEmbedSource(
        id: 'pvrplay',
        name: 'STREAM 3 · PVRPlay',
        url: 'https://$_pvrPlayHost/watch/movie/$id',
        allowedHosts: const <String>{'pvrplay.fun'},
      ),
      ProviderEmbedSource(
        id: 'cinesrc',
        name: 'STREAM 4 · CineSRC',
        url: 'https://cinesrc.st/embed/movie/$id',
        allowedHosts: const <String>{'cinesrc.st'},
      ),
      ProviderEmbedSource(
        id: 'framex',
        name: 'STREAM 5 · Frame X',
        url: 'https://framextv.xyz/embed/$id',
        allowedHosts: const <String>{'framextv.xyz', 'framextv.cc'},
      ),
      ProviderEmbedSource(
        id: 'streamrip',
        name: 'STREAM 6 · Stream Rip',
        url: 'https://streamrip.fun/play?type=movie&id=$id',
        allowedHosts: const <String>{'streamrip.fun'},
      ),
      ProviderEmbedSource(
        id: 'filmu',
        name: 'STREAM 7 · FilmU',
        url: 'https://embed.filmu.in/movie/$id',
        allowedHosts: const <String>{'filmu.in'},
      ),
      ProviderEmbedSource(
        id: 'multiembed',
        name: 'STREAM 8 · Multiembed',
        url: 'https://multiembed.mov/?video_id=$id&tmdb=1',
        allowedHosts: const <String>{'multiembed.mov'},
      ),
      ProviderEmbedSource(
        id: 'nexstream',
        name: 'STREAM 9 · NexStream',
        url: 'https://api.codespecters.com/embed/movie/$id?apikey=$nexStreamKey',
        allowedHosts: const <String>{'codespecters.com'},
      ),
      ProviderEmbedSource(
        id: 'vidrift-movie',
        name: 'STREAM 10 · VidRift',
        url: 'https://embed.vidrift.net/embed/movie/$id?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
        allowedHosts: const <String>{
          'embed.vidrift.net',
          'embed.vidrift.in',
        },
        loadInIframe: true,
      ),
    ];
  }

  /// Builds the selected TMDB season/episode route. Anime Sub/Dub uses the
  /// absolute episode index expected by the AniList embed; the TMDB route stays
  /// available as a fallback for the exact selected season and episode.
  static List<ProviderEmbedSource> forTv({
    required int tmdbId,
    int? aniListId,
    int seasonNumber = 1,
    int episodeNumber = 1,
    int? aniListEpisodeNumber,
    String? adminVideoUrl,
    String? dailymotionPlayerId,
  }) {
    final adminSource = fromAdminUrl(
      adminVideoUrl ?? '',
      dailymotionPlayerId: dailymotionPlayerId,
    );
    if (tmdbId <= 0) {
      return adminSource == null
          ? const <ProviderEmbedSource>[]
          : <ProviderEmbedSource>[adminSource];
    }

    final season = seasonNumber > 0 ? seasonNumber : 1;
    final episode = episodeNumber > 0 ? episodeNumber : 1;
    final animeEpisode = (aniListEpisodeNumber ?? episode) > 0
        ? (aniListEpisodeNumber ?? episode)
        : episode;
    const hosts = <String>{
      'embed.vidrift.net',
      'embed.vidrift.in',
    };
    const brand = '?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1';

    // AniList often represents each anime season as a separate entry.
    // Use its episode route only for season one; later seasons must keep the
    // exact TMDB season/episode path instead of guessing an AniList offset.
    if (aniListId != null && aniListId > 0 && season == 1) {
      return <ProviderEmbedSource>[
        if (adminSource != null) adminSource,
        ProviderEmbedSource(
          id: 'vidrift-anime-sub',
          name: 'VidRift Anime · Sub',
          url: 'https://embed.vidrift.net/embed/anilist/$aniListId/$animeEpisode$brand',
          allowedHosts: hosts,
          loadInIframe: true,
        ),
        ProviderEmbedSource(
          id: 'vidrift-anime-dub',
          name: 'VidRift Anime · Dub',
          url: 'https://embed.vidrift.net/embed/anilist/$aniListId/$animeEpisode$brand&dub=1',
          allowedHosts: hosts,
          loadInIframe: true,
        ),
        ProviderEmbedSource(
          id: 'vidrift-tv-fallback',
          name: 'VidRift TV · TMDB fallback',
          url: 'https://embed.vidrift.net/embed/tv/$tmdbId/$season/$episode$brand',
          allowedHosts: hosts,
          loadInIframe: true,
        ),
      ];
    }

    return <ProviderEmbedSource>[
      if (adminSource != null) adminSource,
      ProviderEmbedSource(
        id: 'vidrift-tv',
        name: 'VidRift TV · Seasons & Episodes',
        url: 'https://embed.vidrift.net/embed/tv/$tmdbId/$season/$episode$brand',
        allowedHosts: hosts,
        loadInIframe: true,
      ),
    ];
  }

  /// Mirrors the reference project's five-minute NexStream demo-key window.
  /// A provider-issued production API key can replace this if required.
  static String _dynamicNexStreamDemoKey() {
    final timeWindow =
        DateTime.now().millisecondsSinceEpoch ~/ 300000;
    final value = 'NEXSTREAM$timeWindow';
    var hash = 0;

    for (final unit in value.codeUnits) {
      hash = ((hash << 5) - hash + unit) & 0xffffffff;
    }

    if (hash >= 0x80000000) hash -= 0x100000000;
    final hex = hash.abs().toRadixString(16).padRight(8, '0');
    return 'DEMO_$hex';
  }

  /// Returns the next available provider after a failed source. The order is
  /// deterministic and never loops back to a provider that already failed.
  static ProviderEmbedSource? nextAvailableAfter(
    Iterable<ProviderEmbedSource> sources,
    String failedSourceId, {
    Set<String> excludedIds = const <String>{},
  }) {
    final items = sources.toList(growable: false);
    final failedIndex = items.indexWhere((item) => item.id == failedSourceId);
    if (failedIndex < 0) return null;

    for (var index = failedIndex + 1; index < items.length; index++) {
      final candidate = items[index];
      if (candidate.isAvailable && !excludedIds.contains(candidate.id)) {
        return candidate;
      }
    }
    return null;
  }

  /// Only HTTPS navigation on the provider's own domain (or its subdomains)
  /// is allowed inside the embedded player.
  static bool allowsNavigation(
    ProviderEmbedSource source,
    Uri uri,
  ) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final approvedHosts = <String>{
      ...source.allowedHosts,
      ..._approvedRedirectHosts,
    };
    return approvedHosts.any((allowed) {
      final domain = allowed.toLowerCase();
      return host == domain || host.endsWith('.$domain');
    });
  }
}
