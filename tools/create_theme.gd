extends SceneTree

func _initialize() -> void:
	var theme=Theme.new()
	var font=SystemFont.new()
	font.font_names=PackedStringArray(["Segoe UI","DejaVu Sans"])
	theme.default_font=font
	theme.default_font_size=16
	for type in ["Label","Button","LineEdit","OptionButton","CheckButton","SpinBox","ItemList","PopupMenu"]:
		theme.set_color("font_color",type,Color("e6f2ed"))
		theme.set_color("font_disabled_color",type,Color("71858a"))
	for type in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type,box(Color("223840"),12))
		theme.set_stylebox("hover",type,box(Color("35545b"),12))
		theme.set_stylebox("pressed",type,box(Color("327b71"),12))
		theme.set_stylebox("disabled",type,box(Color("1d3037"),12))
		var focus=box(Color.TRANSPARENT,12)
		focus.border_color=Color("80cdbb")
		focus.set_border_width_all(2)
		theme.set_stylebox("focus",type,focus)
		theme.set_color("font_hover_color",type,Color("e6f2ed"))
		theme.set_color("font_pressed_color",type,Color("e6f2ed"))
	for type in ["PrimaryButton","SecondaryButton","ToolbarButton","DangerButton","ToolboxButton","PieceCard","QuietButton"]:
		theme.set_type_variation(type,"Button")
	theme.set_stylebox("normal","PrimaryButton",box(Color("56d6a3"),14))
	theme.set_stylebox("hover","PrimaryButton",box(Color("79e8bc"),14))
	theme.set_stylebox("pressed","PrimaryButton",box(Color("3ba984"),14))
	theme.set_font_size("font_size","PrimaryButton",17)
	for state in ["font_color","font_hover_color","font_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color"]:
		theme.set_color(state,"PrimaryButton",Color("092a27"))
	for type in ["ToolboxButton","PieceCard"]:
		theme.set_stylebox("normal",type,box(Color("223840"),6))
		theme.set_stylebox("hover",type,box(Color("35545b"),6))
		var selected=box(Color("28554f"),6)
		selected.border_color=Color("56d6a3")
		selected.set_border_width_all(2)
		theme.set_stylebox("pressed",type,selected)
	theme.set_stylebox("normal","DangerButton",box(Color("462c35"),10))
	theme.set_stylebox("hover","DangerButton",box(Color("70404a"),10))
	theme.set_stylebox("pressed","DangerButton",box(Color("a4545d"),10))
	theme.set_stylebox("normal","QuietButton",box(Color.TRANSPARENT,10))
	theme.set_stylebox("hover","QuietButton",box(Color("253e45"),10))
	theme.set_stylebox("normal","LineEdit",box(Color("142b33"),12))
	theme.set_stylebox("focus","LineEdit",box(Color("172f37"),12))
	theme.set_color("font_placeholder_color","LineEdit",Color("9cbbbd"))
	theme.set_color("caret_color","LineEdit",Color("80cdbb"))
	for type in ["PanelContainer","PopupPanel","AcceptDialog"]:
		theme.set_stylebox("panel",type,surface(Color("12262e"),16))
	for type in ["SurfacePanel","ToolbarPanel","MenuPanel","ContextPanel"]:
		theme.set_type_variation(type,"PanelContainer")
	theme.set_stylebox("panel","ToolbarPanel",surface(Color("12262e"),10))
	theme.set_stylebox("panel","ContextPanel",surface(Color("12262e"),12))
	theme.set_stylebox("panel","MenuPanel",box(Color(0.055,0.11,0.14,0.88),24))
	theme.set_stylebox("embedded_border","Window",surface(Color("12262e"),12))
	theme.set_color("title_color","Window",Color("e6f2ed"))
	theme.set_stylebox("panel","ItemList",box(Color("223840"),12))
	theme.set_stylebox("selected","ItemList",box(Color("28554f"),12))
	theme.set_stylebox("selected_focus","ItemList",box(Color("28554f"),12))
	theme.set_color("font_selected_color","ItemList",Color("e6f2ed"))
	theme.set_constant("v_separation","ItemList",16)
	theme.set_stylebox("panel","PopupMenu",surface(Color("12262e"),12))
	theme.set_stylebox("hover","PopupMenu",box(Color("35545b"),8))
	theme.set_stylebox("slider","HSlider",box(Color("35545b"),4))
	theme.set_stylebox("grabber_area","HSlider",box(Color("56d6a3"),4))
	theme.set_stylebox("grabber_area_highlight","HSlider",box(Color("79e8bc"),4))
	theme.set_color("marquee_fill","ConstructionOverlay",Color(0.4,0.65,0.86,0.16))
	theme.set_color("marquee_border","ConstructionOverlay",Color("80cdbb"))
	theme.set_color("connector_fill","ConstructionOverlay",Color("12262e"))
	theme.set_color("connector_available","ConstructionOverlay",Color("80cdbb"))
	theme.set_color("connector_hover","ConstructionOverlay",Color("ffd17a"))
	theme.set_color("connector_active","ConstructionOverlay",Color("56d6a3"))
	theme.set_constant("connector_radius","ConstructionOverlay",8)
	theme.set_stylebox("panel","TabContainer",box(Color("12262e"),12))
	for type in ["TabContainer","TabBar"]:
		theme.set_stylebox("tab_selected",type,box(Color("35545b"),10))
		theme.set_stylebox("tab_unselected",type,box(Color("223840"),10))
		theme.set_stylebox("tab_hovered",type,box(Color("35545b"),10))
		theme.set_color("font_selected_color",type,Color("e6f2ed"))
		theme.set_color("font_unselected_color",type,Color("9cbbbd"))
		theme.set_color("font_hovered_color",type,Color("e6f2ed"))
	for data in [["PanelTitle",18,"e6f2ed"],["PanelHeading",18,"e6f2ed"],["TrackTitle",18,"e6f2ed"],["InspectorTitle",21,"e6f2ed"],["DialogTitle",26,"e6f2ed"],["BrandTitle",54,"e6f2ed"],["MutedLabel",16,"9cbbbd"],["SmallMutedLabel",14,"9cbbbd"],["CardLabel",13,"e6f2ed"],["AccentSmallLabel",14,"79e8bc"],["AccentLabel",16,"79e8bc"],["SuccessLabel",17,"79e8bc"],["ErrorLabel",16,"ff8790"]]:
		theme.set_type_variation(data[0],"Label")
		theme.set_font_size("font_size",data[0],data[1])
		theme.set_color("font_color",data[0],Color(data[2]))
	if ResourceLoader.exists("res://assets/font/DIMITRI_.TTF"):
		theme.set_font("font","BrandTitle",load("res://assets/font/DIMITRI_.TTF"))
	for type in ["VBoxContainer","HBoxContainer"]: theme.set_constant("separation",type,8)
	theme.set_constant("h_separation","GridContainer",8)
	theme.set_constant("v_separation","GridContainer",8)
	for data in [["HUDMargin",20],["PanelMargin",16],["CardMargin",6],["MenuMargin",40]]:
		theme.set_type_variation(data[0],"MarginContainer")
		for side in ["left","right","top","bottom"]: theme.set_constant("margin_"+side,data[0],data[1])
	for data in [["HUDVBox","VBoxContainer",16],["HUDHBox","HBoxContainer",16],["MenuVBox","VBoxContainer",24],["CompactVBox","VBoxContainer",4]]:
		theme.set_type_variation(data[0],data[1])
		theme.set_constant("separation",data[0],data[2])
	for name in ["undo","redo","play","pause","grid","snap","rotate","delete","move"]:
		var icon_path="res://assets/ui/icons/"+name+".svg"
		if ResourceLoader.exists(icon_path): theme.set_icon(name,"SandboxIcons",load(icon_path))
	var path="res://resources/sandbox_theme.tres"
	var uid=ResourceLoader.get_resource_uid(path)
	ResourceSaver.save(theme,path)
	if uid!=-1: ResourceSaver.set_uid(path,uid)
	quit()

func box(color: Color, padding: float) -> StyleBoxFlat:
	var style=StyleBoxFlat.new()
	style.bg_color=color
	style.set_corner_radius_all(12)
	style.content_margin_left=padding
	style.content_margin_right=padding
	style.content_margin_top=padding
	style.content_margin_bottom=padding
	return style

func surface(color: Color,padding: float) -> StyleBoxFlat:
	var style=box(color,padding)
	style.set_corner_radius_all(18)
	style.shadow_color=Color(0.0,0.0,0.0,0.18)
	style.shadow_size=5
	style.shadow_offset=Vector2(0,3)
	return style
