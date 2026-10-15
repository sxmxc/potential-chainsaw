# SupabaseClient for Godot 4

Copy `addons/supabase_client/` into another Godot 4 project and enable **SupabaseClient** under Project Settings > Plugins. The plugin registers the `SupabaseClient` autoload; disabling it removes that registration. The plugin owns its configuration and has no dependency on Marble Engineer, other addons or particular Edge Functions.

```gdscript
var supabase = SupabaseClient

func _ready() -> void:
    var result := await supabase.invoke_function("your-function", null, HTTPClient.METHOD_GET)
    if result.ok:
        handle_data(result.data)
    else:
        show_error(result.error.message)
```

Use `await request(path, method, json_body, authenticated, headers)` for project-relative JSON endpoints. Methods are `HTTPClient.METHOD_*`; omit the body for GET. JSON objects, arrays and scalar values are supported, including Data API results. Results are `{ok, data, error, status}`; status is zero for local/transport failures. HTTP errors preserve parsed JSON in `data` for application-specific handling; the generic `error.message` contains no raw server data. Do not log response bodies or credentials. This is a small JSON client, rather than a complete Storage, Realtime or query-builder SDK.

Email/password Auth:

```gdscript
var result := await supabase.sign_in_with_password("player@example.com", password)
var private_result := await supabase.request("/functions/v1/private-function", HTTPClient.METHOD_POST, {"value": 1}, true)
await supabase.sign_out()
```

Auth operations sanitize provider responses and return no tokens. Tokens remain in memory until sign-out or node destruction. Authenticated requests share session refresh and retry once on HTTP 401. `authentication_changed` signals sign-in/sign-out; `is_signed_in()` reports whether a renewable session is present. Use an existing account with a password. Signup, password recovery, browser redirects, social sign-in and OS credential storage are outside this addon.

The client loads `supabase.cfg` beside its own script on startup. Set the project URL and publishable key there, or use the public `configure(url, key)` method when an explicit override is needed. Include this `.cfg` in your export preset. Environment overrides belong to the consuming project. The client accepts publishable keys, uses HTTPS, disables redirects, and permits localhost HTTP only in editor builds. Default limits are eight concurrent requests, 20 seconds per request and a 5 MB body/response; exported properties let projects adjust them. The autoload remains available for the application lifetime. A closing UI should discard stale results without destroying the client.

Both `request` and `invoke_function` accept an optional final header dictionary for custom API authentication or metadata. Headers are kept on each request, including its retry. Header names/values must be text; line breaks, reserved transport/Auth headers and more than 16 KB of custom headers are rejected. The client still owns `apikey`, Supabase bearer authentication and JSON content type. Custom authentication does not create or alter a Supabase Auth session.

App-specific routes and response envelopes belong in consuming code. Marble Engineer demonstrates this with the small `SupabaseCommunityBackend` adapter outside this folder. Copying this addon alone does not copy community-puzzle behavior or configuration.
