extends "res://tests/support/game_test.gd"

const Client = preload("res://addons/supabase_client/supabase_client.gd")

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
	func sign_in(_email: String) -> Dictionary: return result
	func verify_sign_in(_email: String, _code: String) -> Dictionary:
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
	var invalid_refresh: bool = false

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
			var path: String = buffers[peer].get_slice(" ", 1)
			paths.append(path)
			var body := "invalid-json" if path == "/malformed" else JSON.stringify({"api_version":1,"ok":true,"data":{"path":path}})
			var status := "200 OK"
			if path.begins_with("/auth/v1/token"):
				body = JSON.stringify({"access_token":"refreshed-token", "refresh_token":"refreshed-refresh", "expires_in":3600})
				if invalid_refresh: status = "400 Bad Request"; body = '{"error":"invalid_grant"}'
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
	assert_true((await service.verify_sign_in("author@example.test", "123456")).ok)
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
	var adapter := SupabaseCommunityBackend.new()
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

func test_real_http_concurrency_and_malformed_responses() -> void:
	var server := LocalHttpServer.new()
	add_child_autoqfree(server)
	assert_eq(server.server.listen(0, "127.0.0.1"), OK)
	var adapter := SupabaseCommunityBackend.new()
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
	var invalid: Dictionary = await adapter.client.request("/malformed")
	assert_eq(invalid.error.code, "invalid_response")

func test_expired_session_refresh_is_shared_and_rejection_clears_credentials() -> void:
	var server := LocalHttpServer.new()
	add_child_autoqfree(server)
	assert_eq(server.server.listen(0, "127.0.0.1"), OK)
	var adapter := SupabaseCommunityBackend.new()
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
