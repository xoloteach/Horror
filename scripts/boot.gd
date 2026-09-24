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
	"ui_release":    [KEY_ESCAPE],
}

const MOUSE_ACTIONS := {
	"attack_light": MOUSE_BUTTON_LEFT,
	"aim":          MOUSE_BUTTON_RIGHT,
	"recall_mouse": MOUSE_BUTTON_MIDDLE,
}


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
	return touch_active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


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


## Three buses so impacts, voice and ambience can be mixed independently.
## Levels are set once here; every play call routes through one of them.
func _setup_buses() -> void:
	var wanted := [
		{"name": "Sfx", "db": -1.0},
		{"name": "Voice", "db": -4.5},
		{"name": "Ambience", "db": -13.0},
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
