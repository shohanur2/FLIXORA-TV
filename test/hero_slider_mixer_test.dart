import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/hero_slider_mixer.dart';

void main() {
  group('HeroSliderMixer', () {
    test('prioritizes Trending Movies and shows Web Series most often', () {
      final mixed = HeroSliderMixer.mix<String>(
        movies: List<String>.generate(6, (index) => 'movie-$index'),
        webSeries: List<String>.generate(6, (index) => 'series-$index'),
        dramas: List<String>.generate(3, (index) => 'drama-$index'),
        anime: List<String>.generate(3, (index) => 'anime-$index'),
        tvShows: List<String>.generate(3, (index) => 'tv-$index'),
        keyOf: (item) => item,
        limit: 10,
      );

      expect(
        mixed,
        [
          'movie-0',
          'movie-1',
          'series-0',
          'series-1',
          'movie-2',
          'series-2',
          'series-3',
          'drama-0',
          'anime-0',
          'tv-0',
        ],
      );
    });

    test('removes duplicate titles across categories and respects the limit', () {
      final mixed = HeroSliderMixer.mix<String>(
        movies: ['shared', 'movie-2', 'movie-3'],
        webSeries: ['shared', 'series-2'],
        dramas: ['drama-1'],
        anime: ['anime-1'],
        tvShows: ['tv-1'],
        keyOf: (item) => item,
        limit: 5,
      );

      expect(mixed.length, 5);
      expect(mixed.toSet().length, mixed.length);
      expect(mixed.first, 'shared');
    });

    test('continues with available sources when a category is empty', () {
      final mixed = HeroSliderMixer.mix<String>(
        movies: ['movie-1', 'movie-2'],
        webSeries: const [],
        dramas: ['drama-1'],
        anime: const [],
        tvShows: ['tv-1'],
        keyOf: (item) => item,
      );

      expect(mixed, ['movie-1', 'movie-2', 'drama-1', 'tv-1']);
    });
  });
}
