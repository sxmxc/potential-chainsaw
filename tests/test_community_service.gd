extends "res://tests/support/game_test.gd"

const Client = preload("res://addons/supabase_client/supabase_client.gd")

class NoSteam extends Node:
	signal connection_changed(connected: bool)
	var initialized: bool = false:
		set(value):
			if initialized == value: return
			initialized = value
			connection_changed.emit(value)

class TicketSteam extends NoSteam:
	var online: bool = true
	var released: Array[int] = []
	var identity: String = ""
	func _init() -> void:
		initialized = true
	func request_web_ticket(value: String) -> Dictionary:
		identity = value
		return {"ok": true, "handle": 42, "ticket": "aabb"}
	func release_web_ticket(handle: int) -> void: released.append(handle)

class FunctionClient extends Node:
	signal authentication_changed
	var headers: Dictionary = {}
	var used_supabase_auth: bool = false
	var result: Dictionary = {"ok":true,"status":200,"data":{"api_version":1,"ok":true,"data":{"puzzles":[]}},"error":{}}
	func sign_out() -> Dictionary:
		authentication_changed.emit()
		return CommunityService.success()
	func invoke_function(_function: String, _body: Variant, _method: int, authenticated: bool, _path: String, extra: Dictionary = {}) -> Dictionary:
		headers = extra
		used_supabase_auth = authenticated
		return result

func test_steam_protected_operations_use_tickets_without_supabase_sessions() -> void:
	var adapter := SupabaseCommunityBackend.new()
	var ticket_source := TicketSteam.new()
	var transport := FunctionClient.new()
	add_child_autoqfree(ticket_source)
	add_child_autoqfree(transport)
	adapter.steam = ticket_source
	adapter.client = transport
	add_child_autoqfree(adapter)
	assert_false(adapter.is_signed_in(), "Steam initialization is not backend authentication")
	assert_true(adapter.uses_automatic_auth())
	assert_true((await adapter.get_my_puzzles({})).ok)
	assert_true(adapter.is_signed_in())
	assert_eq(ticket_source.identity, "marble-engineer-community")
	assert_eq(transport.headers, {"x-steam-ticket":"aabb"})
	assert_false(transport.used_supabase_auth)
	assert_eq(ticket_source.released, [42])
	ticket_source.initialized = false
	assert_false(adapter.steam_verified, "Connection changes invalidate the verified Steam identity")
	ticket_source.initialized = true
	watch_signals(adapter)
	assert_true((await adapter.sign_out()).ok)
	assert_signal_emitted(adapter, "authentication_changed", "Client authentication changes reach the adapter")
	transport.result = {"ok":false,"status":0,"data":{},"error":{"code":"network","message":"Offline"}}
	assert_false((await adapter.unpublish_puzzle("some-id")).ok)
	assert_eq(ticket_source.released, [42, 42], "Failures release the ticket too")
	assert_false(adapter.is_signed_in())
	await adapter.browse_puzzles({}, "")
	assert_true(transport.headers.is_empty(), "Public browsing never obtains a Steam ticket")
	assert_eq(ticket_source.released.size(), 2)

class FakeBackend extends Node:
	signal authentication_changed
	var result: Dictionary = CommunityService.success()
	var published: Dictionary = {}
	var authenticated: bool = false

	func is_signed_in() -> bool: return authenticated
	func browse_puzzles(_filters: Dictionary, _compatibility: String) -> Dictionary: return result
	func get_puzzle(_id: String, _revision: int, _compatibility: String) -> Dictionary: return result
	func publish_puzzle(data: Dictionary, _compatibility: String) -> Dictionary: published = data; return result
	func unpublish_puzzle(_id: String) -> Dictionary: return result
	func get_my_puzzles(_filters: Dictionary) -> Dictionary: return result
	func sign_in(_email: String, _password: String) -> Dictionary:
		authenticated = true
		authentication_changed.emit()
		return result
	func sign_out() -> Dictionary:
		authenticated = false
		authentication_changed.emit()
		return result

class LocalHttpServer extends Node:
	var server := TCPServer.new()
	var peers: Array[StreamPeerTCP] = []
	var buffers: Dictionary = {}
	var paths: Array[String] = []
	var bodies: Array[Dictionary] = []
	var headers: Array[String] = []
	var invalid_refresh: bool = false
	var invalid_password: bool = false

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			var peer := server.take_connection()
			peers.append(peer)
			buffers[peer] = ""
		for peer in peers.duplicate():
			peer.poll()
			if peer.get_available_bytes() == 0: continue
			buffers[peer] += peer.get_utf8_string(peer.get_available_bytes())
			if "\r\n\r\n" not in buffers[peer]: continue
			var header_end: int = buffers[peer].find("\r\n\r\n")
			var content_length := 0
			for header in buffers[peer].left(header_end).split("\r\n"):
				if header.to_lower().begins_with("content-length:"): content_length = int(header.get_slice(":", 1))
			var payload: String = buffers[peer].substr(header_end + 4)
			if payload.to_utf8_buffer().size() < content_length: continue
			headers.append(buffers[peer].left(header_end))
			var parsed: Variant = JSON.parse_string(payload) if not payload.is_empty() else {}
			bodies.append(parsed if parsed is Dictionary else {})
			var path: String = buffers[peer].get_slice(" ", 1)
			paths.append(path)
			var body := "invalid-json" if path == "/malformed" else JSON.stringify({"api_version":1,"ok":true,"data":{"path":path}})
			var status := "200 OK"
			if path.begins_with("/auth/v1/token"):
				body = JSON.stringify({"access_token":"refreshed-token", "refresh_token":"refreshed-refresh", "expires_in":3600})
				if invalid_refresh or (invalid_password and path.ends_with("grant_type=password")):
					status = "400 Bad Request"
					body = '{"error":"invalid_grant","error_description":"PRIVATE_PROVIDER_DETAIL"}'
			var bytes := body.to_utf8_buffer()
			peer.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status,bytes.size()]).to_utf8_buffer())
			peer.put_data(bytes)
			peers.erase(peer)
			buffers.erase(peer)

	func _exit_tree() -> void:
		for peer in peers: peer.disconnect_from_host()
		server.stop()

var responses: Array[Dictionary] = []

func collect_request(adapter: SupabaseCommunityBackend, path: String) -> void:
	responses.append(SupabaseCommunityBackend.decode_envelope(await adapter.client.request(path)))

func collect_owned(adapter: SupabaseCommunityBackend) -> void:
	responses.append(await adapter.get_my_puzzles({}))

func service_with(adapter: Node) -> CommunityService:
	var service := CommunityService.new()
	add_child_autofree(service)
	service.configure(PuzzleStore.new(PieceCatalog.new()), adapter)
	return service

func playable(store: PuzzleStore) -> Dictionary:
	return store.playable_content(store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0])

func test_contract_publish_gate_and_provider_independence() -> void:
	var adapter := FakeBackend.new()
	var service := service_with(adapter)
	var puzzle := playable(service.store)
	puzzle.campaign = {"chapter": {"id": "introduction"}}
	puzzle._source = "campaign"
	assert_true((await service.publish_puzzle(puzzle)).ok)
	assert_false(adapter.published.has("campaign"))
	assert_false(adapter.published.has("_source"))
	assert_eq(adapter.published.id, puzzle.id)
	assert_eq(adapter.published.required_assets, service.store.required_assets(puzzle))
	adapter.published = {}
	puzzle.validation = {}
	assert_false((await service.publish_puzzle(puzzle)).ok)
	assert_true(adapter.published.is_empty(), "Unverified drafts never reach the provider")
	assert_true((await service.sign_in("author@example.test", "test-password")).ok)
	assert_true(service.is_signed_in())
	assert_true((await service.sign_out()).ok)
	assert_false(service.is_signed_in())

func test_download_reuses_installation_and_rejects_identity_conflicts() -> void:
	var adapter := FakeBackend.new()
	var service := service_with(adapter)
	var puzzle := playable(service.store)
	puzzle.id = "community-online-r1"
	adapter.result = CommunityService.success({"puzzle": puzzle})
	var installed := await service.download_puzzle("online", 1)
	assert_true(installed.ok)
	assert_eq(installed.data.puzzle._source, "community")
	assert_false(PuzzleStore.is_official(installed.data.puzzle))
	assert_true((await service.download_puzzle("online", 1)).ok, "Identical downloads are idempotent")
	puzzle.name = "Unrelated replacement"
	adapter.result = CommunityService.success({"puzzle": puzzle})
	assert_false((await service.download_puzzle("online", 1)).ok)
	assert_ne(service.store.list_community()[0].name, puzzle.name)
	puzzle.id = "../escape"
	assert_false((await service.download_puzzle("online", 1)).ok)
	adapter.result = CommunityService.failure("network", "Offline")
	assert_false((await service.browse_puzzles()).ok)
	assert_eq(service.store.list_community().size(), 1, "Offline service leaves installed puzzles available")
	assert_false(service.store.load_campaign().levels.is_empty())

func test_response_errors_do_not_expose_auth_payloads() -> void:
	var decode := Client.decode_response
	assert_eq(decode.call(HTTPRequest.RESULT_TIMEOUT, 0, PackedByteArray()).error.code, "timeout")
	assert_eq(decode.call(HTTPRequest.RESULT_SUCCESS, 401, '{"error":"SECRET"}'.to_utf8_buffer()).error.code, "sign_in_required")
	var failure: Dictionary = Client.auth_error(decode.call(HTTPRequest.RESULT_SUCCESS, 400, '{"error":"SECRET"}'.to_utf8_buffer()))
	assert_false("SECRET" in failure.error.message)
	assert_true(failure.data.is_empty())
	assert_true(decode.call(HTTPRequest.RESULT_SUCCESS, 200, "[]".to_utf8_buffer()).ok, "The portable client supports JSON arrays")
	var wrong_version: Dictionary = decode.call(HTTPRequest.RESULT_SUCCESS, 200, '{"api_version":2,"ok":true,"data":{}}'.to_utf8_buffer())
	assert_eq(SupabaseCommunityBackend.decode_envelope(wrong_version).error.code, "invalid_response")
	var valid: Dictionary = decode.call(HTTPRequest.RESULT_SUCCESS, 200, '{"api_version":1,"ok":true,"data":{"puzzles":[]}}'.to_utf8_buffer())
	assert_true(SupabaseCommunityBackend.decode_envelope(valid).ok)

func test_session_response_validation_and_local_sign_out() -> void:
	var adapter := standalone_backend()
	adapter.client = Client.new()
	add_child_autoqfree(adapter.client)
	add_child_autofree(adapter)
	adapter.client.project_url = ""
	assert_false(adapter.client.accept_session({}).ok)
	assert_true(adapter.client.accept_session({"access_token":"test-token", "refresh_token":"test-refresh", "expires_in":1}).ok)
	assert_true(adapter.is_signed_in())
	var result := await adapter.sign_out()
	assert_false(result.ok, "Remote revocation failure is reported")
	assert_false(adapter.is_signed_in(), "Local credentials are cleared even offline")
	assert_eq(adapter.client.access_token, "")
	assert_eq(adapter.client.refresh_token, "")
	assert_false((await adapter.get_my_puzzles({})).ok)

func test_password_sign_in_uses_password_grant_and_sanitizes_results() -> void:
	var server := LocalHttpServer.new()
	add_child_autoqfree(server)
	assert_eq(server.server.listen(0, "127.0.0.1"), OK)
	var client := Client.new()
	add_child_autoqfree(client)
	client.configure("http://127.0.0.1:%d" % server.server.get_local_port(), "sb_publishable_test")
	assert_false((await client.sign_in_with_password("author@example.test", "")).ok)
	assert_true(server.paths.is_empty(), "Missing credentials do not send a request")
	var result := await client.sign_in_with_password(" author@example.test ", " password with spaces ")
	assert_true(result.ok)
	assert_true(result.data.is_empty(), "Sign-in never returns session tokens")
	assert_true(client.is_signed_in())
	assert_eq(server.paths[0], "/auth/v1/token?grant_type=password")
	assert_eq(server.bodies[0], {"email":"author@example.test", "password":" password with spaces "})
	client.clear_session()
	server.invalid_password = true
	result = await client.sign_in_with_password("author@example.test", "wrong-password")
	assert_eq(result.error.code, "authentication_failed")
	assert_true(result.data.is_empty())
	assert_false("PRIVATE_PROVIDER_DETAIL" in result.error.message)
	assert_false(client.is_signed_in())

func test_real_http_concurrency_and_malformed_responses() -> void:
	var server := LocalHttpServer.new()
	add_child_autoqfree(server)
	assert_eq(server.server.listen(0, "127.0.0.1"), OK)
	var adapter := standalone_backend()
	adapter.client = Client.new()
	add_child_autoqfree(adapter.client)
	add_child_autoqfree(adapter)
	adapter.client.project_url = "http://127.0.0.1:%d" % server.server.get_local_port()
	adapter.client.publishable_key = "sb_publishable_test"
	responses.clear()
	collect_request.call_deferred(adapter, "/first")
	collect_request.call_deferred(adapter, "/second")
	await wait_until(func(): return responses.size() == 2, 5)
	assert_eq(responses.size(), 2, "Independent HTTPRequest nodes complete concurrent requests")
	for result in responses: assert_true(result.ok)
	assert_true(responses.any(func(result): return result.data.get("path") == "/first"))
	assert_true(responses.any(func(result): return result.data.get("path") == "/second"))
	assert_eq(adapter.client.requests.size(), 0)
	var custom: Dictionary = await adapter.client.invoke_function("any-function", {"value":1}, HTTPClient.METHOD_POST, false, "", {"x-custom":"portable-header"})
	assert_true(custom.ok)
	assert_true("x-custom: portable-header" in server.headers[-1])
	assert_eq(server.bodies[-1], {"value":1.0})
	var invalid: Dictionary = await adapter.client.request("/malformed")
	assert_eq(invalid.error.code, "invalid_response")

func test_expired_session_refresh_is_shared_and_rejection_clears_credentials() -> void:
	var server := LocalHttpServer.new()
	add_child_autoqfree(server)
	assert_eq(server.server.listen(0, "127.0.0.1"), OK)
	var adapter := standalone_backend()
	adapter.client = Client.new()
	add_child_autoqfree(adapter.client)
	add_child_autoqfree(adapter)
	adapter.client.project_url = "http://127.0.0.1:%d" % server.server.get_local_port()
	adapter.client.publishable_key = "sb_publishable_test"
	assert_true(adapter.client.accept_session({"access_token":"expired", "refresh_token":"refresh", "expires_in":1}).ok)
	responses.clear()
	collect_owned.call_deferred(adapter)
	collect_owned.call_deferred(adapter)
	await wait_until(func(): return responses.size() == 2, 5)
	assert_eq(responses.size(), 2)
	for result in responses: assert_true(result.ok)
	assert_eq(server.paths.filter(func(path): return path.begins_with("/auth/v1/token")).size(), 1, "Concurrent authenticated calls share one refresh")
	assert_eq(adapter.client.access_token, "refreshed-token")
	adapter.client.expires_at = 0
	server.invalid_refresh = true
	var rejected := await adapter.get_my_puzzles({})
	assert_eq(rejected.error.code, "sign_in_required")
	assert_false(adapter.is_signed_in())
	assert_eq(adapter.client.access_token, "")

func standalone_backend() -> SupabaseCommunityBackend:
	var adapter := SupabaseCommunityBackend.new()
	adapter.steam = NoSteam.new()
	add_child_autoqfree(adapter.steam)
	return adapter
