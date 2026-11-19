import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/main.dart';

void main() {
  Movie buildMovie({
    int id = 157336,
    int tmdbId = 157336,
    String mediaType = 'movie',
    String videoUrl = '',
  }) {
    return Movie(
      id: id,
      tmdbId: tmdbId,
      title: 'Interstellar',
      year: '2014',
      overview: 'A test movie.',
      poster: '',
      backdrop: '',
      rating: 8.6,
      releaseDate: '2014-11-07',
      videoUrl: videoUrl,
      mediaType: mediaType,
    );
  }

  group('Media title playback eligibility', () {
    test('TMDB metadata alone is not a playable source', () {
      final movie = buildMovie();

      expect(movie.hasPlayableVideoUrl, isFalse);
      expect(movie.canAttemptPlayback, isFalse);
    });

    test('direct video remains playable without a TMDB ID', () {
      final movie = buildMovie(
        id: -12,
        tmdbId: 0,
        videoUrl: 'https://cdn.example.com/movie.mp4',
      );

      expect(movie.hasPlayableVideoUrl, isTrue);
      expect(movie.canAttemptPlayback, isTrue);
    });

    test('movie without a direct URL or TMDB ID is not playable', () {
      final movie = buildMovie(id: -12, tmdbId: 0);

      expect(movie.canAttemptPlayback, isFalse);
    });

    test('TV metadata alone is not playable before MovieBox matching', () {
      final title = buildMovie(mediaType: 'tv');

      expect(title.hasPlayableVideoUrl, isFalse);
      expect(title.canAttemptPlayback, isFalse);
    });

    test('Supabase TV content retains its media type', () {
      final title = Movie.fromSupabase({
        'id': 12,
        'tmdb_id': 1399,
        'title': 'Example Series',
        'media_type': 'tv',
      });

      expect(title.mediaType, 'tv');
      expect(title.canAttemptPlayback, isFalse);
    });

    test('legacy Supabase rows remain movies by default', () {
      final title = Movie.fromSupabase({
        'id': 13,
        'tmdb_id': 157336,
        'title': 'Interstellar',
      });

      expect(title.mediaType, 'movie');
    });
 
    test('MovieBox match preserves the published Admin record identity', () {
      final admin = Movie.fromSupabase({
        'id': 42,
        'tmdb_id': 157336,
        'title': 'Interstellar',
        'media_type': 'movie',
        'release_date': '2014-11-07',
        'is_published': true,
      });
      final movieBox = Movie.fromMovieBox({
        'id': 'mb-42',
        'title': 'Interstellar',
        'isSeries': false,
        'detailPath': 'movie/interstellar',
        'cover': 'https://cdn.example.test/poster.jpg',
        'year': '2014',
        'subjectType': 1,
      });

      final resolved = movieBox.withFallbackMetadata(admin);

      expect(resolved.isMovieBox, isTrue);
      expect(resolved.sourceId, 42);
      expect(resolved.tmdbId, 157336);
      expect(resolved.title, 'Interstellar');
    });

  });
}
