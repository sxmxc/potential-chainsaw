extends Label

func _ready() -> void:
	if SteamClient.initialized:
		text = SteamClient.steam_name
	else:
		text = "Steam unavailable"
