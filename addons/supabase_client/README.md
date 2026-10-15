# SupabaseClient for Godot

A small native Godot JSON/HTTPS client with Supabase email/password authentication and memory-only sessions. It can call project-relative Data API, RPC, and Edge Function endpoints. It is not a query builder or a full Storage/Realtime SDK.

## Install and configure

Copy `addons/supabase_client/` into your project and enable **Supabase Client** under **Project Settings → Plugins**. The plugin registers the `SupabaseClient` autoload; disabling it removes that registration. The addon has no dependency on other addons or application schemas.

Requirements: Godot 4 with GDScript. The client has been checked with Godot 4.7.2; earlier minor versions are not verified and the plugin declares no minimum version.

Create `supabase.cfg` beside `supabase_client.gd`, using `supabase.cfg.example`:

```ini
[supabase]
url="https://your-project.supabase.co"
publishable_key="sb_publishable_your_key"
```

At `_ready()`, the client loads that file. Include `addons/supabase_client/*.cfg` in the export preset's non-resource filter. For a runtime override, call `SupabaseClient.configure(url, key)` after the node is ready; this also clears the current session. A manually instantiated script node must enter the scene tree before making requests.

Only keys starting with `sb_publishable_` are accepted; legacy anon JWT keys are unsupported. HTTPS is required except `http://localhost:<port>` and `http://127.0.0.1:<port>` in editor builds. Publishable keys identify a project and are safe to distribute; they do not grant user identity. Never ship a secret/service-role key or database password.

## JSON requests

```gdscript
func load_items() -> void:
    var result: Dictionary = await SupabaseClient.request(
        "/rest/v1/items?select=id,name&limit=10"
    )
    if result.ok:
        print(result.data) # Array for this Data API query.
    else:
        push_warning(result.error.message)
```

The example assumes your project exposes an `items` table and permits the requested read. Configure database grants and RLS independently; this client does not create tables or policies.

`request(path, method = HTTPClient.METHOD_GET, body = null, authenticated = false, headers = {})` accepts a project-relative path beginning with a single `/`. Supply query parameters yourself, encoding values with `uri_encode()`. Bodies are JSON-serialized; responses may be objects, arrays, or scalars. A successful empty response returns `{}`. Binary/file transfer and streaming are unsupported.

Edge Functions use the same result convention:

```gdscript
func submit_feedback(message: String) -> Dictionary:
    return await SupabaseClient.invoke_function(
        "feedback", {"message": message}, HTTPClient.METHOD_POST, true
    )
```

`invoke_function(function_name, body = null, method = HTTPClient.METHOD_POST, authenticated = false, relative_path = "", headers = {})` builds `/functions/v1/<name>[/<relative_path>]`. This example assumes a deployed function and a signed-in session. The client does not interpret application-specific response envelopes.

Both methods accept custom text headers as their last argument. The client reserves Authorization, apikey, JSON Content-Type, and transport headers. Invalid names, line breaks in values, or more than 16 KB of custom headers fail locally. Custom headers persist through an authenticated retry; they do not create an Auth session.

## Authentication and sessions

Await `sign_in_with_password(email, password)` with an existing account. Check its result before making requests with `authenticated = true`. `sign_out()` clears local tokens immediately, then attempts server revocation. A revocation failure returns `sign_out_local`; the device remains signed out. `clear_session()` clears local state without a server request.

`is_signed_in()` means a refresh token exists locally, not that the server has just validated the user. Authenticated requests refresh within 60 seconds of expiry and retry once after HTTP 401. Concurrent refreshes share one operation. `refresh_session()` is also callable explicitly. Invalid refresh credentials clear the session; transient failures return an error.

Connect `authentication_changed` to refresh application UI; it also fires on session refresh. Session generations discard results when sign-in/configuration/sign-out changes the session during a request. Tokens remain in memory only; the addon does not persist them or provide OS credential storage. Auth helpers sanitize responses and return no tokens; the node's token fields are still accessible to application code.

Signup, email-code/OTP login, password recovery, OAuth/browser callbacks, and automatic session restoration are not implemented.

## Results, limits, and security

Awaited operations return `{ok, data, error, status}`. On success, `error` is empty. On failure it contains `code` and `message`. `status` is the HTTP status, or zero for local/transport failures. HTTP failures retain parsed response JSON in `data`; invalid JSON returns `invalid_response`. Common codes include `unavailable`, `invalid_request`, `busy`, `too_large`, `network`, `timeout`, `sign_in_required`, `rate_limit`, and `http_error`.

Default exported limits are eight concurrent requests, 20 seconds per request, and 5,000,000 bytes for request/response bodies. Redirects are disabled. There is no request queue, general retry/backoff policy, or public cancellation API. Keep the client alive while requests are pending; closing UI should discard stale results rather than destroy the client.

Use authenticated requests and server-side authorization/RLS for private operations. Avoid logging credentials, tokens, or raw Auth/API bodies. Direct low-level `request_http` calls bypass session orchestration; ordinary application calls should use `request`, `invoke_function`, and the Auth helpers.
