import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/catalog_source_policy.dart';

void main() {
  group('CatalogSourcePolicy', () {
    test('MovieBox wins over a published Admin duplicate', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: 'moviebox',
        publishedAdminFallback: 'admin',
      );

      expect(selected, 'moviebox');
    });

    test('published Admin is used only when MovieBox has no match', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: null,
        publishedAdminFallback: 'admin',
      );

      expect(selected, 'admin');
    });

    test('returns unavailable when neither source has a match', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: null,
        publishedAdminFallback: null,
      );

      expect(selected, isNull);
    });

    test('MovieBox replaces only its duplicate and preserves other card order', () {
      final ordered = CatalogSourcePolicy.preferMovieBoxDuplicates<String>(
        [
          'first',
          'admin:interstellar',
          'middle',
          'moviebox:interstellar',
          'last',
        ],
        isMovieBox: (source) => source.startsWith('moviebox:'),
        matches: (movieBoxItem, candidate) =>
            movieBoxItem.split(':').last == candidate.split(':').last,
      );

      expect(
        ordered,
        ['first', 'middle', 'moviebox:interstellar', 'last'],
      );
    });

    test('indexed MovieBox matching removes only exact duplicate candidates', () {
      final ordered = CatalogSourcePolicy.preferMovieBoxDuplicatesByKey<String>(
        [
          'first',
          'admin:interstellar',
          'middle',
          'moviebox:interstellar',
          'admin:other',
          'last',
        ],
        isMovieBox: (item) => item.startsWith('moviebox:'),
        movieBoxKeys: (item) => item == 'moviebox:interstellar'
            ? const ['tmdb:movie:42', 'title:movie:interstellar:year:2014']
            : const [],
        candidateKeys: (item) => item == 'admin:interstellar'
            ? const ['tmdb:movie:42']
            : const [],
      );

      expect(
        ordered,
        ['first', 'middle', 'moviebox:interstellar', 'admin:other', 'last'],
      );
    });

    test('indexed matching preserves different release years', () {
      final ordered = CatalogSourcePolicy.preferMovieBoxDuplicatesByKey<String>(
        ['admin:2022', 'moviebox:2024'],
        isMovieBox: (item) => item.startsWith('moviebox:'),
        movieBoxKeys: (_) => const ['title:movie:dune:year:2024'],
        candidateKeys: (_) => const ['title:movie:dune:year:2022'],
      );

      expect(ordered, ['admin:2022', 'moviebox:2024']);
    });

    test('only Admin rows are sent to publication visibility checks', () {
      final candidates = CatalogSourcePolicy.adminCandidates<String>(
        ['tmdb', 'moviebox', 'admin'],
        isAdmin: (source) => source == 'admin',
      );

      expect(candidates, ['admin']);
    });

    test('Admin visibility key identifies the exact Admin row', () {
      expect(
        CatalogSourcePolicy.adminVisibilityKey(
          isAdmin: true,
          sourceId: 42,
        ),
        'admin:id:42',
      );
      expect(
        CatalogSourcePolicy.adminVisibilityKey(
          isAdmin: false,
          sourceId: 42,
        ),
        isNull,
      );
    });

    test('only requested exact Admin keys are accepted from visibility results', () {
      expect(
        CatalogSourcePolicy.filterBlockedAdminKeys(
          requestedKeys: const ['admin:id:42'],
          blockedKeys: const [
            'admin:id:42',
            'admin:id:99',
            'tmdb:157336',
            'title:interstellar:2014',
          ],
        ),
        {'admin:id:42'},
      );
    });

    test('MovieBox remains canonical even when a published Admin duplicate exists', () {
      final selected = CatalogSourcePolicy.preferMovieBox<String>(
        movieBoxMatch: 'moviebox-stream-unavailable',
        publishedAdminFallback: 'admin',
      );
      expect(selected, 'moviebox-stream-unavailable');
    });

    test('unpublishing Admin does not block a matching MovieBox title', () {
      final blockedKeys = {'admin:id:42'};

      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: true,
          visibilityKey: 'admin:id:42',
          blockedKeys: blockedKeys,
        ),
        isTrue,
      );
      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: false,
          visibilityKey: 'admin:id:42',
          blockedKeys: blockedKeys,
        ),
        isFalse,
      );
      expect(
        CatalogSourcePolicy.isAdminBlocked(
          isAdmin: false,
          visibilityKey: null,
          blockedKeys: blockedKeys,
        ),
        isFalse,
      );
    });
  });
}
