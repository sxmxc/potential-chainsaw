extends GutTest

const Client = preload("res://addons/supabase_client/supabase_client.gd")

func test_standalone_client_needs_only_explicit_configuration() -> void:
	# Instantiate the addon directly, without main.tscn, CommunityService or game configuration.
	var client := Client.new()
	assert_eq(client.project_url, "")
	assert_eq(client.publishable_key, "")
	add_child_autoqfree(client)
	var config := ConfigFile.new()
	assert_eq(config.load("res://addons/supabase_client/supabase.cfg"), OK)
	assert_eq(client.project_url, config.get_value("supabase", "url"), "Client loads the config beside the addon")
	assert_eq(client.publishable_key, config.get_value("supabase", "publishable_key"))
	client.configure("https://example.supabase.co/", "sb_publishable_test")
	assert_eq(client.project_url, "https://example.supabase.co")
	assert_false(client.is_signed_in())
	assert_eq((await client.request("https://another-project.test/")).error.code, "invalid_request")
	assert_eq((await client.request("//another-project.test/")).error.code, "invalid_request")
	client.max_body_bytes = 8
	assert_eq((await client.request("/functions/v1/anything", HTTPClient.METHOD_POST, {"too_big":true})).error.code, "too_large")
	client.publishable_key = "sb_secret_never_allowed"
	assert_eq((await client.request("/rest/v1/anything")).error.code, "unavailable")

func test_generic_response_format_is_independent_of_community_api() -> void:
	assert_eq(Client.decode_response(HTTPRequest.RESULT_SUCCESS, 200, "42".to_utf8_buffer()).data, 42.0, "RPC scalar responses require no schema knowledge")
	assert_true(Client.decode_response(HTTPRequest.RESULT_SUCCESS, 201, PackedByteArray()).ok, "Successful writes may return no JSON body")
	var result := Client.decode_response(HTTPRequest.RESULT_SUCCESS, 200, '[{"name":"Any project"}]'.to_utf8_buffer())
	assert_true(result.ok)
	assert_eq(result.data[0].name, "Any project")
	assert_eq(result.status, 200)
	result = Client.decode_response(HTTPRequest.RESULT_SUCCESS, 200, '{"custom":"payload"}'.to_utf8_buffer())
	assert_true(result.ok)
	assert_eq(result.data.custom, "payload")
	result = Client.decode_response(HTTPRequest.RESULT_SUCCESS, 403, '{"code":"custom_denial"}'.to_utf8_buffer())
	assert_false(result.ok)
	assert_eq(result.status, 403)
	assert_eq(result.data.code, "custom_denial", "The caller owns its API's error interpretation")
