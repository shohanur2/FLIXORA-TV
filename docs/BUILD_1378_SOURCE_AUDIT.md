# FLIXORA TV — Build #1378 Port Audit

## Authority and safety boundary

- Mobile reference repository: `shohanur2/FLIXORA-BOX`
- Immutable reference revision: `a3a167b4c74bbb141a29a80c58c97f0f8f2fe386`
- Reference branch at the time of audit: `fix/fast-first-playback-background-enrichment`
- Reference build: **Build #1378**
- TV working branch: `feature/build-1378-tv-port`
- Never commit changes to `FLIXORA-BOX`; all TV work stays in this repository.
- Keep the existing Supabase project and FLIXORA-ADMIN. Do not recreate either.
- Do not drop or silently replace any mobile feature. TV-specific changes may adapt input, focus, layout, lifecycle, and platform integration while preserving behavior.

## Current TV repository state (audited)

The TV branch currently contains only four tracked files:

- `.github/workflows/build.yml`
- `README.md`
- `lib/main.dart`
- `pubspec.yaml`

The current TV app is a small TMDB-only scaffold. It has a home screen, a hero carousel, two shelves (Trending Movies and Popular Web Series), and partial D-pad handling. It is not yet a functional port of the mobile app.

The current TV dependencies are limited to Flutter, cupertino_icons, http, cached_network_image, supabase_flutter, media_kit, media_kit_video, and media_kit_libs_video.

## Build #1378 source inventory

The reference revision has 82 tracked files. Important implementation areas identified in the source tree include:

### Main application and UI
- `lib/main.dart`
- `lib/archive_screen.dart`
- `lib/archive_service.dart`
- `lib/video_quality_service.dart`

### MovieBox / WeFeed / streaming
- `lib/streaming/moviebox_service.dart`
- `lib/streaming/moviebox_stream_policy.dart`
- `lib/streaming/provider_catalog.dart`
- `lib/streaming/provider_embed_player.dart`
- `lib/streaming/streaming_source.dart`
- `lib/streaming/external_catalog_service.dart`
- `lib/streaming/catalog_source_policy.dart`
- `lib/streaming/hero_slider_mixer.dart`
- `lib/streaming/featured_carousel_layout.dart`
- `lib/streaming/trending_movie_eligibility.dart`
- `lib/streaming/tmdb_media_type.dart`
- `lib/streaming/anilist_service.dart`

### Player / native playback / PiP
- `lib/native/sparkbox_core.dart`
- `lib/native/rust_playback_core.dart`
- `lib/player/playback_error_policy.dart`
- `lib/player/picture_in_picture_service.dart`
- `android/app/src/main/kotlin/com/flixora/flixora/MainActivity.kt`
- `rust/flixora_core/Cargo.toml`
- `rust/flixora_core/src/lib.rs`
- `scripts/patch_sparkbox_fast_stream.py`
- `scripts/patch_sparkbox_short_tv.py`

### Download / notifications / platform
- `lib/downloads/resumable_download_service.dart`
- `lib/services/notification_service.dart`
- `android/app/src/main/kotlin/com/flixora/flixora/DownloadForegroundService.kt`
- `android/app/build.gradle`
- `android/app/src/main/AndroidManifest.xml`

### Backend and catalog policy
- `lib/services/catalog_visibility_service.dart`
- `lib/streaming/catalog_source_policy.dart`
- Supabase remains the existing shared backend; no schema recreation is part of this port.

## Compatibility risks to resolve before claiming parity

1. The TV scaffold currently uses a different, smaller dependency set than Build #1378.
2. Native Rust/SparkBox libraries must be packaged for the Android TV ABIs and verified; copying Dart wrappers alone is insufficient.
3. Android TV remote focus and key handling must work across every screen, dialog, menu, shelf, subtitle selector, and player control.
4. Mobile-only interactions (touch gestures, file picking, system UI, PiP, notifications, download foreground service) need TV-compatible equivalents without removing their capabilities.
5. MovieBox/WeFeed provider integration and subtitle lookup/rendering must be verified end-to-end, not inferred from class/file presence.
6. TV launcher metadata, banner, landscape behavior, and optional touchscreen declaration need to be validated on both Android TV and Google TV.
7. Existing mobile secrets and signing credentials must not be copied into source control.

## Porting order

1. Freeze and inventory Build #1378 source and dependency versions.
2. Port shared Dart application and service code into this TV branch without changing mobile source.
3. Port required assets, Android native code, Rust source/build configuration, and required workflows.
4. Resolve compile/analyzer issues caused by TV platform integration, documenting every intentional platform adaptation.
5. Add TV-first focus navigation and large-screen presentation while preserving all existing features.
6. Validate MovieBox, WeFeed, playback, audio, subtitles, resume, downloads, and Supabase/Admin-published catalog behavior.
7. Build and test on Android TV and Google TV targets; only then consider merging to TV main.

## Current status

- [x] Identify Build #1378 reference commit.
- [x] Create isolated TV working branch.
- [x] Inventory current TV scaffold and key mobile source modules.
- [ ] Port the full Build #1378 source and dependencies.
- [ ] Port native Rust/SparkBox playback integration.
- [ ] Complete TV remote/focus adaptation.
- [ ] Verify full subtitle and player parity.
- [ ] Verify Android TV and Google TV builds/devices.
