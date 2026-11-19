import 'package:flutter_test/flutter_test.dart';

import '../lib/streaming/trending_movie_eligibility.dart';

void main() {
  group('TrendingMovieEligibility', () {
    test('recognizes explicit Hindi audio variants, not subtitles', () {
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'Original · 1080p',
          'Hindi Dub · 720p',
        ]),
        isTrue,
      );
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'English · 1080p',
          'Hindi Subtitles',
        ]),
        isFalse,
      );
      expect(
        TrendingMovieEligibility.hasHindiAudioVariant([
          'English · 1080p',
          'Original',
        ]),
        isFalse,
      );
    });

    test('classifies Bollywood from Hindi language or regional catalogue', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'hi',
          originCountry: '',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Bollywood',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'hi',
          originCountry: 'India',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Bollywood',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ta',
          originCountry: 'India',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'South Indian',
      );
    });

    test('classifies Hollywood from the US catalogue or country metadata', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'en',
          originCountry: '',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: true,
        ),
        'Hollywood',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'en',
          originCountry: 'United States',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Hollywood',
      );
    });

    test('keeps other international titles in the broad Trending feed', () {
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ru',
          originCountry: 'Russia',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'International',
      );
    });

    test('classifies South Indian, Bengali, Korean and other Asian cinema separately', () {
      for (final language in ['ta', 'te', 'ml', 'kn']) {
        expect(
          TrendingMovieEligibility.category(
            originalLanguage: language,
            originCountry: 'India',
            inBollywoodCatalogue: false,
            inHollywoodCatalogue: false,
          ),
          'South Indian',
        );
      }
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'bn',
          originCountry: 'Bangladesh',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Bengali',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ko',
          originCountry: 'South Korea',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Korean',
      );
      expect(
        TrendingMovieEligibility.category(
          originalLanguage: 'ja',
          originCountry: 'Japan',
          inBollywoodCatalogue: false,
          inHollywoodCatalogue: false,
        ),
        'Asian',
      );
    });

    test('keeps recent releases and rejects old or future titles', () {
      final now = DateTime(2026, 11, 12);
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2025-06-01',
          year: '2025',
          now: now,
        ),
        isTrue,
      );
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2023-01-01',
          year: '2023',
          now: now,
        ),
        isFalse,
      );
      expect(
        TrendingMovieEligibility.isRecentRelease(
          releaseDate: '2027-01-01',
          year: '2027',
          now: now,
        ),
        isFalse,
      );
    });
  });
}
