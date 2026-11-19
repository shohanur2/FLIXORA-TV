import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/tmdb_media_type.dart';

void main() {
  group('TmdbMediaType.isTvEndpoint', () {
    test('recognizes trending TV endpoints', () {
      expect(TmdbMediaType.isTvEndpoint('trending/tv/week'), isTrue);
      expect(TmdbMediaType.isTvEndpoint('trending/tv/day'), isTrue);
    });

    test('recognizes TV and TV discovery endpoints', () {
      expect(TmdbMediaType.isTvEndpoint('tv/popular'), isTrue);
      expect(TmdbMediaType.isTvEndpoint('discover/tv'), isTrue);
    });

    test('does not classify movie endpoints as TV', () {
      expect(TmdbMediaType.isTvEndpoint('trending/movie/week'), isFalse);
      expect(TmdbMediaType.isTvEndpoint('movie/popular'), isFalse);
      expect(TmdbMediaType.isTvEndpoint('discover/movie'), isFalse);
    });

    test('normalizes whitespace and case', () {
      expect(TmdbMediaType.isTvEndpoint('  TRENDING/TV/WEEK '), isTrue);
    });
  });
}
