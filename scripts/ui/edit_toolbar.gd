extends HFlowContainer
var build: BuildManager
func configure(manager: BuildManager) -> void:
	build=manager
	%Rotate.icon=get_theme_icon("rotate","SandboxIcons")
	%Move.icon=get_theme_icon("move","SandboxIcons")
	%Delete.icon=get_theme_icon("delete","SandboxIcons")
	%Rotate.pressed.connect(build.rotate_piece)
	%Move.pressed.connect(build.move_selected)
	%Duplicate.pressed.connect(func():build.move_selected(true))
	%Delete.pressed.connect(build.delete_selected)
	%Lower.pressed.connect(func():build.elevate_selected(-build.height_step(Input.is_key_pressed(KEY_SHIFT))))
	%Raise.pressed.connect(func():build.elevate_selected(build.height_step(Input.is_key_pressed(KEY_SHIFT))))
func refresh() -> void:
	visible=build.enabled and not build.connect_mode and build.chosen==null and build.selected!=null
	%Move.disabled=build.selected==null
	%Duplicate.disabled=build.selected==null
	%Delete.disabled=build.selected==null
	%Duplicate.visible=build.chosen==null
	%Delete.visible=build.chosen==null
	%SelectionCount.text="%d selected" % build.selection.size() if build.selected else "Placing "+build.chosen.display_name if build.chosen else ""
	%Lower.visible=build.selected!=null and build.chosen==null
	%Raise.visible=%Lower.visible
	%Lower.disabled=not permitted("move")
	%Raise.disabled=%Lower.disabled
	%Rotate.disabled=build.selected!=null and not permitted("rotate")
	%Duplicate.disabled=not permitted("duplicate")
	%Delete.disabled=not permitted("delete")

func permitted(action: String) -> bool:
	if not build.rules: return true
	for piece in build.selection:
		if not build.rules.permits(piece.instance_id,action): return false
	return true
