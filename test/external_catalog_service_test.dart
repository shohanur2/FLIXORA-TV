import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/external_catalog_service.dart';

void main() {
  group('External catalogue response parsing', () {
    test('parses OMDb title ratings and ignores N/A values', () {
      final metadata = OmdbMetadata.fromJson({
        'imdbRating': '8.4',
        'Metascore': 'N/A',
        'Rated': 'PG-13',
        'Runtime': '148 min',
        'Awards': '2 wins',
        'imdbVotes': '1,234,567',
        'BoxOffice': 'USD 100,000,000',
        'Country': 'United States',
        'Language': 'English',
      });

      expect(metadata.imdbRating, '8.4');
      expect(metadata.metascore, isEmpty);
      expect(metadata.rated, 'PG-13');
      expect(metadata.hasContent, isTrue);
    });

    test('parses Watchmode availability rows without inventing links', () {
      final source = WatchmodeSource.fromJson({
        'name': 'Example Streaming',
        'type': 'sub',
        'region': 'BD',
        'format': 'HD',
        'price': '',
        'web_url': 'https://example.com/title',
      });

      expect(source.name, 'Example Streaming');
      expect(source.region, 'BD');
      expect(source.webUrl, 'https://example.com/title');
    });

    test('parses TasteDive recommendations', () {
      final suggestion = TasteDiveSuggestion.fromJson({
        'Name': 'Example Series',
        'Type': 'show',
        'wTeaser': 'A short description',
      });

      expect(suggestion.name, 'Example Series');
      expect(suggestion.type, 'show');
      expect(suggestion.description, 'A short description');
    });

    test('external data is empty when all providers return no data', () {
      const data = ExternalCatalogData();
      expect(data.isEmpty, isTrue);
    });

    test('Trakt title info is optional and requires real response values', () {
      const empty = TraktTitleInfo(
        rating: null,
        votes: null,
        rank: null,
        traktUrl: '',
      );
      const filled = TraktTitleInfo(
        rating: 8.1,
        votes: 500,
        rank: 12,
        traktUrl: 'https://trakt.tv/movies/123',
      );

      expect(empty.hasContent, isFalse);
      expect(filled.hasContent, isTrue);
    });
  });
}
