# FLIXORA MovieBox Subtitle Integration

FLIXORA uses the MovieBox/WeFeed subtitle metadata returned with the selected MovieBox stream.

## Runtime flow

1. The existing MovieBox playback request resolves the selected movie or episode.
2. The MovieBox stream response supplies its `subtitles` list (normalized from MovieBox's subtitle list).
3. FLIXORA displays those returned subtitle choices in the existing Subtitle panel.
4. Selecting a MovieBox subtitle activates its supplied subtitle URL through the existing player subtitle path.
5. The Download Subtitle panel lists the same MovieBox results and downloads/applies a selected subtitle through FLIXORA's existing subtitle validation and local cache.

## Scope

- MovieBox-provided subtitles are the primary and only automatic online subtitle source for MovieBox titles.
- No IMDb lookup, Stremio extension search, or third-party subtitle-provider search is used for MovieBox titles.
- Existing embedded subtitle tracks and manual subtitle import remain available.
- Existing Subtitle panel design is preserved.
- This integration does not change playback, stream selection, Audio, Buffering, general video downloads, or any non-subtitle feature.

MovieBox can only return subtitles that are available for the selected title/episode in its upstream catalogue. If the MovieBox response contains no subtitle entries, FLIXORA cannot fabricate additional MovieBox subtitles; manual subtitle import remains available.
