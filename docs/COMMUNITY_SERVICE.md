# Community puzzle service

The initial provider is the hosted Supabase project `oxxajndhxzudvzlqfgng`. Source is in `supabase/`; the Godot application depends on `CommunityService`, rather than Supabase tables or Auth response formats. The community and Steam ownership migrations are deployed with owner approval; Edge Function version 3 is active. Public browsing and real Steam ticket verification work through the Godot client. Steam-owned publication/download/play/unpublish remains untested against the hosted service; the verification performed no content mutations.

## Client and persistence

`scripts/community/community_service.gd` exposes asynchronous browse, get, download, publish, unpublish, owned-listing, email/password sign-in and sign-out methods. Call each with `await`. Results are `{ok: bool, data: Dictionary, error: {code, message}}`; successful results have an empty error. `configure(store, adapter)` attaches the selected provider. Replacing Supabase requires an adapter implementing these same operations and `authentication_changed`/`is_signed_in`, and changing its construction in GameManager. No general HTTP framework or additional gameplay engine is involved.

The portable [SupabaseClient addon](../addons/supabase_client/README.md) owns HTTP and Auth. Copy that folder and enable the plugin to reuse it in another Godot project; its code has no game dependencies, game configuration or community routes. `SupabaseCommunityBackend` uses the plugin-provided autoload and maps this game's routes and API-v1 envelope. The client uses a separate `HTTPRequest` per operation, a maximum of eight concurrent requests, 20-second timeouts, disabled redirects and a 5 MB decompressed-response/body limit. Supabase Auth refresh is serialized and authenticated requests retry once after expiration. Sign-out clears local tokens even if revocation fails. Tokens are never persisted to `user://`, configuration, logs or puzzle files. The browser ignores results after closure; an already-submitted publication or download may finish, but cannot unexpectedly open gameplay after its window closes.

`addons/supabase_client/supabase.cfg` contains only the project URL and public **publishable** key. The addon loads it directly; consuming game code does not read or reconfigure these values. Ordinary exports require HTTPS; editor builds also permit localhost HTTP for local development. Never put a secret key, service-role key, access token or database password here. The public publishable key identifies the project, not a creator.

Downloads call `PuzzleStore.install_community`; JSON import calls that same function. The shared decoder strips forged provenance/registration, verifies registered assets and the solution against existing rules, rejects conflicting identities and writes the community library. Campaign registration/progression stays separate. Online downloaded IDs have the form `community-<server UUID>-r<revision>`, so different revisions coexist and retain separate completion records. Local author IDs and existing files are preserved.

## API v1

Base path: `/functions/v1/community/v1`. Every handler response is `{api_version: 1, ok, data, error}`. Public requests send the publishable key as `apikey`. Authenticated requests additionally send `Authorization: Bearer <user access token>`.

| Route | Access | Result |
| --- | --- | --- |
| `GET /puzzles?search=&offset=0&compatibility=<catalog>` | Public | Metadata only, 20 rows and nullable `next_offset` |
| `GET /puzzles/<uuid>?revision=1&compatibility=<catalog>` | Public | One published puzzle revision |
| `POST /puzzles` with `{puzzle, compatibility}` | Verified Steam ticket or signed-in email account | Server UUID, revision, share code `<uuid>@<revision>` |
| `GET /mine?search=&offset=0` | Signed in | Owned metadata, including unpublished items |
| `DELETE /puzzles/<uuid>` | Owner | Unpublishes all downloadable revisions; installed copies survive |

Publication accepts the game's existing JSON format. Validation rejects unsupported fields, scene/script paths, unregistered assets, invalid setting types/ranges, invalid link references/ports, objectives, permissions, bounds, camera fields, or unsupported catalog/version values. It checks that a preserved solution and successful test record are present; it does **not** prove physics success or a working solution. Game-side publication and downloaded-solution validation remain in force.

The catalog manifest is generated exclusively from YARD's authoritative saved registry, scene-authored settings and live mechanism port declarations:

```powershell
godot --headless --path . --script tools/export_community_catalog.gd
```

Commit both generated outputs: `resources/community_catalog.json` and `supabase/functions/community/catalog.json`. Regenerate after changing the game release version, catalog membership, mechanism ports or configuration constraints, using an up-to-date saved registry. The compatibility digest covers the release version and manifest. A compatibility change intentionally requires the corresponding game and server versions; supporting multiple releases is outside this first version.

## Database and security

`community_puzzles` stores ownership and latest listing metadata. `community_revisions` stores immutable JSON revisions. Ownership comes from server-side `Auth.getUser`, not uploaded creator text. The server rejects anonymous Auth users. RLS permits published reads and owners' private reads. `anon` and `authenticated` have SELECT only; direct writes and direct publication RPC execution are revoked, preventing clients from bypassing structural validation. The Edge Function uses a server-only privileged client for the publication RPC and an owner-filtered unpublish update.

The publication RPC is `SECURITY INVOKER`, executable only by `service_role`, with an empty search path. It locks each creator's transaction, preserves revision content, rejects conflicting/stale revisions, and bounds storage at 50 puzzle identities per account and 100 revisions per puzzle. New publications have a 30-second account interval. Republish of an identical latest revision is idempotent. Public browsing is paginated and excludes definitions. Auth rate limits are managed by Supabase; no ratings, profiles or social systems are added.

## Local checks

Validated tooling: Godot 4.7.2, GUT 9.7.1, Supabase CLI 2.121.0 and Deno 2.9.6. The Edge dependency is pinned and its Deno lockfile is included with the source.

```powershell
npx --yes supabase@2.121.0 start
npx --yes supabase@2.121.0 db reset --local
npx --yes supabase@2.121.0 test db
npx --yes supabase@2.121.0 functions serve community
godot --headless --path . --script addons/gut/gut_cmdln.gd -gselect=community -gexit
Push-Location supabase/functions/community
npx --yes deno@2.9.6 task check
npx --yes deno@2.9.6 task test
Pop-Location
```

The database stack requires Docker. `supabase/tests/database/community.test.sql` tests public, owner and other-user RLS and denied writes/RPC access inside a rolled-back fixture. Never run this fixture on production. For local development, set the localhost URL and local publishable key in the addon configuration; restore the hosted values before shipping. Use a local test account with an email and password. Local and hosted Auth configuration are separate.

## Hosted setup and deployment

The project was inspected through MCP before implementation: public tables, migrations and Edge Functions were empty. Recheck for drift before deploying. Obtain owner approval before applying the migration or deploying the function. No runtime game code runs migrations or deploys infrastructure.

For CLI deployment, authenticate the CLI independently from MCP, preferably using a project-scoped personal access token set outside source control. A database password may also be needed for linking/pushing. Inspect CLI `--help` when using a different version.

```powershell
npx --yes supabase@2.121.0 link --project-ref oxxajndhxzudvzlqfgng
npx --yes supabase@2.121.0 db push --dry-run --skip-vault
# Review the complete pending SQL; after approval:
npx --yes supabase@2.121.0 db push --skip-vault
npx --yes supabase@2.121.0 functions deploy community --project-ref oxxajndhxzudvzlqfgng --use-api
```

Do not use `--prune`, `db reset --linked`, or production seeds. The migration is additive and touches only the two community tables, indexes, policies and publication function. MCP `apply_migration` and `deploy_edge_function` can deploy the same reviewed source if CLI credentials are unavailable; preserve the source and recorded migration version in Git and reconcile remote migration history before subsequent CLI pushes.

`[functions.community] verify_jwt = false` allows unauthenticated browsing with modern publishable keys. Authenticated routes perform their own Auth verification; this flag does not grant publication access. The hosted runtime supplies `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEYS` and `SUPABASE_SECRET_KEYS`; the implementation supports legacy runtime server keys when the new injected maps are absent. These server credentials never ship with Godot. No custom application secret is required.

Manual Dashboard configuration:

1. Enable email sign-in in **Authentication > Providers > Email**. Anonymous sign-in is unnecessary and rejected by this API.
2. Use an existing verified email account with a password. The desktop game signs in through `/auth/v1/token?grant_type=password`. It has no signup or password-reset flow.
3. No email-template or SMTP changes are needed to sign in with an already verified account and password. Email/password remains a standalone fallback; Steam users use automatic ticket verification instead.
4. Ensure the runtime key maps are present under **Edge Functions > Secrets**. The public client key is already configured for this project; rotate/update it there and in the build configuration if needed.

After deployment, verify public browse; sign in with an existing account and password; publish an existing tested puzzle; retrieve/install it; run it through normal gameplay; unpublish as owner; verify unauthenticated and other-owner mutation denial; verify invalid server submissions; verify local/offline play. Clean up the representative test publication by unpublishing it. Do not describe the integration as operational until this workflow succeeds.

## Deployment verification

The recorded hosted migration versions are `20261015002733` and `20261015042117`; local filenames match them so subsequent CLI pushes do not reapply them. Function `community` version 3 is active. The current advisor reports only the existing leaked-password protection warning described below. Both community tables have RLS enabled; anonymous/authenticated direct writes and publication RPC access are denied. The server role alone can call the publication function.

Live HTTP checks passed: public browse returned API-v1 metadata with HTTP 200; owned listings, publish and unpublish without a user session returned HTTP 401. The opt-in GUT live check also passed through `SupabaseClient` and `CommunityService` over HTTPS. Run that check explicitly with `MARBLE_ENGINEER_LIVE_COMMUNITY_TEST=1` and `-gselect=community_service`; ordinary tests keep networking optional.

Real-account password sign-in and the authenticated representative workflow remain unverified. No test publications were created during deployment. The CLI dry run could not run because the CLI has no access token; deployment used the authenticated MCP connection and repository source.

## Steam community authentication

`SteamClient` still owns initialization, identity and callbacks. `request_web_ticket(identity)` awaits `get_ticket_for_web_api`, matches its handle, validates the result/size, and encodes only the returned bytes. It times out after 10 seconds; callers release handles after HTTP completion, including failures. Disconnect/shutdown cancel tickets, and delivered tickets have a 30-second safety lifetime. No ticket is persisted or logged. The identity badge is unchanged.

`SupabaseCommunityBackend` requests a fresh ticket for each publish, owned listing or unpublish operation and passes `x-steam-ticket` using the addon's generic header support. Its audience is `marble-engineer-community`, shared with the server. It does not send a SteamID or create a Supabase Auth account/session. Steam initialization alone never marks community authentication verified. The game-facing `uses_automatic_auth()` capability hides the email form for Steam users; failures appear only on affected actions. Public browse/download require neither Steam nor email login. Existing email/password remains available when Steam is not initialized.

The Edge Function calls Valve's HTTPS `ISteamUserAuth/AuthenticateUserTicket` endpoint with the server-configured AppID and fixed audience, and accepts only a successful result with a string SteamID64. It never uses a client-supplied ID or display name. Invalid tickets do not fall back to email. Steam-owned private reads and mutations use the server database client with an explicit verified-owner filter. No custom persistent sessions or registration system are introduced.

Server secrets required before hosted verification:

- `STEAM_APP_ID`: the AppID associated with the Steam API credential and ticket.
- `STEAM_WEB_API_KEY`: a Steam Web API user key for development, or an appropriate publisher key. User keys use Valve's public `api.steampowered.com` endpoint; the implementation now uses that endpoint, whose `AuthenticateUserTicket` method supports Web API user keys. Store it only in Supabase Edge Function secrets; never in Godot, the addon configuration, source control or logs.

The game already reads its AppID from `steam/initialization/app_data/app_id` in Project Settings (currently `480`). AppID 480 was sufficient to receive a real callback and ticket locally. It does not demonstrate verification with the configured server credentials. The current development setup uses AppID 480 and an account Web API key; validate that combination against Valve before claiming hosted authentication works. Use an authorized AppID/credential combination for release. No verification bypass is provided. See [Valve's authentication flow](https://partner.steamgames.com/doc/features/auth) and [AuthenticateUserTicket parameters](https://partner.steamgames.com/doc/webapi/ISteamUserAuth).

Verification rejects malformed/oversized ticket headers before contacting Valve, has an 8-second upstream timeout and disables redirects. Each Edge isolate permits at most four concurrent verifications and 60 attempts/minute, with a one-second cooldown per ticket digest. Memory is bounded; these controls are per isolate, not a distributed quota. Use gateway-wide rate limiting if traffic warrants it. Public endpoints never trigger Steam verification. Publication bodies remain limited to 5 MB and existing per-owner publication quotas remain in force.

### Ownership migration and deployment review

`supabase/migrations/20261015042117_steam_community_ownership.sql` was applied with explicit owner approval. It adds nullable `steam_owner_id` text, makes `owner_id` nullable, requires exactly one owner identity, adds Steam indexes, and updates the service-only publication RPC. Existing email UUIDs, foreign keys, puzzle IDs, revisions and definitions are preserved. No existing publication is assigned to Steam. Existing UUID-owner RLS read policies and denied direct client writes remain intact. Steam owners access private content only through verified Edge requests. Email owners can still manage their existing publications using the standalone password fallback; no account linking or data transfer is included.

Hosted inspection found one email-owned puzzle, one revision and one Auth user. The migration was applied before deploying function version 3 from repository source, including `steam_auth.ts`. The local migration filename was reconciled with the hosted migration-history version. Future changes to hosted records/permissions still require owner approval. `verify_jwt = false` is already configured and must stay that way: the handler verifies Steam tickets or Supabase Auth itself before any privileged request.

### Focused verification

- GUT covers automatic-auth UI behavior, ticket forwarding/cleanup on HTTP success and failure, public browsing without tickets, isolated password fallback and addon header validation.
- Set `MARBLE_ENGINEER_LIVE_STEAM_BACKEND_TEST=1` to run the read-only hosted ticket verification, invalid-ticket rejection and public-browse check. Set `MARBLE_ENGINEER_LIVE_STEAM_TEST=1` and run `-gselect=steam_community` with Steam running to obtain/cancel a real ticket without logging its contents.
- `deno task check` and `deno task test` cover Valve audience/AppID binding, string identity handling, malformed/rejected tickets, upstream failures, throttling, verified-owner publication/filtering and denied unpublishing for another owner. These use mocked upstream services, not hosted authentication.
- `supabase test db` additionally exercises ownership constraints, preserved email access, direct-write/RPC denial and independent Steam owners. Requires the isolated local Postgres/Docker stack; do not run fixtures on production.

Hosted read-only verification passed with AppID 480 and the account Web API key: a real ticket obtained through GodotSteam was accepted for `GET /mine`; a malformed ticket and a well-formed but unverifiable ticket were rejected; public browsing remained available. Ticket handles were released. Still pending: Steam-owned publication/retrieval/management and other-owner mutation denial against the hosted deployment. Those mutations remain covered by mocked backend tests, not a live publication test.

Verified locally on Godot 4.7.2 / GodotSteam 4.23.1: the actual game started with Steam running, the real ticket callback/cleanup test passed using AppID 480, live public browse passed, and isolated community/addon and Edge tests passed. The new SQL fixtures were not run because Docker/Postgres tools are unavailable. Hosted inspection after local work still found one puzzle, one revision and one Auth user; anonymous INSERT and authenticated UPDATE remain denied.

The current hosted security advisor reports [leaked-password protection disabled](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) for the existing password fallback. No Auth settings were changed by this task.

Development credential update: the owner has configured `STEAM_APP_ID=480` and an account Web API key in hosted secrets. The verifier now targets `api.steampowered.com`, because Valve documents Web API user-key support there; `partner.steam-api.com` is the publisher endpoint. No key is downloaded or exposed to Godot. The approved migration/deployment and read-only hosted verification are complete. No secrets were read back, and no puzzles were created, modified or unpublished during verification. The existing email-owned publication retained its exact original fields and revision-definition hash after deployment; its Steam owner remains null.
