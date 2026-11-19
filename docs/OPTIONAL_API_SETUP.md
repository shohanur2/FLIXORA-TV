# FLIXORA provider and API setup

This guide separates **metadata/availability APIs** from **video playback sources**. They are different things: a catalogue API can tell FLIXORA what a title is and where it is available, but it does not automatically provide a playable movie stream.

## What is already in the app

- **TMDB** — movie/TV discovery, posters, backdrops, release dates, genres and title IDs.
- **AniList** — anime metadata and matching.
- **OMDb** — IMDb rating, Metascore, runtime, content rating and box-office metadata.
- **Watchmode** — region-specific subscription, free, rent and buy availability; it returns links and provider details, not video.
- **TasteDive** — related movie and TV recommendations (legacy endpoint).
- **Trakt** — community rating, vote count and rank.
- **Internet Archive** — public-domain/CC0 catalogue items only.
- **Existing player sources** — Admin-managed direct MP4/HLS and the provider adapters already in FLIXORA. The current player and Admin source priority must remain unchanged.

The Supabase `external-catalog` Edge Function is already deployed and active in the FLIXORA project. Its optional API integrations read secrets server-side.

## 1. API keys and where to get them

| Secret name | Required? | Get it from | Used for |
|---|---|---|---|
| `TMDB_API_KEY` | Required for catalogue | [TMDB API settings](https://www.themoviedb.org/settings/api) | Movie/TV catalogue and metadata |
| `SUPABASE_URL` | Required | Existing FLIXORA Supabase project settings | App database connection |
| `SUPABASE_ANON_KEY` | Required | Existing FLIXORA Supabase API keys | Public app database access under RLS |
| `SUPABASE_ACCESS_TOKEN` | Only for function deployment | [Supabase personal access tokens](https://supabase.com/dashboard/account/tokens) | Lets GitHub Actions deploy the Edge Function |
| `SUPABASE_PROJECT_REF` | Only for function deployment | Supabase project URL / project settings | Tells the deploy workflow which project to update |
| `OMDB_API_KEY` | Optional | [OMDb API key request](https://www.omdbapi.com/apikey.aspx) | Extra ratings and title details |
| `WATCHMODE_API_KEY` | Optional | [Watchmode API](https://api.watchmode.com/) | Where-to-watch availability by country |
| `TASTEDIVE_API_KEY` | Optional | [TasteDive API page](https://tastedive.com/read/api) | Similar-title recommendations |
| `TRAKT_CLIENT_ID` | Optional | [Create a Trakt app](https://developer.trakt.tv/docs/create-an-app) | Trakt ratings and community data |
| `DAILYMOTION_PLAYER_ID` | Optional | Dailymotion Studio → Embeds → Players | Enables Admin-supplied Dailymotion embeds |

For this FLIXORA Supabase project:
- `SUPABASE_PROJECT_REF` = `vxqqmilgmfrdcndorhvz`
- `SUPABASE_URL` = `https://vxqqmilgmfrdcndorhvz.supabase.co`

Keep the existing `FLIXORA_KEYSTORE_BASE64`, `FLIXORA_KEYSTORE_PASSWORD` and `FLIXORA_KEY_ALIAS` signing secrets unchanged. Do not send API keys or signing credentials in chat.

## 2. Where to put the values

In the private GitHub repository:

1. Open **Settings → Secrets and variables → Actions**.
2. Under **Repository secrets**, add each value using the exact secret name from the table.
3. Do not add optional keys unless you have actually obtained them.
4. Open **Actions → Deploy FLIXORA Supabase Functions → Run workflow**.
5. Wait for the workflow to finish successfully. It stores supplied optional keys as Supabase Edge Function secrets and deploys `external-catalog`.
6. Build a new APK only when a Flutter build-time secret such as `TMDB_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` or `DAILYMOTION_PLAYER_ID` changes.

The app's build workflow already passes the four Flutter build-time values above. The catalogue function's optional keys are **not** compiled into the APK.

## 3. Important free-plan and policy notes

- **Watchmode** documents a free Developer plan with a monthly credit allowance for non-commercial use. Check the current plan and attribution/cache rules before release.
- **OMDb** advertises a free daily request limit; its API data is licensed CC BY-NC 4.0. Check that the intended use remains non-commercial and follows the licence.
- **TasteDive** describes its endpoint as a legacy API while directing new development toward Qloo. The current FLIXORA integration uses the legacy TasteDive endpoint; a Qloo migration is a separate task and needs its own approved access.
- **Trakt** requires developers to follow its API policy. Its app-creation terms expressly prohibit using Trakt data in apps that promote copyright infringement or piracy. Do not configure/use Trakt unless FLIXORA's content and playback integrations comply with those terms.
- **Dailymotion** requires a valid Player ID for current embeds. Dailymotion's custom player/embed features may require an eligible plan; check the account's current Studio entitlements before relying on it.
- A Supabase personal access token should be scoped to the FLIXORA project and only the permissions needed for function deployment. Never put a service-role/secret key in Flutter or in `--dart-define`.

## 4. About HDHub4u and other requested directories

The FLIXORA reference project treats HDHub4u and MovieLinkBD as **external directory/search destinations**, not as official playback APIs. The HDHub4u helper only builds a title-search URL; it does not return a verified video URL, an episode resolver, or a documented API response. The reference's 4KHDHub helper is also a download-search URL builder, not a streaming API.

For that reason, these directory/scraper integrations are not being presented as reliable in-app playback providers. I will not add private scraping, bypasses, or undocumented resolver endpoints. A provider can be added to FLIXORA's in-app player when it supplies a documented API/SDK or a source URL that the owner is authorized to use. The Admin panel can continue to attach authorized direct files and embed links.

## 5. Playback behaviour to preserve

- Admin-managed source and publication status remain higher priority than catalogue-only metadata.
- TMDB IDs remain the canonical duplicate-matching key, separated by `movie` and `tv` media type.
- The selected season and episode must be passed unchanged to the selected TV provider route.
- A metadata or where-to-watch API must never be treated as a playable stream.
- Existing Player controls, source fallback, Offline Home cache, and the dedicated no-internet screen must not be rebuilt as part of API-key setup.
