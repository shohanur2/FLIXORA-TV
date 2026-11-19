import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  test('MovieBox Hot Shorts episode lists preserve season and part numbers', () {
    final episodes = MovieBoxShortEpisode.fromSeasons([
      {'se': 2, 'episodes': [2, 1, 2]},
      {'se': 1, 'episodes': [1, 3]},
    ]);

    expect(
      episodes.map((episode) => episode.label).toList(),
      ['S1 · E1', 'S1 · E3', 'S2 · E1', 'S2 · E2'],
    );
  });

  test('Short TV subject types 3 and 7 are treated as series', () {
    for (final subjectType in [3, 7]) {
      final movie = Movie.fromMovieBox({
        'id': 'short-series-$subjectType',
        'title': 'Example Short Series',
        'subjectType': subjectType,
        'cover': 'https://cdn.example.test/short.jpg',
      });

      expect(movie.movieBoxIsSeries, isTrue);
      expect(movie.mediaType, 'tv');
      expect(movie.movieBoxSubjectType, subjectType);
    }
  });

  test('Hot Shorts parser accepts alternate season and object episode keys', () {
    final episodes = MovieBoxShortEpisode.fromSeasons([
      {
        'seasonNumber': 2,
        'episodes': [
          {'ep': 2},
          {'episodeNumber': 1},
          2,
        ],
      },
      {
        'season': 1,
        'episodeList': [
          {'episode': 3},
          1,
        ],
      },
    ]);

    expect(
      episodes.map((episode) => episode.label).toList(),
      ['S1 · E1', 'S1 · E3', 'S2 · E1', 'S2 · E2'],
    );
  });

  test('MovieBox Hot Shorts TV is recognized as a separate feed', () {
    final section = MovieBoxHomeSection.fromApi({
      'title': 'Hot Shorts TV',
      'items': [
        {
          'id': 'short-1',
          'title': 'Example Short',
          'isSeries': true,
          'detailPath': 'series/example-short',
          'cover': 'https://cdn.example.test/short.jpg',
          'year': '2026',
          'subjectType': 2,
        },
      ],
    });

    expect(section.isHotShorts, isTrue);
    expect(section.items.single.isMovieBox, isTrue);
    expect(section.items.single.movieBoxIsSeries, isTrue);
  });
}
