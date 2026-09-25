extends Node
## Registers the input map and audio buses at runtime.
##
## Actions are built here rather than serialised into project.godot: the
## InputEvent text format is fragile to hand-author, and doing it in code keeps
## the whole control scheme readable in one place.

const ACTIONS := {
	"move_forward":  [KEY_W, KEY_UP],
	"move_back":     [KEY_S, KEY_DOWN],
	"move_left":     [KEY_A, KEY_LEFT],
	"move_right":    [KEY_D, KEY_RIGHT],
	"dodge":         [KEY_SPACE],
	"attack_heavy":  [KEY_F],
	"recall":        [KEY_R, KEY_Q],
	"restart":       [KEY_ENTER, KEY_KP_ENTER],
	"pause":         [KEY_P],
	"shoulder_swap": [KEY_C],
	"look_left":     [],
	"look_right":    [],
	"look_up":       [],
	"look_down":     [],
	"ui_release":    [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"attack_light": MOUSE_BUTTON_LEFT,
	"aim":          MOUSE_BUTTON_RIGHT,
	"recall_mouse": MOUSE_BUTTON_MIDDLE,
}

const JOY_BUTTON_ACTIONS := {
	"attack_light": JOY_BUTTON_RIGHT_SHOULDER,
	"attack_heavy": JOY_BUTTON_Y,
	"recall": JOY_BUTTON_B,
	"dodge": JOY_BUTTON_A,
	"pause": JOY_BUTTON_START,
	"shoulder_swap": JOY_BUTTON_LEFT_SHOULDER,
}

const JOY_AXIS_ACTIONS := [
	["move_left", JOY_AXIS_LEFT_X, -1.0],
	["move_right", JOY_AXIS_LEFT_X, 1.0],
	["move_forward", JOY_AXIS_LEFT_Y, -1.0],
	["move_back", JOY_AXIS_LEFT_Y, 1.0],
	["look_left", JOY_AXIS_RIGHT_X, -1.0],
	["look_right", JOY_AXIS_RIGHT_X, 1.0],
	["look_up", JOY_AXIS_RIGHT_Y, -1.0],
	["look_down", JOY_AXIS_RIGHT_Y, 1.0],
	["aim", JOY_AXIS_TRIGGER_LEFT, 1.0],
]


# --- touch/virtual input state, written by TouchControls and read by the
# --- player and camera so that touch is a peer of keyboard+mouse, not a hack.
var touch_active := false
var touch_move := Vector2.ZERO
var _touch_look := Vector2.ZERO


func _enter_tree() -> void:
	_setup_input()
	_setup_buses()


## Merged movement axis: keyboard WASD plus the virtual stick.
func move_axis() -> Vector2:
	var kb := Input.get_vector("move_left", "move_right",
			"move_forward", "move_back")
	if touch_move.length_squared() > 0.0025:
		return (kb + touch_move).limit_length(1.0)
	return kb


func push_look(delta_px: Vector2) -> void:
	_touch_look += delta_px


## Camera drains this each frame and adds it to mouse motion.
func consume_look() -> Vector2:
	var v := _touch_look
	_touch_look = Vector2.ZERO
	return v


## True when the player can act without the mouse being captured.
func input_unlocked() -> bool:
	return touch_active or not Input.get_connected_joypads().is_empty() \
			or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Synthesise a real action event so existing _unhandled_input handlers and
## Input.is_action_pressed() both see virtual button presses.
func press_action(action: String, strength := 1.0) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	ev.strength = strength
	Input.parse_input_event(ev)


func release_action(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


## Autoload-safe session reset: scene reloads must never inherit a latched touch
## aim/button or stale look delta from the previous run.
func reset_virtual_input() -> void:
	touch_move = Vector2.ZERO
	_touch_look = Vector2.ZERO
	for action in ["aim", "attack_light", "attack_heavy", "recall",
			"recall_mouse", "dodge"]:
		Input.action_release(action)


func _setup_input() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)

	for action in MOUSE_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_ACTIONS[action]
		InputMap.action_add_event(action, ev)

	for action in JOY_BUTTON_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var button := InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_ACTIONS[action]
		InputMap.action_add_event(action, button)

	for binding in JOY_AXIS_ACTIONS:
		var action: String = binding[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.18)
		var motion := InputEventJoypadMotion.new()
		motion.axis = binding[1]
		motion.axis_value = binding[2]
		InputMap.action_add_event(action, motion)


## Three buses so impacts, voice and ambience can be mixed independently.
## Levels are set once here; every play call routes through one of them.
func _setup_buses() -> void:
	var wanted := [
		{"name": "Sfx", "db": -3.0},
		{"name": "Voice", "db": -4.0},
		{"name": "Ambience", "db": -12.0},
		{"name": "Music", "db": -9.0},
		{"name": "UI", "db": -4.0},
	]
	for entry in wanted:
		if AudioServer.get_bus_index(entry["name"]) != -1:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, entry["name"])
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, entry["db"])
	AudioServer.set_bus_volume_db(0, -3.0)
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -5.0
		AudioServer.add_bus_effect(0, limiter)
