/// Helpers for identifying TMDB catalogue endpoint media types.
class TmdbMediaType {
  TmdbMediaType._();

  static bool isTvEndpoint(String endpoint) {
    final normalized = endpoint.trim().toLowerCase();
    return normalized.startsWith('tv/') ||
        normalized.startsWith('discover/tv') ||
        normalized.startsWith('trending/tv/');
  }
}
