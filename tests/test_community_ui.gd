extends "res://tests/support/scene_test.gd"

class OfflineBackend extends Node:
	signal authentication_changed
	var wait_for_response: bool = false
	var authenticated: bool = false
	var credentials: Array[String] = []
	var automatic_auth: bool = false
	func uses_automatic_auth() -> bool: return automatic_auth
	func get_my_puzzles(_filters: Dictionary) -> Dictionary:
		return CommunityService.failure("sign_in_required", "Steam authentication is unavailable.")
	func is_signed_in() -> bool: return authenticated
	func sign_in(email: String, password: String) -> Dictionary:
		credentials = [email, password]
		authenticated = true
		authentication_changed.emit()
		return CommunityService.success()
	func browse_puzzles(_filters: Dictionary, _compatibility: String) -> Dictionary:
		if wait_for_response: await get_tree().create_timer(0.1).timeout
		return CommunityService.failure("network", "Offline. Installed puzzles are still available.")

func test_online_navigation_offline_feedback_and_safe_close() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	game.qa_resolution(1920, 1080)
	await get_tree().process_frame
	var service: CommunityService = game.community_service
	service.backend.queue_free()
	var adapter := OfflineBackend.new()
	service.add_child(adapter)
	service.backend = adapter
	var browser: Window = game.get_node("%PuzzleBrowser")
	var online: VBoxContainer = browser.get_node("%Network")
	browser.open(false, true)
	assert_true(browser.get_node("%OnlineBrowse").visible)
	browser.get_node("%OnlineBrowse").pressed.emit()
	assert_true(online.visible)
	assert_false(browser.get_node("%Browse").visible)
	assert_true("Offline" in online.get_node("%Feedback").text)
	assert_false(browser.get_node("%Import").visible)
	if DisplayServer.get_name() != "headless" and OS.get_environment("MARBLE_ENGINEER_UI_CAPTURE") == "1":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://build")
		assert_eq(get_viewport().get_texture().get_image().save_png("res://build/community-online.png"), OK)
	browser.get_node("%OnlineBrowse").pressed.emit()
	assert_false(online.visible)
	assert_true(browser.get_node("%Import").visible)
	assert_true(browser.get_node("%Browse").visible)
	adapter.wait_for_response = true
	browser.get_node("%OnlineBrowse").pressed.emit()
	assert_eq(online.get_node("%Feedback").text, "Loading…")
	browser.close()
	await get_tree().create_timer(0.2).timeout
	assert_eq(online.get_node("%Feedback").text, "Loading…", "A closed browser ignores stale request results")
	browser.open_campaign()
	assert_false(browser.get_node("%OnlineBrowse").visible)
	assert_false(online.visible)
	assert_false(browser.get_node("%Import").visible)

func test_password_form_signs_in_and_clears_credentials() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	var service: CommunityService = game.community_service
	service.backend.queue_free()
	var adapter := OfflineBackend.new()
	service.add_child(adapter)
	service.backend = adapter
	var browser: Window = game.get_node("%PuzzleBrowser")
	var online: VBoxContainer = browser.get_node("%Network")
	browser.open(false, true)
	browser.get_node("%OnlineBrowse").pressed.emit()
	online.get_node("%Account").pressed.emit()
	assert_true(online.get_node("%Password").secret)
	online.get_node("%Email").text = "author@example.test"
	online.get_node("%Password").text = "test-password"
	online.get_node("%SignInButton").pressed.emit()
	assert_eq(adapter.credentials, ["author@example.test", "test-password"])
	assert_true(service.is_signed_in())
	assert_eq(online.get_node("%Password").text, "")
	assert_false(online.get_node("%SignIn").visible)
	assert_eq(online.get_node("%Feedback").text, "Signed in.")
	online.get_node("%Password").text = "unsent-password"
	browser.close()
	assert_eq(online.get_node("%Password").text, "")

func test_automatic_auth_hides_email_form_even_when_verification_fails() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	var service: CommunityService = game.community_service
	service.backend.queue_free()
	var adapter := OfflineBackend.new()
	adapter.automatic_auth = true
	service.add_child(adapter)
	service.backend = adapter
	var browser: Window = game.get_node("%PuzzleBrowser")
	var online: VBoxContainer = browser.get_node("%Network")
	browser.open(false, true)
	browser.get_node("%OnlineBrowse").pressed.emit()
	assert_false(online.get_node("%Account").visible)
	assert_false(online.get_node("%SignIn").visible)
	online.get_node("%Mine").button_pressed = true
	assert_false(online.get_node("%SignIn").visible)
	assert_eq(online.get_node("%Feedback").text, "Steam authentication is unavailable.")
	browser.close()

func test_online_publication_uses_existing_local_revision_lifecycle() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	add_child_autoqfree(game)
	await get_tree().process_frame
	var service: CommunityService = game.community_service
	service.backend.queue_free()
	var adapter := OfflineBackend.new()
	service.add_child(adapter)
	service.backend = adapter
	var session: ConstructionSession = game.workspace.session
	var puzzle: Dictionary = session.store.load_campaign().levels.filter(func(item): return item.id == "campaign-01")[0]
	session.editor(puzzle)
	game.workspace.authoring.open()
	assert_true(game.workspace.authoring.get_node("%PublishOnline").visible)
	assert_false(game.workspace.authoring.get_node("%PublishOnline").disabled)
	game.workspace.authoring.get_node("%PublishOnline").pressed.emit()
	assert_true(FileAccess.file_exists(session.store.published_directory.path_join(puzzle.id + ".json")))
	assert_eq(session.puzzle.status, "published")
	assert_true(game.get_node("%PuzzleBrowser").get_node("%Network").get_node("%PublishOnline").visible)
	session.puzzle.name = "Edited after online publication"
	assert_eq(int(session.capture().revision), int(puzzle.revision) + 1, "Subsequent edits advance the existing revision contract")
	game.get_node("%PuzzleBrowser").close()
	session.editor(puzzle, true)
	game.workspace.authoring.open()
	assert_false(game.workspace.authoring.get_node("%PublishOnline").visible)
