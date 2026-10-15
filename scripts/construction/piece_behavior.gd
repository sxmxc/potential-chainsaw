class_name PieceBehavior
extends Node3D

signal output_raised(port: String, value: Variant)
signal activity_changed(running: bool)
@export var configuration_fields: Array[PieceSetting] = []
var preview_only: bool = false
var active: bool = false:
	set(running):
		if active == running: return
		active = running
		activity_changed.emit(running)
var enabled: bool = true
var config: Dictionary = {}
var inputs: Dictionary = {}
var outputs: Array[String] = []
var initializing_signals: bool = false

func configure(settings: Dictionary) -> void:
	config = settings.duplicate(true)
	reset()

func start_run() -> void:
	active = not preview_only

## Optional world-space path shown by the shared build overlay for selection/preview.
func build_trajectory(_excluded: Array[RID] = []) -> PackedVector3Array:
	return PackedVector3Array()

## Called after simulation has settled the initial persistent-state wires.
func signals_ready() -> void:
	initializing_signals = false

func reset() -> void:
	active = false
	initializing_signals = false
	enabled = bool(config.get("enabled", true))
	input_values = state_inputs.duplicate()
	output_values = state_outputs.duplicate()

# State ports carry latched values; ordinary inputs/outputs are event pulses.
@export var state_inputs: Dictionary[String, Variant] = {}
@export var state_outputs: Dictionary[String, Variant] = {}
var input_values: Dictionary = {}
var output_values: Dictionary = {}

func receive(port: String, value: Variant = null) -> bool:
	if preview_only or not active or not inputs.has(port): return false
	if state_inputs.has(port):
		var previous: Variant = input_values.get(port, state_inputs[port])
		if typeof(previous) == typeof(value) and previous == value: return true
		input_values[port] = value
	inputs[port].call(value)
	if "activated" in outputs: emit_output("activated")
	return true

func emit_output(port: String, value: Variant = null) -> void:
	if state_outputs.has(port):
		var previous: Variant = output_values.get(port, state_outputs[port])
		if typeof(previous) == typeof(value) and previous == value: return
		output_values[port] = value
	elif port not in outputs:
		push_error("Undeclared output: " + port)
		return
	output_raised.emit(port, value)

func output_ports() -> Array:
	return outputs + state_outputs.keys()

func is_marble(body: Node3D) -> bool:
	return body is RigidBody3D and body.collision_layer & 2 != 0
