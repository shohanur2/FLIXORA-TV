/// Validation and bounded retry rules for MovieBox stream resolution.
class MovieBoxStreamPolicy {
  MovieBoxStreamPolicy._();

  static const int maxAttempts = 3;
  static const Duration retryDelay = Duration(milliseconds: 350);

  static bool hasPlayableLinks(Map<String, dynamic> response) {
    final rawLinks = response['links'];
    if (rawLinks is! List) return false;
    return rawLinks.whereType<Map>().any((link) {
      final uri = Uri.tryParse((link['url'] ?? '').toString().trim());
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty;
    });
  }
}
