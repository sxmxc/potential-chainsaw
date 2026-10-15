# Community puzzle service

The initial provider is the hosted Supabase project `oxxajndhxzudvzlqfgng`. Source is in `supabase/`; the Godot application depends on `CommunityService`, rather than Supabase tables or Auth response formats. The community migration and Edge Function version 1 were deployed with owner approval. Public browsing works through the real Godot client; unauthenticated management requests return HTTP 401. The signed-in publication/download/play/unpublish workflow still needs email Auth configuration and a real sign-in.

## Client and persistence

`scripts/community/community_service.gd` exposes asynchronous browse, get, download, publish, unpublish, owned-listing, email/password sign-in and sign-out methods. Call each with `await`. Results are `{ok: bool, data: Dictionary, error: {code, message}}`; successful results have an empty error. `configure(store, adapter)` attaches the selected provider. Replacing Supabase requires an adapter implementing these same operations and `authentication_changed`/`is_signed_in`, and changing its construction in GameManager. No general HTTP framework or additional gameplay engine is involved.

The portable [SupabaseClient addon](../addons/supabase_client/README.md) owns HTTP and Auth. Copy that folder and enable the plugin to reuse it in another Godot project; its code has no game dependencies, game configuration or community routes. `SupabaseCommunityBackend` uses the plugin-provided autoload and maps this game's routes and API-v1 envelope. The client uses a separate `HTTPRequest` per operation, a maximum of eight concurrent requests, 20-second timeouts, disabled redirects and a 5 MB decompressed-response/body limit. Authentication refresh is serialized and authenticated requests retry once after expiration. Sign-out clears local tokens even if revocation fails. Tokens are never persisted to `user://`, configuration, logs or puzzle files. The browser ignores results after closure; an already-submitted publication or download may finish, but cannot unexpectedly open gameplay after its window closes.

`addons/supabase_client/supabase.cfg` contains only the project URL and public **publishable** key. The addon loads it directly; consuming game code does not read or reconfigure these values. Ordinary exports require HTTPS; editor builds also permit localhost HTTP for local development. Never put a secret key, service-role key, access token or database password here. The public publishable key identifies the project, not a creator.

Downloads call `PuzzleStore.install_community`; JSON import calls that same function. The shared decoder strips forged provenance/registration, verifies registered assets and the solution against existing rules, rejects conflicting identities and writes the community library. Campaign registration/progression stays separate. Online downloaded IDs have the form `community-<server UUID>-r<revision>`, so different revisions coexist and retain separate completion records. Local author IDs and existing files are preserved.

## API v1

Base path: `/functions/v1/community/v1`. Every handler response is `{api_version: 1, ok, data, error}`. Public requests send the publishable key as `apikey`. Authenticated requests additionally send `Authorization: Bearer <user access token>`.

| Route | Access | Result |
| --- | --- | --- |
| `GET /puzzles?search=&offset=0&compatibility=<catalog>` | Public | Metadata only, 20 rows and nullable `next_offset` |
| `GET /puzzles/<uuid>?revision=1&compatibility=<catalog>` | Public | One published puzzle revision |
| `POST /puzzles` with `{puzzle, compatibility}` | Signed-in email account | Server UUID, revision, share code `<uuid>@<revision>` |
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
3. No email-template or SMTP changes are needed to sign in with an already verified account and password. Steam integration is future work.
4. Ensure the runtime key maps are present under **Edge Functions > Secrets**. The public client key is already configured for this project; rotate/update it there and in the build configuration if needed.

After deployment, verify public browse; sign in with an existing account and password; publish an existing tested puzzle; retrieve/install it; run it through normal gameplay; unpublish as owner; verify unauthenticated and other-owner mutation denial; verify invalid server submissions; verify local/offline play. Clean up the representative test publication by unpublishing it. Do not describe the integration as operational until this workflow succeeds.

## Deployment verification

The recorded hosted migration version is `20261015002733`; the local migration filename matches it so subsequent CLI pushes do not reapply it. Function `community` version 1 is active. Supabase security advisors reported no findings. Both community tables have RLS enabled; anonymous/authenticated direct writes and publication RPC access are denied. The server role alone can call the publication function.

Live HTTP checks passed: public browse returned API-v1 metadata with HTTP 200; owned listings, publish and unpublish without a user session returned HTTP 401. The opt-in GUT live check also passed through `SupabaseClient` and `CommunityService` over HTTPS. Run that check explicitly with `MARBLE_ENGINEER_LIVE_COMMUNITY_TEST=1` and `-gselect=community_service`; ordinary tests keep networking optional.

Real-account password sign-in and the authenticated representative workflow remain unverified. No test publications were created during deployment. The CLI dry run could not run because the CLI has no access token; deployment used the authenticated MCP connection and repository source.
