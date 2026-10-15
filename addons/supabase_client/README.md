# SupabaseClient for Godot

SupabaseClient is a native Godot addon for JSON requests and email/password authentication. Use it to call a Supabase project's Data API, database RPCs, or Edge Functions from GDScript. It provides memory-only sessions and authenticated request handling; it does not include a query builder, Storage file transfer, or Realtime subscriptions.

## Install and configure

Copy `addons/supabase_client/` into a Godot 4 project and enable **Supabase Client** in **Project Settings → Plugins**. The plugin registers the `SupabaseClient` autoload; disabling the plugin removes it. No other addon or application schema is required. The plugin declares no minimum Godot minor version.

Create `supabase.cfg` beside `supabase_client.gd`, using the supplied `supabase.cfg.example`:

```ini
[supabase]
url="https://your-project.supabase.co"
publishable_key="sb_publishable_your_key"
```

The client reads this file at `_ready()`. Include `addons/supabase_client/*.cfg` in the export preset's non-resource include filter. To configure at runtime, call `SupabaseClient.configure(url, key)` after the node is ready. Reconfiguration clears the current session. You can also instantiate the script yourself, but it must enter the scene tree before requests are made.

Only `sb_publishable_` keys are accepted; legacy anon JWT keys are unsupported. HTTPS is required, with an exception for `http://localhost:<port>` and `http://127.0.0.1:<port>` in editor builds. A publishable key identifies the application, not a signed-in user. Keep secret/service-role keys and database passwords on the server. See [Supabase's key guide](https://supabase.com/docs/guides/getting-started/api-keys) for the distinction.

## Make a public request

Requests use project-relative paths and return a result dictionary. This example assumes an `items` table with `id` and `name` columns and a policy/grant allowing the read:

```gdscript
func load_items(search: String) -> void:
    var path := "/rest/v1/items?select=id,name&limit=10"
    path += "&name=eq." + search.uri_encode()
    var result: Dictionary = await SupabaseClient.request(path)
    if result.ok:
        print(result.data)
    else:
        push_warning(result.error.message)
```

Supply and encode query parameters yourself. The addon does not create tables, grants, or row-level security policies. Public requests send the configured `apikey` and no user bearer token.

The general call is:

```gdscript
request(path, method = HTTPClient.METHOD_GET, body = null,
        authenticated = false, headers = {})
```

The path must begin with one `/`. A non-null body is JSON-serialized; successful responses can be objects, arrays, or scalars. A successful empty response returns `{}`. The same method can call an RPC path such as `/rest/v1/rpc/your_function` with POST and a JSON arguments dictionary.

## Sign in and call a private endpoint

Use an existing password account. Signup, email-code/OTP login, recovery, OAuth callbacks, and automatic session restoration are not implemented.

```gdscript
func load_private_items(email: String, password: String) -> Dictionary:
    var signed_in: Dictionary = await SupabaseClient.sign_in_with_password(
        email, password
    )
    if not signed_in.ok:
        return signed_in
    return await SupabaseClient.request(
        "/rest/v1/items?select=id,name",
        HTTPClient.METHOD_GET, null, true
    )
```

Setting `authenticated = true` requires a local session and sends its access token. The server must still authorize the operation through grants, RLS, or function logic. `is_signed_in()` means a refresh token exists locally; it is not a fresh server identity check.

Authenticated requests refresh within 60 seconds of expiry and retry once after HTTP 401. Concurrent refreshes share one operation. You can also await `refresh_session()` explicitly. Rejected refresh credentials clear the session; transient failures return an error. There is no general retry/backoff policy.

Connect `authentication_changed` to update account controls. It fires when sessions are cleared, accepted, or refreshed. Requests discard stale results when configuration or session changes make them obsolete. Tokens stay in memory and are lost when the client exits. Auth helpers sanitize their results and do not return tokens, although application code can access the node's token fields.

Await `sign_out()` when the user signs out. It clears local tokens immediately and then attempts server revocation. If revocation fails, the result is `sign_out_local` and the device remains signed out. `clear_session()` clears local state without contacting the server. Neither method adds secure storage or guarantees the immediate invalidation of every previously issued access token.

## Invoke an Edge Function

`invoke_function()` builds the function URL and uses the same transport and session handling:

```gdscript
func submit_feedback(message: String) -> Dictionary:
    return await SupabaseClient.invoke_function(
        "feedback", {"message": message}, HTTPClient.METHOD_POST, true
    )
```

This assumes a deployed `feedback` function and an existing session. The call signature is:

```gdscript
invoke_function(function_name, body = null,
                method = HTTPClient.METHOD_POST, authenticated = false,
                relative_path = "", headers = {})
```

`relative_path` appends a route beneath `/functions/v1/<function_name>/`. Choose `authenticated` to match the function's authentication requirements. The addon returns parsed JSON without interpreting an application-specific envelope. An HTTP success containing your own `{ok: false}` is still a transport success; your application must inspect that payload.

Both request methods accept a dictionary of custom text headers. Authorization, apikey, Content-Type, and transport headers are reserved. Invalid names, line breaks in values, or custom headers totaling more than 16 KB fail locally. Custom headers survive an authenticated retry and do not create an Auth session.

## Handle failures and request limits

Every awaited operation returns `{ok, data, error, status}`. Success has an empty error. Failure has `error.code` and `error.message`; `status` is an HTTP status or zero for a local/transport failure. HTTP failures retain parsed JSON in `data`, so do not log raw response bodies indiscriminately. Invalid JSON produces `invalid_response`.

Handle `sign_in_required` by asking for authentication, `busy` by allowing the user to try again when requests finish, and `rate_limit` with an appropriate delay. `unavailable` commonly indicates missing/invalid configuration; `network` and `timeout` indicate transport failure. Auth helpers deliberately sanitize provider errors.

The exported defaults are eight concurrent requests, a 20-second timeout, and 5,000,000-byte request/response limits. Redirects are disabled. There is no queue, public cancellation API, binary transfer, or streaming. Keep the client alive while operations are pending; a closing screen should ignore its stale results rather than destroy the client.

Use `request()`, `invoke_function()`, and the Auth helpers for normal application calls. Low-level `request_http()` bypasses session orchestration. Avoid logging passwords, tokens, or raw Auth bodies, and enforce authorization on the server even when the UI already restricts an action.
