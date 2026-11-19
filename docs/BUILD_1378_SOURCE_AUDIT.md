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

The Mobile Build #1378 source tree has **82 tracked files**. The current TV branch has **73 tracked files** after the first parity-port pass.

TV branch currently includes:

- `.github/workflows/build.yml`, `README.md`, `docs/BUILD_1378_SOURCE_AUDIT.md`
- `lib/main.dart` and the currently ported Dart modules under `lib/archive*`, `lib/downloads`, `lib/native`, `lib/player`, `lib/services`, `lib/streaming`, `lib/video_quality_service.dart`, `lib/widgets/liquid_glass_surface.dart`
- `pubspec.yaml`
- Android Kotlin `MainActivity.kt` and `DownloadForegroundService.kt`
- Rust playback core and SparkBox patch scripts.

The TV `lib/main.dart` has now been replaced with the complete 19,845-line Mobile Build #1378 main application source as the feature baseline. The app has a root focus-traversal group and always-visible focus highlight strategy for TV remotes, but this is only foundational adaptation: every screen, row, selector and Player control still needs deliberate D-pad testing and TV layout work. The TV branch now contains the Android Gradle files, TV-specific manifest, app launcher icon densities, launch theme resources and a Leanback banner drawable. Gradle wrapper bootstrap is still generated in CI; Firebase configuration remains an optional Actions secret and must be configured to enable push notifications.

## Build #1378 source inventory and gaps

### Main application and UI

- Mobile source: `lib/main.dart` (19,845 lines at the reference revision)
- TV source: `lib/main.dart` is restored from the exact Build #1378 source as the full feature baseline; TV-specific adaptation remains in progress.
- Mobile `main.dart` contains substantial catalogue, navigation, settings, Player and Subtitle integration. A file-level copy without dependency and TV focus adaptation is not sufficient.

### Mobile source modules missing from TV at audit time

- `lib/streaming/anilist_service.dart`
- `lib/streaming/external_catalog_service.dart`
- Mobile Android Gradle project files and wrapper configuration
- Mobile launcher icon resources and image assets
- (Ported during this audit) 15 Dart unit-test files
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

The TV pubspec has been aligned with the Mobile Build #1378 dependency set, including file_picker, connectivity_plus, app_settings, google_fonts, flutter_cache_manager, share_plus, screen_brightness and video_player. Android TV runtime compatibility of each plugin still needs verification; dependency presence is not proof of a working TV interaction. The FLIXORA logo asset has also been copied and registered.

## Android and CI findings

1. The TV branch now contains committed Groovy Gradle configuration, a TV-specific manifest, landscape orientation, Leanback launcher category, optional touchscreen, launcher icon densities, launch themes and a Leanback banner drawable.
2. CI still runs `flutter create` to bootstrap generated wrapper/platform metadata. Its interaction with committed Android files must be verified before the next build; do not assume every custom file is preserved.
3. Core library desugaring is enabled in the committed app Gradle file. Firebase Google Services is applied only when the optional `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` Actions secret supplies a client configuration. No Firebase config file or private credential is committed.
4. The mobile manifest's PiP, download service, auth callback and notification capabilities are retained where applicable, but PiP/background service behavior still needs TV device verification.
5. Build #30 completed successfully on the pre-port commit `3b8f183c3862c9305dc7dfd7504bd5c0b0c281c7`. Rust, SparkBoxCore, dependency install, analyze, APK build and artifact upload all passed for the old TMDB scaffold. It does **not** validate the current full Build #1378 baseline or the newly committed Android configuration.
6. Automatic push builds are paused; the workflow now uses manual dispatch only.

## Feature parity audit

| Area | Current evidence | Status |
|---|---|---|
| Home/catalogue | Full Build #1378 main.dart baseline restored; TV layout/focus still unverified | Partial |
| Admin/Supabase catalogue merge | Supabase initialization exists; merge not integrated in TV UI | Incomplete |
| MovieBox / WeFeed | Some shared services and native build scripts are present; TV UI integration unverified | Incomplete |
| Player | Full mobile Player is not integrated into TV main.dart | Incomplete |
| Audio / quality / buffering / seeking / resume | Mobile source has implementations; TV end-to-end integration not verified | Incomplete |
| Subtitles | Extensive logic is embedded in mobile main.dart; full implementation not ported to TV main.dart | Incomplete |
| Download/background download | Service and Android service files are present; TV runtime test absent | Incomplete |
| PiP/Mini Player | Mobile PiP service copied; Android TV support and integration unverified | Incomplete |
| Liquid Glass | Reusable surface exists; app-wide conversion still outstanding | Partial |
| D-pad/remote | Root focus traversal/highlight enabled; screen-by-screen directional behavior unverified | Incomplete |
| Android TV launcher | Committed Leanback manifest, landscape, icon densities and banner drawable | Partial |
| Device testing | No verified Android TV / Google TV device acceptance report | Not done |

## Required implementation order

1. Freeze the Mobile Build #1378 reference and maintain the TV-only repository boundary.
2. Finish source/dependency/API mapping before copying the main application wholesale.
3. Port missing shared modules, assets and tests where relevant; preserve the existing backend and Admin Panel.
4. Validate CI Flutter project generation against the committed Android TV Gradle/manifest/resources and make the Android build reproducible.
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
- [x] Port the Build #1378 main.dart baseline, dependencies, AniList/external catalogue services, 15 unit tests and FLIXORA logo.
- [x] Add Android TV manifest, Gradle configuration, launcher icons, launch themes and banner drawable.\n- [ ] Complete source/API mapping for remaining platform-specific behaviors and TV UI.
- [x] Restore full Build #1378 application, Player and Subtitle source baseline in TV main.dart.\n- [ ] Complete TV-specific integration and verify Player/Subtitle behavior end-to-end.
- [ ] Complete remote focus and Liquid Glass adaptation across all screens.
- [ ] Validate CI Flutter project generation against committed Android Gradle/manifest/resources and make the Android build fully reproducible.
- [ ] Run analyzer/tests and one controlled build after review.
- [ ] Verify all acceptance flows on Android TV and Google TV devices.

**No release or feature parity claim is valid until the remaining checks are completed.**
