/// Filters transient decoder/player events that do not stop active playback.
class PlaybackErrorPolicy {
  PlaybackErrorPolicy._();

  /// A player error is fatal only when the player is not opening, playback is
  /// not active, and the playback position has not advanced since the event.
  static bool shouldShowError({
    required bool isOpening,
    required bool isPlaying,
    required Duration positionAtError,
    required Duration currentPosition,
  }) {
    if (isOpening || isPlaying) return false;
    return currentPosition <= positionAtError;
  }
}
