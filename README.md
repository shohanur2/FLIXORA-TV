# FLIXORA TV

Separate Android TV / Google TV application for FLIXORA.

## Repository boundary

- This repository contains the TV application only.
- `FLIXORA-BOX` is a read-only reference. Do not commit or modify mobile app files.
- The existing FLIXORA Supabase project and FLIXORA Admin Panel are reused; do not recreate them.
- Never place Supabase service-role keys or private credentials in this public repository.

## Current scaffold

- Flutter Android application shell.
- Landscape Android manifest setup in CI.
- Android TV Leanback launcher category and Leanback feature declaration in CI.
- TMDB trending movie and TV-series feed.
- Home hero slider with automatic advance and remote left/right controls.
- Initial movie and web-series shelves.
- GitHub Actions workflow to analyze and build a release APK.

## Build

The GitHub Actions workflow `.github/workflows/build.yml` runs on pushes to `main` and manual dispatch. It generates the Android platform project, runs `flutter analyze`, builds a release APK and uploads it as an artifact.

Configure these GitHub Actions repository secrets before expecting live catalogue data:

- `TMDB_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

The app currently uses TMDB for its first live catalogue scaffold. Supabase initialization is prepared but the Admin-published catalogue merge is not implemented yet.

## Not implemented yet

- Exact approved Build #962 mobile Player port/adaptation. Its authoritative source revision still needs to be located and verified.
- Full D-pad focus traversal across all shelves, search, details and dialogs.
- MovieBox / WeFeed native Rust core packaging and Android TV ABI validation.
- Admin-published Supabase titles taking priority over TMDB duplicates.
- Full details, seasons, episode selection, subtitle/audio/quality controls and functional playback.
- Automated TV device / emulator testing.

Do not treat the current scaffold as a finished TV app or a verified playable release.
