# FLIXORA TV

FLIXORA TV is the dedicated Android TV / Google TV edition of FLIXORA. The goal is full feature parity with the authoritative FLIXORA Mobile Build #1378, with TV-specific layout, D-pad focus, remote-key handling, large-screen scaling and platform integration.

## Source of truth and repository boundaries

- Mobile reference: `shohanur2/FLIXORA-BOX`
- Immutable reference commit: `a3a167b4c74bbb141a29a80c58c97f0f8f2fe386` (Mobile Build #1378)
- TV working branch: `feature/build-1378-tv-port`
- All implementation changes belong in this repository. The mobile repository is read-only.
- Reuse the existing FLIXORA Supabase project and FLIXORA-ADMIN. Do not recreate or modify their schema/configuration as part of the TV port.
- Never commit service-role keys, signing secrets, or private credentials.

## Product requirements

The TV app must retain the mobile app's functional capabilities, including:

- FLIXORA catalogue, TMDB discovery, Admin-published titles, duplicate resolution and visibility policy.
- MovieBox / WeFeed discovery, detail resolution, stream resolution and playback.
- Player controls, audio-track selection, quality selection, buffering/error handling, seeking, resume/watch progress and supported fullscreen behavior.
- Complete subtitle experience: embedded tracks, MovieBox subtitles, automatic subtitle lookup where configured, language selection, manual file/URL import, subtitle download, style and delay controls.
- Download and background-download flows, saved/library features, archive/shorts and notifications where supported by the TV platform.
- Liquid Glass visual language: dark cinematic surfaces, restrained purple/gold accents, frosted panels, clear focus glow and remote-friendly sizing.
- D-pad navigation and Back/OK behavior across every screen, shelf, menu, dialog, selector and player control.

A mobile-only interaction may receive a TV-specific equivalent, but its underlying capability must not silently disappear.

## Current implementation status (honest snapshot)

The current TV branch is still an incomplete port, not a finished playable release.

- `lib/main.dart` contains the full Mobile Build #1378 application baseline, including Home/catalogue, MovieBox/WeFeed integration paths, Player, Subtitle, Download and Library code. TV-specific focus traversal, Home navigation autofocus, Player media/D-pad keys and Hot Shorts D-pad controls have been added; full remote testing remains pending.
- Shared MovieBox/Rust wrappers, streaming policies, AniList/external catalogue services, download service, PiP service, notification service, archive modules and 15 mobile unit tests have been ported.
- Build #1378 dependencies, FLIXORA logo, Android TV Leanback manifest, landscape configuration, launcher icon densities, TV banner drawable and committed Android Gradle configuration are present. Liquid Glass has been applied to Home/policy headers, bottom navigation and Player control bars; app-wide styling and large-screen layout adaptation remain incomplete.
- MovieBox/WeFeed APIs, Admin/Supabase data, Player/Subtitle playback, native downloads/PiP and plugin behavior still need real Android TV / Google TV runtime verification.
- Presence of a Dart wrapper or native library build step does not by itself prove the corresponding feature works on a TV device.

See [the detailed Build #1378 audit](docs/BUILD_1378_SOURCE_AUDIT.md) for the source inventory, known gaps and validation plan.

## Build and CI

The workflow is `.github/workflows/build.yml`. During the full audit and port, automatic push-triggered builds are intentionally disabled; use **workflow_dispatch** only after the source/configuration review is complete.

Required GitHub Actions secrets for the current catalogue/backend integration:

- `TMDB_API_KEY`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` (optional; Base64-encoded Android `google-services.json` to enable the existing Firebase push-notification integration)

Only the Supabase anon/publishable key belongs in the client build. Never use a service-role key in the app.

The Android Gradle files, TV manifest, launcher resources and themes are committed. CI creates a temporary Flutter Android project only to obtain Gradle wrapper scripts/JAR, then copies those wrapper files into the TV project; it does not regenerate or overwrite the committed TV Android configuration.

## Release acceptance checklist

A release is not ready until all of the following are verified:

1. Flutter dependency resolution and static analysis pass from a clean checkout.
2. Rust core and SparkBoxCore build and package all intended Android TV ABIs.
3. APK installs, launches and is discoverable from Android TV / Google TV launchers.
4. D-pad focus is always visible and predictable; Back, OK, arrows and playback keys behave correctly.
5. Admin-published content takes precedence over matching TMDB catalogue entries.
6. MovieBox / WeFeed discovery, details, episode selection and stream resolution work.
7. Playback, audio, quality, buffering, seek, resume and error recovery work.
8. Subtitle language selection, embedded and external subtitles, lookup, import, download and style/delay controls work.
9. Download/background behavior and other supported mobile capabilities work on target TV devices.
10. No regression is introduced into the mobile app, Supabase backend or existing Admin Panel.

Do not mark a feature complete based only on compilation. Record the device/emulator and test result for each acceptance item.
