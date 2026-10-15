extends Node
## Portable native Godot JSON/HTTPS client with memory-only Supabase email OTP Auth.
signal authentication_changed
signal refresh_finished(result: Dictionary)

@export var project_url: String = ""
@export var publishable_key: String = ""
@export var request_timeout: float = 20.0
@export var max_concurrent_requests: int = 8
@export var max_body_bytes: int = 5000000
var access_token: String = ""
var refresh_token: String = ""
var expires_at: float = 0
var refreshing: bool = false
var session_generation: int = 0
var requests: Array[HTTPRequest] = []

func _ready() -> void:
	var config := ConfigFile.new()
	var script_path: String = get_script().resource_path
	if config.load(script_path.get_base_dir().path_join("supabase.cfg")) == OK:
		project_url = config.get_value("supabase", "url", project_url)
		publishable_key = config.get_value("supabase", "publishable_key", publishable_key)

static func success(data: Variant = {}, status: int = 200) -> Dictionary:
	return {"ok": true, "data": data, "error": {}, "status": status}

static func failure(code: String, message: String, status: int = 0, data: Variant = {}) -> Dictionary:
	return {"ok": false, "data": data, "error": {"code": code, "message": message}, "status": status}

func configure(url: String, key: String) -> void:
	clear_session()
	project_url = url.trim_suffix("/")
	publishable_key = key

func is_signed_in() -> bool:
	return not refresh_token.is_empty()

func sign_in(email: String) -> Dictionary:
	if email.strip_edges().is_empty() or "@" not in email: return failure("invalid_email", "Enter an email address.")
	var result := await request_http("/auth/v1/otp", HTTPClient.METHOD_POST, {"email": email.strip_edges(), "create_user": true})
	return success() if result.ok else auth_error(result)

func verify_sign_in(email: String, code: String) -> Dictionary:
	if code.strip_edges().is_empty(): return failure("invalid_code", "Enter the code from your email.")
	var generation := session_generation
	var result := await request_http("/auth/v1/verify", HTTPClient.METHOD_POST, {"email": email.strip_edges(), "token": code.strip_edges(), "type": "email"})
	if generation != session_generation: return failure("cancelled", "Sign-in was cancelled.")
	if result.ok and result.data is Dictionary: return accept_session(result.data, true)
	return auth_error(result)

func accept_session(data: Dictionary, new_session: bool = false) -> Dictionary:
	if not data.get("access_token") is String or not data.get("refresh_token") is String or not data.get("expires_in") is float and not data.get("expires_in") is int:
		return failure("invalid_response", "The sign-in response was invalid.")
	if data.access_token.is_empty() or data.refresh_token.is_empty(): return failure("invalid_response", "The sign-in response was incomplete.")
	if not is_finite(float(data.expires_in)) or float(data.expires_in) <= 0: return failure("invalid_response", "The sign-in response was invalid.")
	if new_session: session_generation += 1
	access_token = data.access_token
	refresh_token = data.refresh_token
	expires_at = Time.get_unix_time_from_system() + float(data.expires_in)
	authentication_changed.emit()
	return success()

static func auth_error(result: Dictionary) -> Dictionary:
	# Raw provider Auth errors never escape sign-in/refresh operations.
	if result.ok: return failure("invalid_response", "The sign-in response was invalid.")
	if result.status >= 400 and result.status < 500 and result.status != 429:
		return failure("authentication_failed", "Could not sign in. Check your email and code, then try again.", result.status)
	return failure(result.error.code, result.error.message, result.status)

func refresh_session() -> Dictionary:
	if refreshing: return await refresh_finished
	if not is_signed_in(): return failure("sign_in_required", "Sign in to continue.")
	refreshing = true
	var generation := session_generation
	var result := await request_http("/auth/v1/token?grant_type=refresh_token", HTTPClient.METHOD_POST, {"refresh_token": refresh_token})
	if generation != session_generation:
		result = failure("cancelled", "Sign-in was cancelled.")
	elif result.ok and result.data is Dictionary:
		result = accept_session(result.data)
	elif result.status >= 400 and result.status < 500 and result.status != 429:
		clear_session()
		result = failure("sign_in_required", "Your session expired. Sign in again to continue.")
	else:
		result = auth_error(result)
	refreshing = false
	refresh_finished.emit(result)
	return result

func clear_session() -> void:
	session_generation += 1
	access_token = ""
	refresh_token = ""
	expires_at = 0
	authentication_changed.emit()

func sign_out() -> Dictionary:
	var token := access_token
	clear_session()
	if token.is_empty(): return success()
	var result := await request_http("/auth/v1/logout?scope=local", HTTPClient.METHOD_POST, null, token)
	if not result.ok: return failure("sign_out_local", "Signed out on this device. The service could not revoke the session.")
	return success()

## JSON endpoints are project-relative; no game routes or envelopes are assumed.
func invoke_function(function_name: String, body: Variant = null, method: int = HTTPClient.METHOD_POST, authenticated: bool = false, relative_path: String = "") -> Dictionary:
	if function_name.is_empty() or "/" in function_name or "?" in function_name or "#" in function_name:
		return failure("invalid_request", "Provide an Edge Function name.")
	var path := "/functions/v1/" + function_name.uri_encode()
	if not relative_path.is_empty(): path += "/" + relative_path.trim_prefix("/")
	return await request(path, method, body, authenticated)

func request(path: String, method: int = HTTPClient.METHOD_GET, body: Variant = null, authenticated: bool = false) -> Dictionary:
	var generation := session_generation
	if authenticated:
		if not is_signed_in(): return failure("sign_in_required", "Sign in to continue.")
		if expires_at <= Time.get_unix_time_from_system() + 60:
			var refreshed := await refresh_session()
			if not refreshed.ok: return refreshed
		if generation != session_generation: return failure("cancelled", "The session changed during this request.")
	var result := await request_http(path, method, body, access_token if authenticated else "")
	if generation != session_generation: return failure("cancelled", "The session changed during this request.")
	if authenticated and result.status == 401:
		var refreshed := await refresh_session()
		if not refreshed.ok: return refreshed
		result = await request_http(path, method, body, access_token)
		if generation != session_generation: return failure("cancelled", "The session changed during this request.")
	return result

func request_http(path: String, method: int, body: Variant = null, token: String = "") -> Dictionary:
	var base := project_url.trim_suffix("/")
	var local_url := OS.has_feature("editor") and (base.begins_with("http://127.0.0.1:") or base.begins_with("http://localhost:"))
	if (not base.begins_with("https://") and not local_url) or not publishable_key.begins_with("sb_publishable_"):
		return failure("unavailable", "Configure a Supabase project URL and publishable key.")
	if not path.begins_with("/") or path.begins_with("//") or "\r" in path or "\n" in path:
		return failure("invalid_request", "Use a project-relative request path.")
	if requests.size() >= max_concurrent_requests: return failure("busy", "Too many requests. Try again shortly.")
	var payload := JSON.stringify(body) if body != null else ""
	if payload.to_utf8_buffer().size() > max_body_bytes: return failure("too_large", "The request body is too large.")
	var request_node := HTTPRequest.new()
	request_node.timeout = request_timeout
	request_node.max_redirects = 0
	request_node.body_size_limit = max_body_bytes
	add_child(request_node)
	requests.append(request_node)
	var headers := PackedStringArray(["Content-Type: application/json", "apikey: " + publishable_key])
	if not token.is_empty(): headers.append("Authorization: Bearer " + token)
	var error := request_node.request(base + path, headers, method, payload)
	if error != OK:
		requests.erase(request_node)
		request_node.queue_free()
		return failure("network", "Could not reach Supabase.")
	var response: Array = await request_node.request_completed
	requests.erase(request_node)
	request_node.queue_free()
	return decode_response(int(response[0]), int(response[1]), response[3])

static func decode_response(transport: int, status: int, bytes: PackedByteArray) -> Dictionary:
	if transport != HTTPRequest.RESULT_SUCCESS:
		return failure("timeout" if transport == HTTPRequest.RESULT_TIMEOUT else "network", "The request did not complete.")
	if status >= 200 and status < 300 and bytes.is_empty(): return success({}, status)
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK: return failure("invalid_response", "The server returned invalid JSON.", status)
	var parsed: Variant = json.data
	if status >= 200 and status < 300: return success(parsed, status)
	if status == 401: return failure("sign_in_required", "Sign in again to continue.", status, parsed)
	if status == 429: return failure("rate_limit", "Too many requests. Try again later.", status, parsed)
	return failure("http_error", "The server rejected the request.", status, parsed)
