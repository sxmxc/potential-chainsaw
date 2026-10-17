extends "res://tests/support/game_test.gd"

# Keep this application's settings/audio setup outside presentation regression tests.
class CompletionHost extends GameManager:
	func load_settings() -> void:
		pass

class CountingStore extends PuzzleStore:
	var campaign_reads: int = 0

	func load_campaign() -> CampaignDefinition:
		campaign_reads += 1
		return super.load_campaign()

var workspace: ConstructionWorkspace
var completion: Control
var requests: int

func setup_presentation() -> void:
	workspace = load("res://scenes/construction_workspace.tscn").instantiate()
	add_child_autoqfree(workspace)
	completion = load("res://scenes/ui/puzzle_completion.tscn").instantiate()
	add_child_autoqfree(completion)
	await get_tree().process_frame
	completion.configure(workspace.session)
	requests = 0
	completion.presentation_requested.connect(func(): requests += 1; completion.present())

func official(id: String) -> Dictionary:
	for data: Dictionary in workspace.session.store.load_campaign().levels:
		if data.id == id: return data
	return {}

# Inject an authoritative result to exercise presentation and navigation contracts.
# These tests do not claim that a puzzle's physical route succeeds.
func acknowledge() -> void:
	workspace.world.simulation.construction_before = workspace.world.build.snapshot()
	workspace.world.simulation.elapsed = 4.5
	workspace.world.simulation._end(SimulationManager.State.SUCCESS, "Puzzle complete")

func test_intro_reveal_next_and_duplicate_result() -> void:
	await setup_presentation()
	workspace.session.player(official("campaign-01"))
	acknowledge()
	assert_true(completion.visible)
	assert_eq(requests, 1)
	assert_true(completion.get_node("%Next").visible)
	assert_string_contains(completion.get_node("%Chapter").text, "Introduction")
	assert_true(workspace.session.progress.records["campaign-01"].completed)
	completion.result(SimulationManager.State.SUCCESS, "Again")
	assert_eq(requests, 1, "Repeated success cannot restart the sequence")
	completion.get_node("%Next").pressed.emit()
	completion.get_node("%Next").pressed.emit()
	await wait_seconds(0.2)
	assert_eq(workspace.session.puzzle.id, "campaign-02")
	assert_false(completion.visible)
	assert_eq(workspace.world.simulation.state, SimulationManager.State.BUILD)
	assert_eq(completion.celebrations.size(), 0)

func test_world_celebration_follows_objective_and_expires_while_ui_remains() -> void:
	await setup_presentation()
	var data := official("campaign-01")
	data.objectives.append(data.objectives[0].duplicate())
	workspace.session.player(data)
	var piece_count := workspace.world.build.pieces.size()
	acknowledge()
	assert_eq(completion.celebrations.size(), 1, "Several goals at one mechanism share a celebration")
	var celebration: Node3D = completion.celebrations[0]
	var goal := workspace.world.build.find_piece(data.objectives[0].target)
	assert_lt(celebration.global_position.distance_to(goal.global_position), 3.0, "The effect celebrates the actual mechanism")
	assert_eq(workspace.world.build.pieces.size(), piece_count, "VFX never enter construction")
	completion.result(SimulationManager.State.SUCCESS, "Again")
	assert_same(completion.celebrations[0], celebration)
	await wait_seconds(3.8)
	assert_true(completion.celebrations.is_empty(), "The authored animation releases the effect")
	assert_false(is_instance_valid(celebration))
	assert_true(completion.visible, "Particle completion does not dismiss the victory screen")

func test_chapter_milestone_uses_recorded_progress() -> void:
	await setup_presentation()
	var data := official("chapter1-loading-loft")
	var campaign := workspace.session.store.load_campaign()
	var chapter := campaign.chapter_for(data)
	for level: Dictionary in campaign.levels:
		if campaign.chapter_for(level).id == chapter.id:
			workspace.session.progress.records[level.id] = {"completed": true}
	workspace.session.player(data)
	acknowledge()
	assert_eq(completion.get_node("%Context").text, "CHAPTER COMPLETE")
	assert_eq(completion.get_node("%Title").text, "Well built!")
	assert_true(completion.get_node("%Progress").visible)
	assert_string_contains(completion.get_node("%Chapter").text, "Chapter 1")
	workspace.session.sandbox()
	assert_false(completion.visible)
	await wait_seconds(1.1)
	assert_eq(completion.celebrations.size(), 0, "Old reveal callbacks stay cancelled")

func test_community_actions_and_keep_building_retain_layout() -> void:
	await setup_presentation()
	var data := official("campaign-01")
	data._source = "community"
	workspace.session.player(data)
	var before := workspace.world.build.snapshot()
	acknowledge()
	assert_false(completion.get_node("%Next").visible)
	assert_false(completion.get_node("%Progress").visible)
	assert_eq(completion.get_node("%LevelSelection").text, "Community puzzles")
	assert_true(workspace.session.progress.community_records[data.id].completed)
	assert_false(workspace.session.progress.records.has(data.id))
	completion.get_node("%KeepBuilding").pressed.emit()
	await wait_seconds(0.2)
	assert_eq(workspace.world.build.snapshot(), before)
	assert_eq(workspace.world.simulation.state, SimulationManager.State.BUILD)
	assert_false(completion.visible)

func test_player_test_preserves_solution_and_returns_to_editor() -> void:
	await setup_presentation()
	workspace.session.editor(official("campaign-01"))
	assert_true(workspace.session.test_player())
	acknowledge()
	assert_true(completion.get_node("%Preserve").visible)
	assert_false(completion.get_node("%LevelSelection").visible)
	assert_false(completion.get_node("%Next").visible)
	completion.get_node("%Preserve").pressed.emit()
	assert_false(completion.get_node("%Preserve").visible)
	assert_true(workspace.session.authored.validation.physics_success)
	assert_eq(workspace.session.progress.records, {}, "Player Test cannot record campaign progress")
	completion.get_node("%ReturnEditor").pressed.emit()
	await wait_seconds(0.2)
	assert_true(workspace.session.is_authoring)
	assert_false(completion.visible)

func test_dismiss_reopen_and_context_change_cancel_navigation() -> void:
	await setup_presentation()
	workspace.session.player(official("campaign-01"))
	var previous_focus := Button.new()
	add_child_autoqfree(previous_focus)
	previous_focus.grab_focus()
	acknowledge()
	var actions: Array[String] = []
	completion.dismiss(func(): actions.append("stale"))
	completion.present()
	await wait_seconds(0.2)
	assert_eq(actions, [], "Reopening abandons the previous exit action")
	assert_eq(completion.get_node("Margin").mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_INHERITED)
	await wait_seconds(1.0)
	assert_eq(completion.get_node("%Progress").value, 1.0, "Interrupted reveal retains the authoritative chapter count")
	completion.dismiss(func(): actions.append("context"))
	workspace.session.sandbox()
	await wait_seconds(0.2)
	assert_eq(actions, [], "Changing context abandons pending exit actions")
	assert_eq(get_viewport().gui_get_focus_owner(), previous_focus, "Dismissal restores focus after the host restores its UI")
	assert_eq(completion.celebrations.size(), 0)

func test_escape_and_browser_dispatch_during_reveal() -> void:
	await setup_presentation()
	workspace.session.player(official("campaign-01"))
	acknowledge()
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	completion._input(event)
	await wait_seconds(0.2)
	assert_false(completion.visible)
	assert_eq(workspace.world.simulation.state, SimulationManager.State.SUCCESS, "Escape only closes presentation")
	completion.present()
	var calls: Array[int] = []
	completion.levels_requested.connect(func(): calls.append(1))
	completion.get_node("%LevelSelection").pressed.emit()
	completion.get_node("%LevelSelection").pressed.emit()
	await wait_seconds(0.2)
	assert_eq(calls.size(), 1)

func test_application_defers_reveal_and_restores_hud_and_modal_ownership() -> void:
	var game: GameManager = load("res://scenes/main.tscn").instantiate()
	game.set_script(CompletionHost)
	game.get_node("%MainMenu").main_menu_playlist = null
	game.get_node("Workspace/World").world_music_playlist = null
	add_child_autoqfree(game)
	await get_tree().process_frame
	workspace = game.workspace
	workspace.session.player(official("campaign-01"))
	# A result during application navigation waits for its owner to settle.
	acknowledge()
	assert_true(game.completion_pending)
	await wait_until(func(): return not game.navigating, 3.0, "Application navigation settles before victory")
	var victory: Control = game.get_node("%PuzzleCompletion")
	assert_true(victory.visible)
	assert_false(workspace.hud.visible)
	assert_false(workspace.world.camera.enabled)
	assert_false(game.modal_motion.wanted)
	# An unrelated modal may interrupt; closing it restores the celebration.
	game.show_message("Review interruption")
	game.message_dialog.hide()
	game.modal_closed()
	assert_true(victory.visible)
	assert_false(game.modal_motion.wanted)
	victory.get_node("%Next").pressed.emit()
	await wait_seconds(0.25)
	assert_eq(workspace.session.puzzle.id, "campaign-02")
	assert_true(workspace.hud.visible)
	assert_true(workspace.world.camera.enabled)
	acknowledge()
	victory.get_node("%LevelSelection").pressed.emit()
	await wait_seconds(0.25)
	assert_true(game.get_node("%PuzzleBrowser").visible)
	assert_true(game.modal_motion.wanted)
	assert_false(workspace.world.camera.enabled)
	game.get_node("%PuzzleBrowser").hide()
	game.modal_closed()
	assert_true(workspace.hud.visible)
	assert_true(workspace.world.camera.enabled)

func test_success_reuses_campaign_loaded_at_entry_without_catalog_io() -> void:
	await setup_presentation()
	var data := official("campaign-01")
	var store := CountingStore.new(workspace.catalog)
	workspace.session.store = store
	workspace.session.player(data)
	assert_eq(store.campaign_reads, 1, "An official puzzle refreshes its campaign at entry")
	var campaign := workspace.session.campaign
	acknowledge()
	assert_eq(store.campaign_reads, 1, "Recording success and presenting victory must not reload the catalog")
	assert_same(workspace.session.campaign, campaign)
	assert_true(workspace.session.progress.records[data.id].completed)
	workspace.world.simulation.reset()
	acknowledge()
	assert_eq(store.campaign_reads, 1, "Retrying uses the same play-session catalog")
	workspace.session.player(data)
	assert_eq(store.campaign_reads, 2, "Reentering refreshes content rather than keeping a stale global cache")
	data._source = "community"
	workspace.session.player(data)
	acknowledge()
	assert_eq(store.campaign_reads, 2, "Community completion needs no campaign read")
	assert_true(workspace.session.progress.community_records[data.id].completed)
