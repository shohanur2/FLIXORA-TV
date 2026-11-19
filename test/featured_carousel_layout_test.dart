import 'package:flutter_test/flutter_test.dart';
import 'package:flixora/streaming/featured_carousel_layout.dart';

void main() {
  group('FeaturedCarouselLayout', () {
    test('uses one geometry to synchronize the hero and poster row', () {
      final offset = FeaturedCarouselLayout.targetScrollOffset(
        index: 1,
        viewportWidth: 393,
        maxScrollExtent: 900,
      );
      expect(offset, closeTo(163.5, 0.001));
      expect(FeaturedCarouselLayout.cardWidth, 228);
      expect(FeaturedCarouselLayout.cardHeight, 54);
      expect(FeaturedCarouselLayout.posterWidth, 36);
      expect(FeaturedCarouselLayout.posterHeight, 48);
      expect(
        FeaturedCarouselLayout.indexForScrollOffset(
          pixels: offset,
          viewportWidth: 393,
          itemCount: 5,
        ),
        1,
      );
    });

    test('keeps the first card at the start and clamps the final card', () {
      expect(
        FeaturedCarouselLayout.targetScrollOffset(
          index: 0,
          viewportWidth: 393,
          maxScrollExtent: 900,
        ),
        0,
      );
      final lastOffset = FeaturedCarouselLayout.targetScrollOffset(
        index: 4,
        viewportWidth: 393,
        maxScrollExtent: 800,
      );
      expect(lastOffset, 800);
      expect(
        FeaturedCarouselLayout.indexForScrollOffset(
          pixels: lastOffset,
          viewportWidth: 393,
          itemCount: 5,
        ),
        4,
      );
    });

    test('returns a safe index for empty and single-item lists', () {
      expect(
        FeaturedCarouselLayout.indexForScrollOffset(
          pixels: 500,
          viewportWidth: 393,
          itemCount: 0,
        ),
        0,
      );
      expect(
        FeaturedCarouselLayout.indexForScrollOffset(
          pixels: 500,
          viewportWidth: 393,
          itemCount: 1,
        ),
        0,
      );
    });
  });
}
