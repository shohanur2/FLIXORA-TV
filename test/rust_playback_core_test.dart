import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/native/rust_playback_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RustPlaybackCore fallback', () {
    test('detects common media formats', () {
      expect(
        RustPlaybackCore.detectStreamKind(
          'https://cdn.example/video/movie.mp4?token=abc',
        ),
        3,
      );
      expect(
        RustPlaybackCore.detectStreamKind(
          'https://cdn.example/video/master.m3u8',
        ),
        1,
      );
      expect(
        RustPlaybackCore.detectStreamKind(
          'https://cdn.example/video/manifest.mpd',
        ),
        2,
      );
    });

    test('ranks quality labels', () {
      expect(RustPlaybackCore.qualityRank('1080p'), 1080);
      expect(RustPlaybackCore.qualityRank('4K'), 2160);
    });

    test('validates HTTP URLs', () {
      expect(
        RustPlaybackCore.isValidHttpUrl('https://cdn.example/movie.mp4'),
        isTrue,
      );
      expect(
        RustPlaybackCore.isValidHttpUrl('file:///movie.mp4'),
        isFalse,
      );
      expect(
        RustPlaybackCore.isValidHttpUrl(
          'https://user:pass@cdn.example/movie.mp4',
        ),
        isFalse,
      );
    });
  });
}
