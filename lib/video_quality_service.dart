/// Shared helpers for FLIXORA's real video-quality selection.
import 'native/rust_playback_core.dart';
///
/// A quality label is a requested/declared encode. It does not prove the
/// video's actual resolution or bitrate; those require media metadata.
class VideoQualityService {
  VideoQualityService._();

  static const List<String> supportedQualities = <String>[
    '240p',
    '360p',
    '480p',
    '720p',
    '1080p',
    '1440p',
    '2160p',
  ];

  /// Extracts a numeric vertical resolution from labels such as 1080p or 4K.
  static int rank(String label) {
    return RustPlaybackCore.qualityRank(label);
  }

  static List<T> sort<T>(
    Iterable<T> items,
    String Function(T item) labelOf,
  ) {
    final result = items.toList();
    result.sort((a, b) => rank(labelOf(a)).compareTo(rank(labelOf(b))));
    return result;
  }

  /// Returns true only when measured video height matches the selected label.
  /// A 5% tolerance allows common non-exact encodes.
  static bool matchesMeasuredHeight(String label, int measuredHeight) {
    final expected = rank(label);
    if (expected <= 0 || measuredHeight <= 0) return false;
    return (measuredHeight - expected).abs() <= expected * 0.05;
  }

  /// Friendly labels for the player quality selector.
  static String displayName(String quality) {
    switch (quality.trim().toLowerCase()) {
      case '1440p':
      case 'qhd':
      case '2k':
        return '2K';
      case '2160p':
      case 'uhd':
      case '4k':
        return '4K';
      default:
        return quality;
    }
  }
}
