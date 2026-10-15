extends GutTest

func test_hosted_steam_owned_listing_when_requested() -> void:
	if OS.get_environment("MARBLE_ENGINEER_LIVE_STEAM_BACKEND_TEST") != "1":
		pending("Set MARBLE_ENGINEER_LIVE_STEAM_BACKEND_TEST=1 to verify a real ticket with the hosted service")
		return
	assert_true(SteamClient.initialized and SteamClient.online)
	if not SteamClient.initialized or not SteamClient.online: return
	var backend := SupabaseCommunityBackend.new()
	add_child_autoqfree(backend)
	var result := await backend.get_my_puzzles({})
	assert_true(result.ok, str(result.error))
	assert_true(backend.is_signed_in(), "A real ticket must be accepted by the hosted verifier")
	assert_true(SteamClient.web_tickets.is_empty(), "HTTP completion releases the Steam ticket")
	if result.ok: assert_true(result.data.get("puzzles") is Array)
	var invalid: Dictionary = await SupabaseClient.invoke_function("community", null, HTTPClient.METHOD_GET, false, "v1/mine", {"x-steam-ticket":"not-a-valid-ticket"})
	assert_eq(invalid.status, 401)
	assert_eq(invalid.data.get("error", {}).get("code"), "authentication_failed")
	var unverifiable: Dictionary = await SupabaseClient.invoke_function("community", null, HTTPClient.METHOD_GET, false, "v1/mine", {"x-steam-ticket":"00"})
	assert_false(unverifiable.ok, "Valve must reject a well-formed but invalid ticket")
	assert_gte(unverifiable.status, 400)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/community_catalog.json"))
	var public_result := await backend.browse_puzzles({}, manifest.compatibility)
	assert_true(public_result.ok, str(public_result.error))
	if public_result.ok: assert_true(public_result.data.get("puzzles") is Array)

func test_live_steam_web_ticket_when_requested() -> void:
	if OS.get_environment("MARBLE_ENGINEER_LIVE_STEAM_TEST") != "1":
		pending("Set MARBLE_ENGINEER_LIVE_STEAM_TEST=1 with Steam running to check ticket acquisition")
		return
	assert_true(SteamClient.initialized)
	assert_true(SteamClient.online)
	if not SteamClient.initialized or not SteamClient.online: return
	var result: Dictionary = await SteamClient.request_web_ticket(SupabaseCommunityBackend.STEAM_TICKET_IDENTITY)
	assert_true(result.ok, "Steam should deliver its web API ticket callback")
	if not result.ok: return
	assert_true(result.ticket is String)
	assert_gt(result.ticket.length(), 0)
	assert_eq(result.ticket.length() % 2, 0)
	assert_true(SteamClient.web_tickets.has(result.handle))
	SteamClient.release_web_ticket(result.handle)
	assert_true(SteamClient.web_tickets.is_empty())
