import 'dart:convert';

import 'package:http/http.dart' as http;

/// Resolves an exact AniList title match for TMDB-identified anime series.
/// A null result is intentionally non-fatal: FLIXORA then uses the TMDB TV
/// embed route instead of guessing an AniList ID.
class AniListService {
  AniListService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const String _query = r'''
query ($search: String) {
  Page(page: 1, perPage: 10) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      title {
        romaji
        english
        native
      }
      startDate {
        year
      }
    }
  }
}
''';

  static Future<int?> findMatchingAnimeId({
    required String title,
    String year = '',
  }) async {
    final cleanTitle = title.trim();
    final normalizedQuery = _normalizeTitle(cleanTitle);
    if (normalizedQuery.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'query': _query,
              'variables': <String, dynamic>{'search': cleanTitle},
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['data'] is! Map) return null;
      final page = (payload['data'] as Map)['Page'];
      if (page is! Map || page['media'] is! List) return null;

      final exactMatches = <Map<String, dynamic>>[];
      for (final raw in page['media'] as List) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final rawTitles = item['title'];
        if (rawTitles is! Map) continue;
        final titleMatches = <String>[
          (rawTitles['romaji'] ?? '').toString(),
          (rawTitles['english'] ?? '').toString(),
          (rawTitles['native'] ?? '').toString(),
        ].any((candidate) =>
            candidate.trim().isNotEmpty &&
            _normalizeTitle(candidate) == normalizedQuery);
        if (titleMatches && int.tryParse('${item['id']}') != null) {
          exactMatches.add(item);
        }
      }

      if (exactMatches.isEmpty) return null;
      final requestedYear = int.tryParse(year);
      if (requestedYear != null) {
        exactMatches.sort((a, b) {
          final aDate = a['startDate'];
          final bDate = b['startDate'];
          final aYear = aDate is Map ? int.tryParse('${aDate['year']}') : null;
          final bYear = bDate is Map ? int.tryParse('${bDate['year']}') : null;
          final aDistance = aYear == null ? 9999 : (aYear - requestedYear).abs();
          final bDistance = bYear == null ? 9999 : (bYear - requestedYear).abs();
          return aDistance.compareTo(bDistance);
        });
      }

      return int.tryParse('${exactMatches.first['id']}');
    } catch (_) {
      return null;
    }
  }

  static String _normalizeTitle(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
