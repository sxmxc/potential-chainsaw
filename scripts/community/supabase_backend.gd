class_name SupabaseCommunityBackend
extends Node
## Marble Engineer's routes and API-v1 envelope live only here.
signal authentication_changed

var client: Node = SupabaseClient

func _ready() -> void:
	client.authentication_changed.connect(authentication_changed.emit)

func is_signed_in() -> bool:
	return client.is_signed_in()

func sign_in(email: String) -> Dictionary:
	return await client.sign_in(email)

func verify_sign_in(email: String, code: String) -> Dictionary:
	return await client.verify_sign_in(email, code)

func sign_out() -> Dictionary:
	return await client.sign_out()

func browse_puzzles(filters: Dictionary, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "puzzles?" + query(filters, compatibility))

func get_my_puzzles(filters: Dictionary) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "mine?" + query(filters, ""), null, true)

func get_puzzle(id: String, revision: int, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_GET, "puzzles/" + id.uri_encode() + "?revision=%d&compatibility=%s" % [revision, compatibility.uri_encode()])

func publish_puzzle(puzzle: Dictionary, compatibility: String) -> Dictionary:
	return await api(HTTPClient.METHOD_POST, "puzzles", {"puzzle": puzzle, "compatibility": compatibility}, true)

func unpublish_puzzle(id: String) -> Dictionary:
	return await api(HTTPClient.METHOD_DELETE, "puzzles/" + id.uri_encode(), null, true)

func query(filters: Dictionary, compatibility: String) -> String:
	return "offset=%d&search=%s&compatibility=%s" % [maxi(0, int(filters.get("offset", 0))), str(filters.get("search", "")).left(100).uri_encode(), compatibility.uri_encode()]

func api(method: int, route: String, body: Variant = null, authenticated: bool = false) -> Dictionary:
	return decode_envelope(await client.invoke_function("community", body, method, authenticated, "v1/" + route))

static func decode_envelope(response: Dictionary) -> Dictionary:
	if response.status == 0: return CommunityService.failure(response.error.code, response.error.message)
	var parsed: Variant = response.data
	if not parsed is Dictionary or parsed.get("api_version") != 1 or not parsed.get("ok") is bool:
		if not response.ok: return CommunityService.failure(response.error.code, response.error.message)
		return CommunityService.failure("invalid_response", "The community service uses an unsupported response format.")
	if response.ok and parsed.ok and parsed.get("data") is Dictionary: return CommunityService.success(parsed.data)
	if not parsed.ok and parsed.get("error") is Dictionary and parsed.error.get("code") is String and parsed.error.get("message") is String:
		return CommunityService.failure(parsed.error.code, parsed.error.message.left(500))
	return CommunityService.failure("invalid_response", "The community service returned an invalid result.")
