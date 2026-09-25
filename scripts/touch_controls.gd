class_name TouchControls
extends CanvasLayer
## On-screen controls for phones and tablets: an analog thumbstick, a look-drag
## region, and a cluster of action buttons.
##
## All screen touches are routed through this node's _input and hit-tested
## manually rather than relying on Control focus or emulated mouse events. That
## gives real multi-touch: the player can steer with the left thumb, swing the
## camera with the right, and hit a button, all in the same frame.
##
## Button presses are injected as InputEventAction via Boot.press_action(), so
## Player's existing keyboard handlers work unchanged.

const STICK_CENTER := Vector2(170, -170)   # y is relative to bottom
const STICK_BASE := 105.0
const STICK_KNOB := 44.0
const STICK_DEADZONE := 0.14
const LOOK_SENS := 1.05

var enabled := false
var input_allowed := false

var _painter: Control
var _buttons: Array = []
var _stick_idx := -1
var _stick_origin := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_idx := -1
var _look_last := Vector2.ZERO
var _aim_on := false


func _ready() -> void:
	layer = 3
	_painter = _Painter.new()
	_painter.owner_ref = self
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painter)

	_buttons = [
		_mk("ATTACK", "attack_light", Vector2(-105, -105), 58, false),
		_mk("HEAVY", "attack_heavy", Vector2(-238, -128), 45, false),
		_mk("RECALL", "recall", Vector2(-360, -105), 45, false),
		_mk("DODGE", "dodge", Vector2(-122, -240), 45, false),
		_mk("AIM", "aim", Vector2(-252, -252), 45, true),
	]

	visible = false
	# Show immediately on genuine touch hardware; otherwise wait for a real
	# touch event (covers desktop browsers that report touch inconsistently).
	if DisplayServer.is_touchscreen_available():
		_activate()


func _mk(label: String, action: String, offset: Vector2, radius: float,
		toggle: bool) -> Dictionary:
	return {
		"label": label, "action": action, "offset": offset,
		"radius": radius, "toggle": toggle,
		"pressed": false, "idx": -1,
	}


func _activate() -> void:
	if enabled:
		return
	enabled = true
	visible = true
	Boot.touch_active = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_painter.queue_redraw()


# ------------------------------------------------------------------ geometry

func _vp() -> Vector2:
	return _painter.size if _painter != null else Vector2(1280, 720)


func _stick_pos() -> Vector2:
	var v := _vp()
	return Vector2(STICK_CENTER.x, v.y + STICK_CENTER.y)


func _button_pos(b: Dictionary) -> Vector2:
	var v := _vp()
	return v + (b["offset"] as Vector2)


func set_input_allowed(allowed: bool) -> void:
	input_allowed = allowed
	visible = enabled and allowed
	if not allowed:
		_stick_idx = -1
		_look_idx = -1
		_stick_vec = Vector2.ZERO
		_aim_on = false
		for button in _buttons:
			button["pressed"] = false
			button["idx"] = -1
		Boot.reset_virtual_input()
		if _painter != null:
			_painter.queue_redraw()


# --------------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not input_allowed:
		return
	if event is InputEventScreenTouch:
		if not enabled:
			_activate()
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		if enabled:
			_on_drag(event as InputEventScreenDrag)


func _on_touch(ev: InputEventScreenTouch) -> void:
	if ev.pressed:
		# buttons take priority
		for b in _buttons:
			if ev.position.distance_to(_button_pos(b)) <= b["radius"] * 1.18:
				_press(b, ev.index)
				get_viewport().set_input_as_handled()
				return
		# then the stick, with a generous grab area
		if _stick_idx == -1 and \
				ev.position.distance_to(_stick_pos()) <= STICK_BASE * 1.75:
			_stick_idx = ev.index
			_stick_origin = _stick_pos()
			_update_stick(ev.position)
			get_viewport().set_input_as_handled()
			return
		# anything else on the right side becomes a look drag
		if _look_idx == -1 and ev.position.x > _vp().x * 0.30:
			_look_idx = ev.index
			_look_last = ev.position
			get_viewport().set_input_as_handled()
	else:
		for b in _buttons:
			if b["idx"] == ev.index:
				_release(b)
				return
		if ev.index == _stick_idx:
			_stick_idx = -1
			_stick_vec = Vector2.ZERO
			Boot.touch_move = Vector2.ZERO
			_painter.queue_redraw()
		elif ev.index == _look_idx:
			_look_idx = -1


func _on_drag(ev: InputEventScreenDrag) -> void:
	if ev.index == _stick_idx:
		_update_stick(ev.position)
		get_viewport().set_input_as_handled()
	elif ev.index == _look_idx:
		Boot.push_look((ev.position - _look_last) * LOOK_SENS)
		_look_last = ev.position
		get_viewport().set_input_as_handled()


func _update_stick(pos: Vector2) -> void:
	var d := (pos - _stick_origin) / STICK_BASE
	if d.length() < STICK_DEADZONE:
		d = Vector2.ZERO
	else:
		# rescale past the deadzone so small pushes still give fine control
		d = d.normalized() * ((d.length() - STICK_DEADZONE)
				/ (1.0 - STICK_DEADZONE))
	_stick_vec = d.limit_length(1.0)
	Boot.touch_move = _stick_vec
	_painter.queue_redraw()


func _press(b: Dictionary, idx: int) -> void:
	b["idx"] = idx
	if b["toggle"]:
		_aim_on = not _aim_on
		b["pressed"] = _aim_on
		if _aim_on:
			Boot.press_action(b["action"])
		else:
			Boot.release_action(b["action"])
	else:
		b["pressed"] = true
		Boot.press_action(b["action"])
	Sfx.play_2d("ui_click", -12.0)
	_painter.queue_redraw()


func _release(b: Dictionary) -> void:
	b["idx"] = -1
	if not b["toggle"]:
		b["pressed"] = false
		Boot.release_action(b["action"])
	_painter.queue_redraw()


func aiming() -> bool:
	return _aim_on


# ------------------------------------------------------------------- painter

class _Painter extends Control:
	var owner_ref

	func _ready() -> void:
		resized.connect(queue_redraw)
		set_process(true)

	func _process(_d: float) -> void:
		# cheap redraw: only the stick knob and button tints animate
		if owner_ref != null and owner_ref.enabled:
			queue_redraw()

	func _draw() -> void:
		if owner_ref == null or not owner_ref.enabled:
			return
		var font := ThemeDB.fallback_font
		var base: Vector2 = owner_ref._stick_pos()

		# --- thumbstick
		draw_circle(base, owner_ref.STICK_BASE, Color(0.02, 0.03, 0.05, 0.34))
		draw_arc(base, owner_ref.STICK_BASE, 0, TAU, 48,
				Color(0.75, 0.86, 1.0, 0.30), 2.5, true)
		var knob: Vector2 = base + owner_ref._stick_vec * owner_ref.STICK_BASE
		draw_circle(knob, owner_ref.STICK_KNOB, Color(0.60, 0.82, 1.0, 0.40))
		draw_arc(knob, owner_ref.STICK_KNOB, 0, TAU, 32,
				Color(0.85, 0.94, 1.0, 0.55), 2.0, true)

		# --- action buttons
		for b in owner_ref._buttons:
			var c: Vector2 = owner_ref._button_pos(b)
			var r: float = b["radius"]
			var on: bool = b["pressed"]
			# Dark translucent fill rather than translucent white: the buttons sit
			# over snow and brazier light, and a light fill left the labels
			# illegible against bright ground.
			var fill := (Color(0.30, 0.62, 0.86, 0.55) if on
					else Color(0.02, 0.03, 0.05, 0.42))
			var ring := (Color(0.85, 0.96, 1.0, 0.95) if on
					else Color(0.80, 0.88, 1.0, 0.55))
			draw_circle(c, r, fill)
			draw_arc(c, r, 0, TAU, 40, ring, 2.5, true)

			var label: String = b["label"]
			if b["action"] == "attack_light" and owner_ref.aiming():
				label = "THROW"
			var fs := 15
			var w := font.get_string_size(label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, c + Vector2(-w * 0.5, 5.0), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
					Color(0.93, 0.97, 1.0, 0.92))
