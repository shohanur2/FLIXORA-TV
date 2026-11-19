# FLIXORA TV — Mobile Build #1378 Port Audit

## Source of truth and repository boundaries

- Mobile reference: `shohanur2/FLIXORA-BOX`
- Immutable reference commit: `a3a167b4c74bbb141a29a80c58c97f0f8f2fe386`
- Reference: Mobile Build #1378
- TV repository: `shohanur2/FLIXORA-TV`
- Working branch: `feature/build-1378-tv-port`
- All changes stay in FLIXORA-TV. FLIXORA-BOX remains read-only.
- Reuse the existing Supabase project and FLIXORA-ADMIN. Do not recreate or change their schema or deploy Edge Functions as part of this client port.
- Preserve all Build #1378 features. TV-specific changes are limited to layout, focus, remote input and platform integration.

## Verified source inventory

At the first parity-port audit, Mobile Build #1378 had 82 tracked files and TV had 73 tracked files. The mobile tree contains several items deliberately not copied to the TV client:
- Supabase Edge Functions and their deploy workflow: backend remains shared and unchanged.
- `google-services.json`: private Firebase client configuration is not committed; CI can receive it through the optional `FIREBASE_GOOGLE_SERVICES_JSON_BASE64` Actions secret.
- Mobile release/deploy workflows and the launcher-icon generator input; TV has its own Android launcher icon density resources.
- Empty placeholder files and mobile-only platform resources.

Ported to TV:
- Full `lib/main.dart` from the immutable Build #1378 reference (19,845 lines at source revision; 19,966 lines after TV adaptations).
- Required Dart dependencies from Build #1378.
- MovieBox/Rust/streaming, archive, download, PiP, notification and catalogue visibility modules.
- AniList and external catalogue services.
- 15 Dart unit-test files.
- FLIXORA logo, launcher icon densities, Android TV manifest, dark launch themes, Leanback banner, Gradle configuration and Kotlin platform files.

## Current TV adaptations

- Android TV / Google TV Leanback launcher category, required Leanback feature, optional touchscreen, landscape orientation and banner drawable.
- Root focus traversal and always-visible focus highlight strategy.
- Purple remote-focus feedback, focusable controls and autofocus on the selected bottom-navigation item.
- Player: media Play/Pause, media Rewind/Fast Forward; D-pad left/right seek when playback overlay is hidden; OK/Select shows the controls. When the overlay is visible, arrows remain available for focus traversal.
- Hot Shorts: D-pad up/down changes short; OK/Select toggles controls; media Play/Pause keys operate playback.
- Liquid Glass: Home and policy headers, bottom navigation and Player control bars. Remaining screens still need consistent styling and performance review.
- Android launch splash uses a dark FLIXORA background and launcher icon.

These changes are source-level adaptations only. They do not prove device compatibility or feature parity until tested on actual Android TV / Google TV hardware.

## Android build and CI

- Committed Android project files: Gradle build/settings, TV manifest, launcher resources, launch themes, Kotlin MainActivity and download foreground service.
- Core library desugaring is enabled in the committed Groovy Gradle file for flutter_local_notifications.
- Firebase Google Services is applied only when optional Firebase client configuration is supplied as an Actions secret.
- CI no longer regenerates the committed Android project. It creates a temporary Flutter Android project solely to obtain Gradle wrapper scripts/JAR, then copies those wrapper files into the TV project.
- CI uses Flutter 3.35.7 and Java 17, runs Flutter analyze and the full Dart/widget test suite before APK generation.
- Automatic push builds remain disabled. The workflow is manual-dispatch only.
- Build #30 passed Rust, SparkBoxCore, dependency install, analyze, APK build and artifact upload on the old scaffold commit `3b8f183c3862c9305dc7dfd7504bd5c0b0c281c7`. It predates the full Build #1378 port and does not validate the current branch.

## Feature parity status

| Area | Current evidence | Status |
|---|---|---|
| Home/catalogue | Full Build #1378 source; TV layout and focus still need device checks | Partial |
| Admin/Supabase | Build #1378 catalogue and visibility code present; live shared-backend verification pending | Partial |
| MovieBox / WeFeed | Build #1378 UI/source, MovieBox/Rust services and SparkBoxCore build steps present; live API verification pending | Partial |
| Player | Full Build #1378 Player source plus TV media/D-pad key handling; device testing pending | Partial |
| Audio / quality / buffering / seeking / resume | Build #1378 implementations present; TV runtime behavior unverified | Partial |
| Subtitles | Full Build #1378 subtitle source present; language selection, import, lookup and rendering need TV verification | Partial |
| Download/background download | UI/source, resumable service and Android foreground service present; runtime test pending | Partial |
| PiP/Mini Player | Source/service and Android activity support present; TV OS support and lifecycle unverified | Partial |
| Hot Shorts | Source present; D-pad page/play controls added; device testing pending | Partial |
| Liquid Glass | Home/policy headers, navigation and Player bars styled; other screens/performance tuning pending | Partial |
| D-pad/remote | Home focus, Player keys and Hot Shorts controls added; all remaining menus/dialogs/shelves require testing | Partial |
| Launcher | Leanback manifest, landscape, icons and banner committed | Partial |
| Device testing | No verified TV device acceptance report yet | Not tested |

## Remaining work — in order

1. Validate clean dependency resolution, Flutter analyze and all 15 tests.
2. Verify committed Gradle/manifest/resources and complete one controlled CI build after source review.
3. Audit every screen, card shelf, selector, dialog, settings panel and player action for D-pad focus, Back/OK and predictable focus return.
4. Complete large-screen layout and scaling for common 720p/1080p/4K TV resolutions.
5. Apply Liquid Glass consistently while profiling blur/render performance on lower-powered TV boxes.
6. Verify Supabase Admin-published precedence and catalogue visibility against the existing live backend.
7. Verify MovieBox/WeFeed discovery, detail, season/episode selection, stream resolution and playback.
8. Verify audio, quality, buffering, seek, resume, subtitle language selection, external/manual subtitle import, lookup, download, style and delay.
9. Verify download/background download, PiP/Mini Player, notifications and plugin compatibility on target TV OS versions.
10. Install and test on at least one Android TV / Google TV device and one Android TV box before considering release or merge.

## Completed in this audit pass

- [x] Freeze Mobile Build #1378 reference and keep mobile repo untouched.
- [x] Restore full Build #1378 main.dart baseline and dependency set.
- [x] Port shared modules, AniList/external catalogue, 15 unit tests and FLIXORA assets.
- [x] Add committed Android TV Gradle/manifest/theme/launcher configuration.
- [x] Remove CI's fragile generated-project mutation; bootstrap only Gradle wrapper files.
- [x] Add TV Player and Hot Shorts remote-key handling.
- [x] Add navigation focus feedback and selected-tab autofocus.
- [x] Apply Liquid Glass to key Home, policy, navigation and Player surfaces.\n- [x] Add a 1920dp content-width cap for ultra-wide displays and a 320x180dp Leanback banner.
- [x] Update README and this audit to reflect the actual implementation.

## Not yet verified

- [ ] Current branch clean Flutter dependency resolution.
- [ ] Current branch `flutter analyze` and all Dart tests (now included in CI before APK build).
- [ ] Current branch Rust/SparkBoxCore build and APK generation.
- [ ] Installation, launcher discovery, focus behavior and playback on TV hardware.
- [ ] Full feature parity and release acceptance.

**Do not describe FLIXORA TV as finished or feature-complete until every relevant runtime acceptance test has passed.**
