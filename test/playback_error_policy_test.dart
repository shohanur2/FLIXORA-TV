import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/player/playback_error_policy.dart';

void main() {
  group('PlaybackErrorPolicy', () {
    test('does not show an error while playback is active', () {
      expect(
        PlaybackErrorPolicy.shouldShowError(
          isOpening: false,
          isPlaying: true,
          positionAtError: Duration.zero,
          currentPosition: const Duration(seconds: 4),
        ),
        isFalse,
      );
    });

    test('does not show an error when playback position advances', () {
      expect(
        PlaybackErrorPolicy.shouldShowError(
          isOpening: false,
          isPlaying: false,
          positionAtError: const Duration(seconds: 8),
          currentPosition: const Duration(seconds: 9),
        ),
        isFalse,
      );
    });

    test('shows an error when playback is stopped without progress', () {
      expect(
        PlaybackErrorPolicy.shouldShowError(
          isOpening: false,
          isPlaying: false,
          positionAtError: const Duration(seconds: 8),
          currentPosition: const Duration(seconds: 8),
        ),
        isTrue,
      );
    });

    test('waits until an opening operation has finished', () {
      expect(
        PlaybackErrorPolicy.shouldShowError(
          isOpening: true,
          isPlaying: false,
          positionAtError: Duration.zero,
          currentPosition: Duration.zero,
        ),
        isFalse,
      );
    });
  });
}
