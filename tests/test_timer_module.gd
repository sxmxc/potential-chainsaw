extends GutTest

func make_timer(settings: Dictionary = {}) -> PieceBehavior:
	var behavior = load("res://scenes/mechanisms/logic/timer.tscn").instantiate()
	add_child_autoqfree(behavior)
	behavior.configure(settings)
	watch_signals(behavior)
	return behavior

func test_duration_is_used_directly_as_seconds() -> void:
	var behavior := make_timer({"frequency": 2.0})
	assert_eq(behavior.get_setting(&"frequency").unit, "s")
	assert_eq(behavior.get_setting(&"frequency").label, "Duration")
	assert_eq(behavior.get_node("Timer").wait_time, 2.0)
	assert_eq(behavior.get_node("Readout").text, "2.00s")

func test_stop_then_start_starts_an_idle_timer_and_restarts_a_completed_one() -> void:
	var behavior := make_timer({"frequency": 0.5, "auto_start": false, "loop": false})
	var clock := behavior.get_node("Timer") as Timer
	behavior.start_run()
	behavior.receive("stop")
	behavior.receive("start")
	assert_false(clock.is_stopped(), "An idle paused timer must start on Start")
	assert_false(clock.paused)
	await get_tree().create_timer(0.65).timeout
	assert_signal_emit_count(behavior, "output_raised", 1)
	assert_true(clock.is_stopped())
	assert_eq(behavior.get_node("Readout").text, "0.00s", "Completed single shots display zero")
	behavior.receive("stop")
	behavior.receive("start")
	assert_false(clock.is_stopped(), "Start after Stop also restarts a completed timer")
	await get_tree().create_timer(0.65).timeout
	assert_signal_emit_count(behavior, "output_raised", 2)
	behavior.reset()
	assert_eq(behavior.get_node("Readout").text, "0.50s", "Build reset restores the ready interval")

func test_configuration_and_reset_leave_the_clock_stopped() -> void:
	var behavior := make_timer({"frequency": 0.5})
	var clock := behavior.get_node("Timer") as Timer
	assert_true(clock.is_stopped())
	await get_tree().create_timer(0.15).timeout
	assert_signal_not_emitted(behavior, "output_raised")
	assert_false(behavior.get_node("Housing/Indicator").visible)
	behavior.start_run()
	assert_false(clock.is_stopped())
	await get_tree().create_timer(0.65).timeout
	assert_signal_emitted_with_parameters(behavior, "output_raised", ["tick", null])
	behavior.reset()
	assert_true(clock.is_stopped())
	assert_false(behavior.active)
	assert_eq(behavior.get_node("ClockHand").rotation.y, 0.0)
	var emissions: int = get_signal_emit_count(behavior, "output_raised")
	await get_tree().create_timer(0.15).timeout
	assert_eq(get_signal_emit_count(behavior, "output_raised"), emissions)

func test_simulation_pause_preserves_time_and_does_not_override_stop_input() -> void:
	var behavior := make_timer({"frequency": 2.0})
	var clock := behavior.get_node("Timer") as Timer
	behavior.start_run()
	await get_tree().create_timer(0.05).timeout
	behavior.active = false
	var remaining := clock.time_left
	await get_tree().create_timer(0.15).timeout
	assert_eq(clock.time_left, remaining)
	assert_false(behavior.get_node("Housing/Indicator").visible)
	behavior.active = true
	await get_tree().create_timer(0.05).timeout
	assert_lt(clock.time_left, remaining)
	behavior.receive("stop")
	behavior.active = false
	behavior.active = true
	remaining = clock.time_left
	await get_tree().create_timer(0.1).timeout
	assert_eq(clock.time_left, remaining, "Resuming simulation must preserve a wired Stop command")
	behavior.receive("start")
	await get_tree().create_timer(0.05).timeout
	assert_lt(clock.time_left, remaining)

func test_manual_single_shot_disabled_and_preview_lifecycle() -> void:
	var behavior := make_timer({"frequency": 0.5, "auto_start": false, "loop": false})
	var clock := behavior.get_node("Timer") as Timer
	behavior.start_run()
	assert_true(clock.is_stopped())
	behavior.receive("start")
	await get_tree().create_timer(0.65).timeout
	assert_signal_emit_count(behavior, "output_raised", 1)
	assert_true(clock.is_stopped())
	behavior.receive("reset")
	assert_false(clock.is_stopped())
	behavior.configure({"frequency": 0.5, "enabled": false})
	behavior.start_run()
	assert_true(clock.is_stopped())
	behavior.configure({"frequency": 0.5})
	behavior.preview_only = true
	behavior.start_run()
	assert_false(behavior.active)
	assert_true(clock.is_stopped())

func test_wiring_owner_starts_pauses_stops_and_resets_the_timer() -> void:
	var piece := BuildingPiece.new()
	add_child_autoqfree(piece)
	var definition := PieceCatalog.new().get_piece("logic-timer")
	piece.setup(definition, false, {"frequency": 2.0})
	var behavior := piece.behaviors[0]
	var clock := behavior.get_node("Timer") as Timer
	var wiring: PieceWiring = autofree(PieceWiring.new())
	var pieces: Array[BuildingPiece] = [piece]
	wiring.start(pieces)
	assert_false(clock.is_stopped())
	wiring.set_paused(true)
	var remaining := clock.time_left
	await get_tree().create_timer(0.1).timeout
	assert_eq(clock.time_left, remaining)
	wiring.set_paused(false)
	await get_tree().create_timer(0.05).timeout
	assert_lt(clock.time_left, remaining)
	wiring.stop()
	remaining = clock.time_left
	await get_tree().create_timer(0.1).timeout
	assert_eq(clock.time_left, remaining, "Run completion stops the clock too")
	wiring.reset(pieces)
	assert_true(clock.is_stopped())
	for id in ["logic-timer", "logic-delay"]:
		var thumbnail := PieceCatalog.new().get_piece(id).thumbnail
		assert_not_null(thumbnail, id + " has a loaded catalog thumbnail")
		if thumbnail: assert_gt(thumbnail.get_width(), 0)
