extends RefCounted

const NUMBERS = {
	"airflow": {"power": ["Air power (N)", 1.2, 0, 5, 0.05], "range": ["Effective range (m)", 4, 0.5, 10, 0.25]},
	"rotor": {"angular_speed": ["Paddle speed (rad/s)", 1.3, -6, 6, 0.1]},
	"gate": {"delay": ["Timed opening (s; 0 = external)", 0, 0, 60, 0.25], "auto_close": ["Close after (s; 0 = stay open)", 0, 0, 60, 0.25]},
	"launcher": {"strength": ["Launch speed added (m/s)", 4, 0.5, 8, 0.1], "angle": ["Launch angle (degrees)", 25, 0, 65, 1]},
	"start": {"release_speed": ["Launch speed", 1.4, 0, 6, 0.1], "quantity": ["Marbles", 1, 1, 20, 1], "interval": ["Release interval (s)", 1, 0.6, 20, 0.1], "start_delay": ["First release delay (s)", 0, 0, 60, 0.25]},
	"elevator": {"elevator_height": ["Elevator rise", ElevatorDefinition.DEFAULT_HEIGHT, ElevatorDefinition.MIN_HEIGHT, ElevatorDefinition.MAX_HEIGHT, ElevatorDefinition.HEIGHT_STEP], "elevator_speed": ["Bucket travel speed", ElevatorDefinition.DEFAULT_SPEED, ElevatorDefinition.MIN_SPEED, ElevatorDefinition.MAX_SPEED, 0.05]},
	"resizable_support": {"support_height": ["Support bearing height", SupportDefinition.DEFAULT_HEIGHT, SupportDefinition.MIN_HEIGHT, SupportDefinition.MAX_HEIGHT, SupportDefinition.HEIGHT_STEP]}
}
const FLAGS = {
	"airflow": {"enabled": ["Initially enabled", true], "reverse": ["Reverse airflow", false]},
	"rotor": {"enabled": ["Initially spinning", true]},
	"gate": {"open": ["Initially open", false]},
	"diverter": {"left": ["Route left", false], "alternating": ["Alternate after crossing", false]},
	"launcher": {"enabled": ["Enabled", true], "external": ["Wait for Fire trigger", false], "auto_rearm": ["Automatically rearm", true]},
	"sensor": {"detect_exit": ["Emit exit event", false]},
	"resizable_support": {"support_double_top": ["Double top", false]}
}

static func normalized(behavior: String, settings: Dictionary) -> Dictionary:
	var result = settings.duplicate(true)
	for key in NUMBERS.get(behavior, {}):
		if not result.has(key): continue
		var field: Array = NUMBERS[behavior][key]
		var value = result[key]
		if not (value is float or value is int) or not is_finite(float(value)): value = field[1]
		result[key] = clampf(float(value), field[2], field[3])
	for key in FLAGS.get(behavior, {}):
		if result.has(key): result[key] = bool(result[key])
	if result.has("release_speed"):
		var value = result.release_speed
		if not (value is float or value is int) or not is_finite(float(value)): value = 1.4
		result.release_speed = clampf(float(value), 0, 6)
	return result
