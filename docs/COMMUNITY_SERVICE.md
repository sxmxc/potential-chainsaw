# Community service and Steam authentication

The community service adds online discovery, revision downloads, publication, owned listings, and unpublishing. Local building, campaign play, and JSON sharing work independently. Downloads become local puzzles and remain installed if their author later unpublishes them.

This guide is for developers maintaining the integration or deploying its backend. For the player-facing publication workflow, use [Puzzle authoring](PUZZLE_AUTHORING.md#share-a-community-puzzle). For generic Godot HTTP and password sessions, use the [SupabaseClient README](../addons/supabase_client/README.md).

## Follow a puzzle through the service

GameManager creates `CommunityService` with the session's PuzzleStore and a `SupabaseCommunityBackend`. The UI asks for a game operation, such as downloading a revision. The adapter turns it into an HTTP request, interprets the API response, and returns a game-facing result. The service then installs the definition through `PuzzleStore.install_community()`, the same validation/storage path used by JSON imports.

Publication follows the reverse boundary. The service checks local publication proof, strips campaign registration, and submits playable content. The backend validates that content and writes it for a verified owner. It does not run Godot physics. The saved successful test establishes the author's local run; server validation establishes an accepted data shape and catalog contract.

Keep provider tables, Auth responses, and game routes out of gameplay/UI code. The adapter owns that translation; the reusable addon owns transport and password sessions. Ordinary startup and local gameplay make no community HTTP requests. Steam initializes separately at startup.

### Game-facing operations

Await these methods on `CommunityService`:

| Method | Result or effect |
| --- | --- |
| `browse_puzzles(filters = {})` | Search/paginate public metadata |
| `get_puzzle(puzzle_id, revision)` | Fetch a compatible published definition |
| `download_puzzle(puzzle_id, revision)` | Fetch and install through PuzzleStore |
| `publish_puzzle(puzzle)` | Check proof and submit playable content |
| `get_my_puzzles(filters = {})` | List owned entries, including unpublished ones |
| `unpublish_puzzle(puzzle_id)` | Remove online availability |
| `sign_in(email, password)` / `sign_out()` | Manage the fallback password session |

Results are `{ok: bool, data: Dictionary, error: Dictionary}`. Success has an empty error; failure contains `error.code` and `error.message`. Use `authentication_changed`, `is_signed_in()`, and `uses_automatic_auth()` to update UI. A replacement adapter must provide the same operations and authentication contract; GameManager selects its construction.

The online panel is embedded in PuzzleBrowser. Closing it invalidates pending UI results, but an already submitted request can finish. Treat closing as presentation cancellation, not a promise that a publication was cancelled on the server.

## Steam identity and authentication

Local Steam profile information is presentation, not verified ownership. `SteamClient` initializes GodotSteam, pumps callbacks, exposes profile/connection signals, and owns web-ticket handles. The server establishes identity separately for each protected operation.

When Steam is initialized, the adapter requests a fresh web ticket for audience `marble-engineer-community`, sends its hex bytes as `x-steam-ticket`, and releases the handle after HTTP completion. SteamClient matches callback handles, bounds ticket size, times out pending requests after 10 seconds, and cancels on disconnect/tree exit. Delivered handles expire after 30 seconds even if a caller disappears. Tickets are neither saved nor logged.

`supabase/functions/community/steam_auth.ts` verifies the ticket over HTTPS with Valve's `AuthenticateUserTicket`, using server secrets `STEAM_APP_ID` and `STEAM_WEB_API_KEY` and the same audience. Only a successful response containing a string SteamID64 is accepted. The client cannot establish ownership by supplying a SteamID or creator label.

The implementation calls `api.steampowered.com`, where Valve documents Web API user-key support. The partner endpoint requires publisher credentials. Select release credentials and endpoint together using [Valve's API reference](https://partner.steamgames.com/doc/webapi/ISteamUserAuth); the two credential paths are not interchangeable.

A verified SteamID is used for explicit database owner filtering. No Supabase Auth user or persistent custom Steam session is created. Verification has an eight-second upstream timeout and rejects redirects. Per isolate, it allows four concurrent requests, 60 attempts per minute, and a one-second cooldown per ticket digest. These bounds are not distributed quotas. Public browsing/download routes do not verify tickets.

If Steam is initialized, automatic authentication stays selected even while disconnected, and email controls remain hidden. A malformed or rejected ticket does not fall back to another account. Without Steam initialization, the client supports an existing email/password account; protected handlers verify its bearer token with `auth.getUser()` and reject anonymous users. There is no signup, recovery, account linking, or ownership-transfer UI. Email-owned publications remain owned by their existing UUID account.

The configured client AppID is **480**, for development. Before release, configure the release AppID and authorized server credentials, then verify the complete publish/download/play/unpublish workflow. A successful development-ticket check does not establish release authentication.

## API v1

The base path is `/functions/v1/community/v1`. Responses use `{api_version: 1, ok, data, error}`. Requests send the public project key in `apikey`; protected calls also send either `x-steam-ticket` or a Supabase user bearer token.

| Route | Access and behavior |
| --- | --- |
| `GET /puzzles?search=&offset=0&compatibility=<digest>` | Public; up to 20 metadata rows and nullable `next_offset` |
| `GET /puzzles/<uuid>?revision=1&compatibility=<digest>` | Public; one published compatible revision |
| `POST /puzzles` with `{puzzle, compatibility}` | Verified owner; returns UUID, revision, and `<uuid>@<revision>` share code |
| `GET /mine?search=&offset=0` | Verified owner; includes unpublished entries |
| `DELETE /puzzles/<uuid>` | Owner only; removes availability of all revisions |

`index.ts` owns routing, ownership, and persistence. `validation.ts` checks allowed fields, types/ranges, catalog dependencies, configuration, ports/links, objectives, and compatibility. Publication is limited to 5 MB and requires a saved solution and successful-test record. Client-side proof and solution-rule checks remain necessary: server validation cannot reproduce the run.

Downloads receive local IDs of `community-<server UUID>-r<revision>`. This gives each immutable online revision independent completion records. Unpublishing hides server availability rather than deleting installed copies.

### Keep the catalog contract in step

The compatibility digest covers the release version and catalog metadata exported from the saved registry, scene settings, surface-mount capability, and actual port declarations. Mounted pieces use only registered construction UIDs and validated orthonormal orientation metadata; the server rejects missing targets, accessory cycles, and mount fields on ordinary pieces. It is not a hash of every physics or model dependency. After relevant release/catalog changes, first ensure YARD's saved index is current, then run:

```powershell
godot --headless --path . --script tools/export_community_catalog.gd
```

Review and commit both outputs: `resources/community_catalog.json` for the game and `supabase/functions/community/catalog.json` for the server. Deploy the matching server manifest with the client release. The API serves one manifest; simultaneous compatibility with multiple catalogs is not implemented.

## Database ownership and publication

The migrations under `supabase/migrations/` define `community_puzzles` for publication metadata and `community_revisions` for immutable definitions. A row has exactly one owner: a Supabase UUID in `owner_id` or a SteamID in `steam_owner_id`. The Steam migration preserves existing UUID ownership.

Both tables enable RLS. Public roles have SELECT access only, restricted by published-read and UUID-owner policies; direct client writes are revoked. Steam private reads and mutations use a privileged server client with explicit verified-owner filters. Keep those filters on every such operation because the privileged client bypasses ordinary RLS protections.

The service-only `community_publish` RPC uses `SECURITY INVOKER` and an empty search path. It locks per owner, rejects stale/conflicting revisions, and permits identical latest-revision republication. Storage is bounded to 50 puzzle identities per owner and 100 revisions per puzzle. New identities check recent publications across the owner; revision updates check the same puzzle's 30-second interval. This is not an account-wide cooldown for every update.

## Set up a local backend

Install Supabase CLI, Deno, and Docker separately. Check installed versions and command help before use; the repository includes Supabase configuration, migrations, Edge source, import map, and lockfile. The Edge dependency is pinned to `@supabase/supabase-js@2.95.3`.

From the repository root, start a disposable local stack:

```powershell
supabase start
supabase db reset --local
supabase test db
supabase functions serve community
```

Reset discards the local database and reapplies migrations. Use it only for a disposable stack. The database tests in `supabase/tests/database/community.test.sql` use rolled-back fixtures and must never run against production.

Configure `addons/supabase_client/supabase.cfg` with this stack's localhost URL and an `sb_publishable_` key, following the [addon setup](../addons/supabase_client/README.md#install-and-configure). The addon rejects legacy anon JWT keys and accepts localhost HTTP only in editor builds. For password tests, provision an existing account; local and hosted Auth settings are separate. Real Steam verification additionally needs authorized server-side Steam secrets.

## Deploy the service

Authenticate the CLI for the intended project, confirm its migration history/drift, and preview the pending migrations before applying them. These commands follow the [Supabase CLI reference](https://supabase.com/docs/reference/cli/supabase-db-push) and [Edge deployment guide](https://supabase.com/docs/guides/functions/deploy):

```powershell
supabase link --project-ref <project-ref>
supabase db push --dry-run
```

After reviewing that project and migration set:

```powershell
supabase db push
supabase functions deploy community --project-ref <project-ref>
```

`[functions.community] verify_jwt = false` allows public browsing without a user JWT. Protected handlers perform their own Steam/Auth verification; do not remove those checks when changing gateway configuration.

Runtime configuration reads `SUPABASE_URL`, the `default` entries of `SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_SECRET_KEYS`, or legacy `SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_ROLE_KEY` fallbacks. Configure `STEAM_APP_ID` and `STEAM_WEB_API_KEY` on the server only. For password fallback, enable email authentication and provision a verified password account.

The exported game needs the project URL and public publishable key, with `addons/supabase_client/*.cfg` included in the export preset. It must never contain a secret key, service-role credential, database password, or Steam Web API key.

## Verification

Run Edge type checks and mocked tests from their directory:

```powershell
Push-Location supabase/functions/community
deno task check
deno task test
Pop-Location
```

These tests cover validation, route/owner enforcement, and Auth/Valve failure handling with mocked providers. Database tests require the isolated local stack. `test_community_service.gd` and `test_supabase_client.gd` use fakes and a local HTTP server through the [normal GUT runner](../README.md#development).

For a release, inspect hosted migrations, function version, secrets, and Auth settings, then exercise public browsing, authenticated publication of a tested puzzle, retrieval/installation, actual play, and unpublishing. Check unauthenticated and other-owner denial, and verify offline play. Automated mocked tests cannot establish hosted configuration or release-AppID authentication.
