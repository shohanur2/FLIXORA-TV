import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/moviebox_stream_policy.dart';

void main() {
  group('MovieBoxStreamPolicy', () {
    test('accepts a valid HTTPS stream URL', () {
      expect(
        MovieBoxStreamPolicy.hasPlayableLinks({
          'links': [
            {'url': 'https://cdn.example.test/video.m3u8'},
          ],
        }),
        isTrue,
      );
    });

    test('rejects missing, malformed and non-network stream URLs', () {
      expect(MovieBoxStreamPolicy.hasPlayableLinks({}), isFalse);
      expect(
        MovieBoxStreamPolicy.hasPlayableLinks({
          'links': [
            {'url': ''},
            {'url': 'file:///storage/video.mp4'},
            {'url': 'https://'},
          ],
        }),
        isFalse,
      );
    });

    test('uses one bounded retry for transient resolution failures', () {
      expect(MovieBoxStreamPolicy.maxAttempts, 3);
      expect(MovieBoxStreamPolicy.retryDelay.inMilliseconds, 350);
    });
  });
}
