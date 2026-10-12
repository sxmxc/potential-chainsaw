class_name ConstructionInput
extends RefCounted

const SHORTCUTS = {
	"cancel": [KEY_ESCAPE], "remove": [KEY_DELETE], "rotate": [KEY_R],
	"move_piece": [KEY_M], "select_tool": [KEY_V], "grid": [KEY_G],
	"snap": [KEY_C], "frame": [KEY_F], "frame_all": [KEY_HOME],
	"height_up": [KEY_PAGEUP], "height_down": [KEY_PAGEDOWN],
	"height_up_fine": [KEY_PAGEUP, false, true], "height_down_fine": [KEY_PAGEDOWN, false, true],
	"undo": [KEY_Z, true], "redo": [KEY_Y, true], "duplicate": [KEY_D, true],
	"save_track": [KEY_S, true], "test_track": [KEY_SPACE],
	"select_all": [KEY_A, true], "cycle_snap": [KEY_TAB]
}

static func install() -> void:
	for action in SHORTCUTS:
		var name = "build_" + action
		if InputMap.has_action(name): continue
		InputMap.add_action(name)
		var data: Array = SHORTCUTS[action]
		var event = InputEventKey.new()
		event.keycode = data[0]
		event.ctrl_pressed = data.size() > 1 and bool(data[1])
		event.shift_pressed = data.size() > 2 and bool(data[2])
		InputMap.action_add_event(name,event)
	var shift_redo = InputEventKey.new()
	shift_redo.keycode = KEY_Z
	shift_redo.ctrl_pressed = true
	shift_redo.shift_pressed = true
	InputMap.action_add_event("build_redo",shift_redo)

static func typing(viewport: Viewport) -> bool:
	var focus = viewport.gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or focus is SpinBox

static func height_text(value: float) -> String:
	return ("%.3f" % value).rstrip("0").rstrip(".")
