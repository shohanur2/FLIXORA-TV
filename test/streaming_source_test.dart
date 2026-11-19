import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/streaming_source.dart';

void main() {
  group('PlaybackSourceRouter.safeHttpUri', () {
    test('accepts HTTP and HTTPS direct URLs', () {
      expect(
        PlaybackSourceRouter.safeHttpUri('https://cdn.example/video.mp4'),
        isNotNull,
      );
      expect(
        PlaybackSourceRouter.safeHttpUri('http://cdn.example/video.mp4'),
        isNotNull,
      );
    });

    test('rejects unsafe schemes, credentials and malformed URLs', () {
      expect(
        PlaybackSourceRouter.safeHttpUri('javascript:alert(1)'),
        isNull,
      );
      expect(
        PlaybackSourceRouter.safeHttpUri('https://user:pass@cdn.example/a.mp4'),
        isNull,
      );
      expect(PlaybackSourceRouter.safeHttpUri('not a url'), isNull);
    });

    test('requires HTTPS and an exact approved host for embeds', () {
      expect(
        PlaybackSourceRouter.safeHttpUri(
          'https://player.example/embed/123',
          requireHttps: true,
          allowedHosts: {'player.example'},
        ),
        isNotNull,
      );
      expect(
        PlaybackSourceRouter.safeHttpUri(
          'http://player.example/embed/123',
          requireHttps: true,
          allowedHosts: {'player.example'},
        ),
        isNull,
      );
      expect(
        PlaybackSourceRouter.safeHttpUri(
          'https://evil-player.example/embed/123',
          requireHttps: true,
          allowedHosts: {'player.example'},
        ),
        isNull,
      );
    });
  });

  group('PlaybackSourceRouter.orderCandidates', () {
    const admin = StreamingPlaybackSource(
      id: 'admin-720p',
      displayName: 'Admin 720p',
      type: PlaybackSourceType.direct,
      url: 'https://storage.example/movie-720p.mp4',
      isAdminManaged: true,
    );
    const legacy = StreamingPlaybackSource(
      id: 'legacy',
      displayName: 'Legacy direct',
      type: PlaybackSourceType.direct,
      url: 'https://cdn.example/movie.mp4',
    );
    const embed = StreamingPlaybackSource(
      id: 'approved-embed',
      displayName: 'Approved Embed',
      type: PlaybackSourceType.embed,
      url: 'https://player.example/embed/123',
    );
    const external = StreamingPlaybackSource(
      id: 'external-page',
      displayName: 'External page',
      type: PlaybackSourceType.external,
      url: 'https://catalog.example/title/123',
    );

    test('keeps Admin direct source first and orders fallback types safely', () {
      final result = PlaybackSourceRouter.orderCandidates(
        [embed, external, legacy, admin],
        approvedEmbedHosts: {'player.example'},
        approvedExternalHosts: {'catalog.example'},
      );

      expect(
        result.map((source) => source.id).toList(),
        ['admin-720p', 'legacy', 'approved-embed', 'external-page'],
      );
    });

    test('does not enable embeds or external pages without explicit approval', () {
      final result = PlaybackSourceRouter.orderCandidates(
        [admin, embed, external],
      );

      expect(result.map((source) => source.id).toList(), ['admin-720p']);
    });

    test('rejects an embed URL whose host is not approved', () {
      final result = PlaybackSourceRouter.orderCandidates(
        [embed],
        approvedEmbedHosts: {'another-player.example'},
      );

      expect(result, isEmpty);
    });
  });
}
