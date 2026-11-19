/// Safe source model and routing primitives for FLIXORA playback.
///
/// Direct media URLs are handled by the existing media_kit player.
/// Embed pages must be opened by a separate, hardened WebView and are accepted
/// only when their exact host has been explicitly approved.
/// External pages are never treated as playable media.
enum PlaybackSourceType {
  direct,
  embed,
  external,
}

class StreamingPlaybackSource {
  const StreamingPlaybackSource({
    required this.id,
    required this.displayName,
    required this.type,
    required this.url,
    this.isAdminManaged = false,
  });

  final String id;
  final String displayName;
  final PlaybackSourceType type;
  final String url;

  /// Admin-managed direct sources always outrank catalogue/provider sources.
  final bool isAdminManaged;
}

class PlaybackSourceRouter {
  PlaybackSourceRouter._();

  /// Returns a parsed HTTP(S) URI without credentials or malformed hosts.
  static Uri? safeHttpUri(
    String raw, {
    bool requireHttps = false,
    Set<String> allowedHosts = const <String>{},
  }) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && (requireHttps || scheme != 'http')) {
      return null;
    }
    if (requireHttps && scheme != 'https') return null;

    if (allowedHosts.isNotEmpty &&
        !allowedHosts.map((host) => host.toLowerCase()).contains(
              uri.host.toLowerCase(),
            )) {
      return null;
    }

    return uri;
  }

  /// Keeps only safe candidates and applies FLIXORA's source priority:
  /// 1. Admin-managed direct video
  /// 2. Other direct video
  /// 3. Approved HTTPS embed
  /// 4. Approved external webpage
  ///
  /// Embed and external hosts must be explicitly allowlisted by the caller.
  /// No provider is implicitly trusted or enabled by this class.
  static List<StreamingPlaybackSource> orderCandidates(
    Iterable<StreamingPlaybackSource> candidates, {
    Set<String> approvedEmbedHosts = const <String>{},
    Set<String> approvedExternalHosts = const <String>{},
  }) {
    final safe = <StreamingPlaybackSource>[];

    for (final source in candidates) {
      final valid = switch (source.type) {
        PlaybackSourceType.direct =>
          safeHttpUri(source.url) != null,
        PlaybackSourceType.embed =>
          approvedEmbedHosts.isNotEmpty &&
              safeHttpUri(
                    source.url,
                    requireHttps: true,
                    allowedHosts: approvedEmbedHosts,
                  ) !=
                  null,
        PlaybackSourceType.external =>
          approvedExternalHosts.isNotEmpty &&
              safeHttpUri(
                    source.url,
                    requireHttps: true,
                    allowedHosts: approvedExternalHosts,
                  ) !=
                  null,
      };

      if (valid) safe.add(source);
    }

    int priority(StreamingPlaybackSource source) {
      if (source.type == PlaybackSourceType.direct &&
          source.isAdminManaged) {
        return 0;
      }
      return switch (source.type) {
        PlaybackSourceType.direct => 1,
        PlaybackSourceType.embed => 2,
        PlaybackSourceType.external => 3,
      };
    }

    // Dart's List.sort is not guaranteed stable, so preserve original order
    // explicitly when two candidates have equal priority.
    final indexed = safe.indexed.toList();
    indexed.sort((a, b) {
      final byPriority = priority(a.$2).compareTo(priority(b.$2));
      return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
    });

    return indexed.map((entry) => entry.$2).toList(growable: false);
  }
}
