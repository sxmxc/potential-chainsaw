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
func refresh() -> void:
	visible=build.enabled and (build.chosen!=null or build.selected!=null)
	%Move.disabled=build.selected==null
	%Duplicate.disabled=build.selected==null
	%Delete.disabled=build.selected==null
	%Duplicate.visible=build.chosen==null
	%Delete.visible=build.chosen==null
	%SelectionCount.text="%d selected" % build.selection.size() if build.selected else "Placing "+build.chosen.display_name if build.chosen else ""
