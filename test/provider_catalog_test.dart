import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/provider_catalog.dart';

void main() {
  group('ProviderCatalog.forMovie', () {
    test('builds the nine existing providers plus VidRift for a TMDB movie', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      expect(sources, hasLength(10));
      expect(sources.map((source) => source.id).toList(), [
        'play4u',
        'yapgrid',
        'pvrplay',
        'cinesrc',
        'framex',
        'streamrip',
        'filmu',
        'multiembed',
        'nexstream',
        'vidrift-movie',
      ]);
      expect(
        sources.first.url,
        'https://play4u.org/watch/tt0816692?embed=1',
      );
      expect(
        sources[1].url,
        'https://yapgrid.com/embed/movie/157336?autoplay=1',
      );
      expect(sources[2].url, contains('/watch/movie/157336'));
      expect(sources[9].url,
          'https://embed.vidrift.net/embed/movie/157336?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1');
      expect(sources.every((source) => source.isAvailable), isTrue);
      expect(sources.last.loadInIframe, isTrue);
    });

    test('keeps Play4U visible but unavailable without a valid IMDb ID', () {
      final sources = ProviderCatalog.forMovie(tmdbId: 157336);

      expect(sources, hasLength(10));
      expect(sources.first.id, 'play4u');
      expect(sources.first.isAvailable, isFalse);
      expect(sources.first.unavailableReason, isNotNull);
      expect(sources[1].isAvailable, isTrue);
    });

    test('all configured provider URLs are HTTPS and match their approved hosts', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );

      for (final source in sources) {
        final uri = Uri.parse(source.url);
        expect(uri.scheme, 'https', reason: source.id);
        expect(
          ProviderCatalog.allowsNavigation(source, uri),
          isTrue,
          reason: source.id,
        );
      }
    });

    test('does not build providers without a TMDB ID', () {
      expect(ProviderCatalog.forMovie(tmdbId: 0), isEmpty);
    });

    test('creates a NexStream URL with a dynamic demo key', () {
      final source = ProviderCatalog.forMovie(tmdbId: 157336)
          .singleWhere((item) => item.id == 'nexstream');

      expect(
        source.url,
        matches(RegExp(
          r'^https://api\.codespecters\.com/embed/movie/157336\?apikey=DEMO_[0-9a-f]{8}$',
        )),
      );
    });
  });

  group('ProviderCatalog TV and anime', () {
    test('builds a VidRift TV route with seasons and episodes', () {
      final sources = ProviderCatalog.forTv(tmdbId: 1399);

      expect(sources, hasLength(1));
      expect(sources.single.id, 'vidrift-tv');
      expect(sources.single.loadInIframe, isTrue);
      expect(
        sources.single.url,
        'https://embed.vidrift.net/embed/tv/1399/1/1?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
      );
      expect(ProviderCatalog.allowsNavigation(
        sources.single,
        Uri.parse(sources.single.url),
      ), isTrue);
    });

    test('builds the exact selected TV season and episode route', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1399,
        seasonNumber: 3,
        episodeNumber: 7,
      );

      expect(
        sources.single.url,
        'https://embed.vidrift.net/embed/tv/1399/3/7?brand=FLIXORA&brandColor=%23E50914&showTitle=1&exit=1',
      );
    });

    test('builds separate AniList Sub and Dub routes with TMDB fallback', () {
      final sources = ProviderCatalog.forTv(tmdbId: 1429, aniListId: 16498);

      expect(sources.map((source) => source.id), [
        'vidrift-anime-sub',
        'vidrift-anime-dub',
        'vidrift-tv-fallback',
      ]);
      expect(sources[0].url, contains('/embed/anilist/16498/1'));
      expect(sources[1].url, contains('&dub=1'));
      expect(sources[2].url, contains('/embed/tv/1429/1/1'));
      expect(sources.every((source) => source.loadInIframe), isTrue);
    });

    test('uses exact TMDB season and episode route for later anime seasons', () {
      final sources = ProviderCatalog.forTv(
        tmdbId: 1429,
        aniListId: 16498,
        seasonNumber: 2,
        episodeNumber: 4,
        aniListEpisodeNumber: 17,
      );

      expect(sources, hasLength(1));
      expect(sources.single.url, contains('/embed/tv/1429/2/4?'));
    });

    test('does not create TV providers without a TMDB ID', () {
      expect(ProviderCatalog.forTv(tmdbId: 0), isEmpty);
    });
  });

  group('ProviderCatalog fallback', () {
    test('tries the next available provider and skips already failed providers', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );
      final next = ProviderCatalog.nextAvailableAfter(
        sources,
        'play4u',
        excludedIds: const <String>{'yapgrid'},
      );

      expect(next?.id, 'pvrplay');
    });

    test('does not wrap around or retry a failed provider automatically', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 157336,
        imdbId: 'tt0816692',
      );
      expect(
        ProviderCatalog.nextAvailableAfter(
          sources,
          'vidrift-movie',
          excludedIds: const <String>{},
        ),
        isNull,
      );
    });
  });

  group('ProviderCatalog.allowsNavigation', () {
    final source = ProviderCatalog.forMovie(
      tmdbId: 157336,
      imdbId: 'tt0816692',
    )[0];

    test('allows HTTPS on the provider domain and its subdomains', () {
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://play4u.org/watch/tt0816692'),
        ),
        isTrue,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://cdn.play4u.org/video'),
        ),
        isTrue,
      );
    });

    test('allows the reference PVRPlay long subdomain', () {
      final pvr = ProviderCatalog.forMovie(tmdbId: 157336)[2];
      final uri = Uri.parse(pvr.url);

      expect(uri.host.endsWith('.pvrplay.fun'), isTrue);
      expect(ProviderCatalog.allowsNavigation(pvr, uri), isTrue);
    });

    test('blocks HTTP, credentials, and unrelated domains', () {
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('http://play4u.org/watch/tt0816692'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://play4u.org.evil.example/watch'),
        ),
        isFalse,
      );
      expect(
        ProviderCatalog.allowsNavigation(
          source,
          Uri.parse('https://user:pass@play4u.org/watch'),
        ),
        isFalse,
      );
    });
  });

  group('ProviderCatalog.fromAdminUrl', () {
    test('converts YouTube watch and short links to in-app embeds', () {
      final watch = ProviderCatalog.fromAdminUrl(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      final short = ProviderCatalog.fromAdminUrl(
        'https://youtu.be/dQw4w9WgXcQ',
      );

      expect(watch?.id, 'youtube');
      expect(watch?.url, contains('youtube-nocookie.com/embed/dQw4w9WgXcQ'));
      expect(short?.url, watch?.url);
    });

    test('converts Vimeo links to the Vimeo player', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://vimeo.com/123456789',
      );

      expect(source?.id, 'vimeo');
      expect(source?.url, 'https://player.vimeo.com/video/123456789');
    });

    test('converts Internet Archive detail links to the embed player', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://archive.org/details/feature_film',
      );

      expect(source?.id, 'internet-archive');
      expect(source?.url, 'https://archive.org/embed/feature_film');
    });

    test('does not pretend Dailymotion is available without a Player ID', () {
      final source = ProviderCatalog.fromAdminUrl(
        'https://www.dailymotion.com/video/x84sh87',
      );

      expect(source?.id, 'dailymotion');
      expect(source?.isAvailable, isFalse);
      expect(source?.unavailableReason, contains('Player ID'));
    });

    test('keeps Admin embed sources available without a TMDB ID', () {
      final sources = ProviderCatalog.forMovie(
        tmdbId: 0,
        adminVideoUrl: 'https://youtu.be/dQw4w9WgXcQ',
      );

      expect(sources, hasLength(1));
      expect(sources.single.id, 'youtube');
      expect(sources.single.isAvailable, isTrue);
    });

    test('rejects unrelated, malformed and unsafe embed URLs', () {
      expect(
        ProviderCatalog.fromAdminUrl('https://example.com/video/123456'),
        isNull,
      );
      expect(
        ProviderCatalog.fromAdminUrl('javascript:alert(1)'),
        isNull,
      );
      expect(
        ProviderCatalog.fromAdminUrl(
          'https://user:pass@www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        isNull,
      );
    });
  });
}
