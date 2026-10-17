extends GutTest

func test_deliveries_count_distinct_marbles_at_the_required_target_and_source() -> void:
	var objectives := PuzzleObjectives.new()
	var goal := {"target": "finish", "source": "release", "count": 2}
	objectives.reset([goal])
	objectives.delivered("elsewhere", "release:0", "release")
	objectives.delivered("finish", "other:0", "other")
	assert_eq(objectives.progress(goal), 0)
	objectives.delivered("finish", "release:1", "release")
	objectives.delivered("finish", "release:1", "release")
	assert_eq(objectives.progress(goal), 1)
	assert_false(objectives.satisfied(0))
	objectives.delivered("finish", "release:2", "release")
	assert_eq(objectives.progress(goal), 2)
	assert_eq(objectives.progress({"target": "finish"}), 3, "Omitting source includes all releases")
	assert_true(objectives.satisfied(0))

func test_activation_requires_the_named_target_and_port_but_not_a_count() -> void:
	var objectives := PuzzleObjectives.new()
	var goal := {"type": "activate", "target": "gate", "event": "opened", "count": 3}
	objectives.reset([goal])
	objectives.activated("gate", "closed")
	objectives.activated("other", "opened")
	assert_true(objectives.has_activity("gate"), "Guidance can observe any target activity")
	assert_eq(objectives.progress(goal), 0)
	assert_false(objectives.satisfied(0))
	objectives.activated("gate", "opened")
	assert_eq(objectives.progress(goal), 1)
	assert_true(objectives.satisfied(0), "Activation goals record occurrence, not frequency")
	assert_eq(objectives.progress({"type": "activate", "target": "gate"}), 0)
	objectives.activated("gate", "activated")
	assert_eq(objectives.progress({"type": "activate", "target": "gate"}), 1)

func test_all_goals_and_deadlines_are_required_without_erasing_visible_progress() -> void:
	var objectives := PuzzleObjectives.new()
	var delivery := {"target": "finish", "time_limit": 5}
	var activation := {"type": "activate", "target": "gate"}
	objectives.reset([delivery, activation])
	objectives.delivered("finish", "marble", "release")
	assert_false(objectives.satisfied(1))
	objectives.activated("gate", "activated")
	assert_true(objectives.satisfied(5))
	assert_false(objectives.satisfied(5.01))
	assert_eq(objectives.progress(delivery), 1)
	assert_eq(objectives.progress(activation), 1)

func test_notifications_observe_current_records_and_reset_clears_the_run() -> void:
	var objectives := PuzzleObjectives.new()
	var goal := {"target": "finish"}
	var observed: Array[int] = []
	var observe := func(): observed.append(objectives.progress(goal))
	objectives.changed.connect(observe)
	objectives.reset([goal])
	objectives.delivered("finish", "marble", "release")
	objectives.activated("gate", "activated")
	objectives.reset([])
	objectives.changed.disconnect(observe)
	assert_eq(observed, [0, 1, 1, 0])
	assert_false(objectives.has_activity("gate"))
	assert_false(objectives.satisfied(0), "An empty goal list cannot complete a puzzle")
