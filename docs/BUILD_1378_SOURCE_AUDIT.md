# FLIXORA TV — Mobile Build #1378 Port Audit

## Authority and safety boundary

- Mobile reference repository: `shohanur2/FLIXORA-BOX`
- Immutable reference revision: `a3a167b4c74bbb141a29a80c58c97f0f8f2fe386`
- Reference branch: `fix/fast-first-playback-background-enrichment`
- Reference build: **Mobile Build #1378**
- TV working branch: `feature/build-1378-tv-port`
- The mobile repository is read-only. All TV changes stay in this repository.
- Reuse the existing FLIXORA Supabase project and FLIXORA-ADMIN; do not recreate or modify their schema.
- Do not remove features to make the TV build easier. Adapt input, focus, layout and platform APIs while retaining the behavior.

## Current repository inventory (verified 2026-11-19)

The Mobile Build #1378 source tree has **82 tracked files**. The current TV branch has **32 tracked files** after the audit/CI and documentation updates.

TV branch currently includes:

- `.github/workflows/build.yml`, `README.md`, `docs/BUILD_1378_SOURCE_AUDIT.md`
- `lib/main.dart` and the currently ported Dart modules under `lib/archive*`, `lib/downloads`, `lib/native`, `lib/player`, `lib/services`, `lib/streaming`, `lib/video_quality_service.dart`, `lib/widgets/liquid_glass_surface.dart`
- `pubspec.yaml`
- Android Kotlin `MainActivity.kt` and `DownloadForegroundService.kt`
- Rust playback core and SparkBox patch scripts.

The TV app's current `lib/main.dart` is still a compact TMDB-only Home scaffold. It is not yet the complete Mobile Build #1378 app. The TV branch does not yet contain a committed Android Gradle project, launcher resource set, or full mobile test suite.

## Build #1378 source inventory and gaps

### Main application and UI

- Mobile source: `lib/main.dart` (19,845 lines at the reference revision)
- TV source: `lib/main.dart` is currently a smaller independent scaffold.
- Mobile `main.dart` contains substantial catalogue, navigation, settings, Player and Subtitle integration. A file-level copy without dependency and TV focus adaptation is not sufficient.

### Mobile source modules missing from TV at audit time

- `lib/streaming/anilist_service.dart`
- `lib/streaming/external_catalog_service.dart`
- Mobile Android Gradle project files and wrapper configuration
- Mobile launcher icon resources and image assets
- Mobile test suite (15 Dart test files)
- Supabase Edge Function source files in the mobile repository (the existing backend remains authoritative; do not redeploy or change it as part of this client port).

### Shared modules already present in TV

- MovieBox / streaming: `moviebox_service.dart`, `moviebox_stream_policy.dart`, `provider_catalog.dart`, `provider_embed_player.dart`, `streaming_source.dart`, `catalog_source_policy.dart`, `featured_carousel_layout.dart`, `hero_slider_mixer.dart`, `tmdb_media_type.dart`, `trending_movie_eligibility.dart`
- Player/native: `sparkbox_core.dart`, `rust_playback_core.dart`, `playback_error_policy.dart`, `picture_in_picture_service.dart`
- Downloads/platform: `resumable_download_service.dart`, `DownloadForegroundService.kt`, `MainActivity.kt`
- Other: `archive_screen.dart`, `archive_service.dart`, `notification_service.dart`, `catalog_visibility_service.dart`, `video_quality_service.dart`
- Rust: `rust/flixora_core/Cargo.toml`, `rust/flixora_core/src/lib.rs`
- Build patch scripts: `scripts/patch_sparkbox_fast_stream.py`, `scripts/patch_sparkbox_short_tv.py`

## Dependency comparison

Mobile Build #1378 dependencies include (among others):

- `google_fonts`, `screen_brightness`, `http`, `dio`, `file_picker`
- `shared_preferences`, `path_provider`, `connectivity_plus`, `app_settings`
- `cached_network_image`, `flutter_cache_manager`, `share_plus`
- `supabase_flutter`, `firebase_core`, `firebase_messaging`, `flutter_local_notifications`
- `media_kit`, `media_kit_video`, `media_kit_libs_video`, `video_player`
- `webview_flutter`, `webview_flutter_android`

The TV pubspec currently has only a subset: `ffi`, WebView, Dio, path_provider, shared_preferences, Firebase, local notifications, http, cached_network_image, Supabase and media_kit packages. It is missing several packages required by the actual mobile `main.dart` (including file_picker, connectivity_plus, app_settings, google_fonts, flutter_cache_manager, share_plus, screen_brightness and video_player). Do not add packages blindly: map each import/use to a TV-compatible implementation or supported equivalent and document intentional differences.

## Android and CI findings

1. TV currently creates Android project files at build time using `flutter create`; this means important Gradle, manifest and resource configuration is not versioned in the TV repository.
2. The workflow currently applies desugaring and Leanback/landscape changes with Python text edits to generated Gradle/manifest files. This is brittle compared with a committed, reviewed Android project.
3. The mobile reference has a Groovy `android/app/build.gradle`, `settings.gradle`, root `build.gradle`, Gradle wrapper, launcher resources and Firebase configuration. TV must use a deliberately reviewed TV-specific Android project, not blindly copy mobile Firebase or launcher settings.
4. The mobile manifest includes PiP, download service, auth callback and notification permissions. Each must be evaluated for TV support and preserved where applicable.
5. Rust core compilation succeeded in Build #30; SparkBoxCore build was still running at the last status check. This does not verify Flutter analysis, APK generation or runtime behavior.
6. Automatic push builds have been paused during the audit. The workflow now uses manual dispatch only, preventing every documentation/source update from triggering another unreviewed build.

## Feature parity audit

| Area | Current evidence | Status |
|---|---|---|
| Home/catalogue | TMDB-only scaffold in TV main.dart | Incomplete |
| Admin/Supabase catalogue merge | Supabase initialization exists; merge not integrated in TV UI | Incomplete |
| MovieBox / WeFeed | Some shared services and native build scripts are present; TV UI integration unverified | Incomplete |
| Player | Full mobile Player is not integrated into TV main.dart | Incomplete |
| Audio / quality / buffering / seeking / resume | Mobile source has implementations; TV end-to-end integration not verified | Incomplete |
| Subtitles | Extensive logic is embedded in mobile main.dart; full implementation not ported to TV main.dart | Incomplete |
| Download/background download | Service and Android service files are present; TV runtime test absent | Incomplete |
| PiP/Mini Player | Mobile PiP service copied; Android TV support and integration unverified | Incomplete |
| Liquid Glass | Reusable surface and limited Home usage exist | Partial |
| D-pad/remote | Home has partial navigation only | Incomplete |
| Android TV launcher | CI currently injects Leanback category; no committed full TV launcher resources | Partial |
| Device testing | No verified Android TV / Google TV device acceptance report | Not done |

## Required implementation order

1. Freeze the Mobile Build #1378 reference and maintain the TV-only repository boundary.
2. Finish source/dependency/API mapping before copying the main application wholesale.
3. Port missing shared modules, assets and tests where relevant; preserve the existing backend and Admin Panel.
4. Replace CI-generated Android project configuration with a committed, reproducible Android TV project and validated manifest/resources.
5. Integrate the full mobile app behavior into TV navigation and large-screen layouts; add complete remote focus and key handling.
6. Integrate and verify MovieBox/WeFeed, Player, Audio, Subtitle, Resume, Download, Library, Archive and other supported capabilities.
7. Apply Liquid Glass consistently without degrading TV rendering performance or focus visibility.
8. Run static analysis and tests, then one controlled build; validate APK installation and feature flows on Android TV/Google TV before considering merge.

## Current status

- [x] Identify immutable Mobile Build #1378 reference.
- [x] Isolate work on TV branch.
- [x] Inventory actual TV and mobile source trees.
- [x] Identify missing mobile files, dependencies and Android project configuration.
- [x] Correct README to state the actual source baseline and incomplete status.
- [x] Pause automatic push builds during the audit.
- [ ] Complete source/API mapping and port the missing shared modules.
- [ ] Integrate full Build #1378 application, Player and Subtitle behavior into TV.
- [ ] Complete remote focus and Liquid Glass adaptation across all screens.
- [ ] Commit and validate a reproducible Android TV project.
- [ ] Run analyzer/tests and one controlled build after review.
- [ ] Verify all acceptance flows on Android TV and Google TV devices.

**No release or feature parity claim is valid until the remaining checks are completed.**
