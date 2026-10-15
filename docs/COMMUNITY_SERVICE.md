# Community service and Steam authentication

The optional online service supports discovery, revision downloads, publication, owned listings, and unpublishing. Offline play and local JSON sharing remain independent. This guide describes checked-in source; it does not establish the current hosted deployment or production authentication status.

## Game-facing contract

`GameManager` creates `CommunityService` and configures it with the session's PuzzleStore and a `SupabaseCommunityBackend`. The service belongs to the application scene. Gameplay/UI do not query provider tables or interpret Auth responses.

Await these service operations:

| Method | Purpose |
| --- | --- |
| `browse_puzzles(filters = {})` | Public metadata search/pagination |
| `get_puzzle(puzzle_id, revision)` | Fetch a published definition |
| `download_puzzle(puzzle_id, revision)` | Fetch and install through `PuzzleStore.install_community` |
| `publish_puzzle(puzzle)` | Check local publication proof and submit playable content |
| `get_my_puzzles(filters = {})` | List owned publications, including unpublished entries |
| `unpublish_puzzle(puzzle_id)` | Remove online availability; installed copies survive |
| `sign_in(email, password)` / `sign_out()` | Email/password fallback session |

Results are `{ok: bool, data: Dictionary, error: Dictionary}`. Success has an empty error; failures contain `error.code` and `error.message`. `authentication_changed`, `is_signed_in()`, and optional adapter capability `uses_automatic_auth()` support UI state. A replacement backend must implement the same operations and required authentication contract; its construction is selected in GameManager.

The adapter uses the plugin-provided `SupabaseClient` autoload. The [addon README](../addons/supabase_client/README.md) owns HTTP/session details. Configure `addons/supabase_client/supabase.cfg` with the project URL and public publishable key. Include it in exports. Secrets and server credentials never belong in the game. No community HTTP request runs during ordinary startup/local gameplay; Steam initializes separately at startup.

The online panel is embedded in PuzzleBrowser. It ignores stale results after closing; an already-submitted request can still finish. Online publication first retains a local published copy. JSON imports and downloads share validation/conflict checks and community storage. Download IDs are `community-<server UUID>-r<revision>`, preserving independent completion records across immutable online revisions. See [Puzzle distribution](PUZZLE_AUTHORING.md).

## API v1

Base path: `/functions/v1/community/v1`. Handler responses use `{api_version: 1, ok, data, error}`. Requests carry the public key as `apikey`. Protected calls additionally carry either `x-steam-ticket` or a Supabase user bearer token.

| Route | Access/result |
| --- | --- |
| `GET /puzzles?search=&offset=0&compatibility=<digest>` | Public; up to 20 metadata rows and nullable `next_offset` |
| `GET /puzzles/<uuid>?revision=1&compatibility=<digest>` | Public; one published compatible revision |
| `POST /puzzles` with `{puzzle, compatibility}` | Verified owner; returns UUID, revision, and `<uuid>@<revision>` share code |
| `GET /mine?search=&offset=0` | Verified owner; metadata including unpublished items |
| `DELETE /puzzles/<uuid>` | Owner only; unpublishes the puzzle and all downloadable revisions |

`supabase/functions/community/index.ts` handles routes, ownership, and persistence. `validation.ts` checks allowed fields, types/ranges, catalog IDs, configuration, ports/links, objectives, and compatibility. Publication accepts at most 5 MB and requires a saved solution and successful-test record. Server validation does not run Godot physics or prove a solution works. Client-side publication and installed-solution rule checks remain necessary.

The release/catalog compatibility digest comes from the game's saved registry, scene settings, and actual port declarations. Regenerate after relevant release/catalog changes:

```powershell
godot --headless --path . --script tools/export_community_catalog.gd
```

Review and commit both outputs: `resources/community_catalog.json` and `supabase/functions/community/catalog.json`. Use an up-to-date saved YARD index. This API serves one manifest; simultaneous compatibility with multiple catalogs is not implemented.

## Steam identity and authentication

`scripts/autoloads/steam_client.gd` initializes GodotSteam, pumps callbacks, exposes local SteamID/persona/avatar and connection signals, and owns web-ticket handles. Project setting `steam/initialization/app_data/app_id` is currently `480`. Local profile information and successful initialization are not server-verified identity.

For every protected operation, the backend requests a fresh ticket with audience `marble-engineer-community`, sends its hex bytes, and releases the handle after HTTP completion. SteamClient matches callback handles, bounds ticket size, times out pending requests after 10 seconds, cancels on disconnect/tree exit, and expires delivered handles after 30 seconds. Tickets are not saved or logged.

`steam_auth.ts` calls Valve's `AuthenticateUserTicket` over HTTPS at `api.steampowered.com`, using server secrets `STEAM_APP_ID` and `STEAM_WEB_API_KEY` and the same audience. It accepts only a successful response containing a string SteamID64. It never trusts a client-supplied SteamID or creator label. Valve documents user-key support at this public endpoint; publisher credentials and the partner endpoint have distinct requirements. See [Valve's API reference](https://partner.steamgames.com/doc/webapi/ISteamUserAuth) when selecting release credentials.

Protected Steam operations use the verified SteamID for explicit database owner filtering. They create no Supabase Auth account or persistent custom session. Malformed/rejected Steam tickets do not fall back to email. If Steam is initialized, the client selects automatic authentication and hides email controls even while disconnected. Without Steam initialization, it supports an existing email/password account; the server verifies the bearer token with `auth.getUser` and rejects anonymous users. There is no signup, password recovery, account linking, or ownership transfer UI.

Verification has an 8-second upstream timeout, no redirects, and per-isolate limits of four concurrent requests, 60 attempts/minute, and a one-second cooldown per ticket digest. These are not distributed quotas. Public routes do not trigger ticket verification.

AppID 480 is development configuration. A locally obtained ticket—or even a successful development verification—does not establish release-AppID authentication or a complete publish/download/play/unpublish workflow. Verify that workflow with authorized release credentials before shipping.

## Database

The two migrations under `supabase/migrations/` define `community_puzzles`, immutable `community_revisions`, and the service-only `community_publish` RPC. The ownership migration adds nullable `steam_owner_id`, makes the existing UUID `owner_id` nullable, and requires exactly one owner identity. Existing email ownership is preserved; it is not transferred to Steam.

Both tables enable RLS. Public roles have SELECT only: published reads and UUID owners' private reads use policies. Direct client writes and publication RPC execution are revoked. The RPC is `SECURITY INVOKER` with an empty search path and service-role-only execution. Steam private reads/mutations use the privileged server client with explicit verified-owner filters.

Publication locks per owner, rejects stale/conflicting revisions, and allows identical latest-revision republication. Storage is bounded to 50 puzzle identities per owner and 100 revisions per puzzle. New identities check recent publications across the owner; updates check the same puzzle's 30-second interval. This is not a uniform account-wide cooldown for every revision update.

## Setup and deployment

Use the checked-in `supabase/config.toml`, migrations, Edge source, import map, and lockfile. The Edge dependency is pinned to `@supabase/supabase-js@2.95.3`. Install Supabase CLI and Deno separately; inspect their `--version` and command `--help` output before use. The commands below follow the [Supabase CLI reference](https://supabase.com/docs/reference/cli/introduction) and [deployment guide](https://supabase.com/docs/guides/functions/deploy); they are not a record of deployment performed during this documentation audit.

For an isolated local stack (requires Docker):

```powershell
supabase start
supabase db reset --local
supabase test db
supabase functions serve community
```

Reset only a disposable local database. `supabase/tests/database/community.test.sql` uses rolled-back fixtures; never run it on production. Configure the client with that stack's localhost URL and publishable key. Legacy anon JWT keys are rejected by this addon. Localhost HTTP is accepted only by editor builds. Local and hosted Auth settings are separate; use an existing email/password account for fallback tests.

For hosted deployment, authenticate the CLI separately, link the intended project, and review migration history/drift before applying changes:

```powershell
supabase link --project-ref <project-ref>
supabase db push --dry-run
# Apply only the reviewed migrations to the intended project:
supabase db push
supabase functions deploy community --project-ref <project-ref>
```

`[functions.community] verify_jwt = false` permits public browsing without a user JWT. Protected handlers verify Steam tickets or Supabase Auth themselves. Runtime configuration reads `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEYS`, and `SUPABASE_SECRET_KEYS` (the `default` entries), with legacy `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` fallback. Configure Steam secrets only on the server. For password fallback, enable email authentication and provision a verified password account. Never place privileged keys or credentials in exported configuration.

## Verification

Run local Edge checks from their directory:

```powershell
Push-Location supabase/functions/community
deno task check
deno task test
Pop-Location
```

The tests mock database/Auth/Valve calls; they verify validators, route/owner enforcement, and failure handling, not hosted authentication. Database tests additionally need the isolated local stack. Godot suites include `test_community_service.gd`, `test_community_ui.gd`, `test_steam_community.gd`, and `test_supabase_client.gd`; run them through the normal GUT command in the [README](../README.md#development).

Live GUT checks are opt-in: `MARBLE_ENGINEER_LIVE_COMMUNITY_TEST=1` enables hosted public browsing; `MARBLE_ENGINEER_LIVE_STEAM_TEST=1` requests/cancels a real Steam ticket; `MARBLE_ENGINEER_LIVE_STEAM_BACKEND_TEST=1` verifies tickets through owned listings. Set flags only for the intended environment with Steam running where required. Ordinary tests do not require live service access.

Before release, verify public browsing, authentication, tested-puzzle publication, retrieval/installation, actual play, unpublishing, and unauthenticated/other-owner denial. Also verify offline play. This documentation audit did not inspect hosted migrations, function versions, secrets, account state, or live content, and did not repeat historical development-authentication checks. Hosted status and production readiness must be verified independently.
