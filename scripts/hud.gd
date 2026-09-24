# GameHUD: CanvasLayer with HP bar, wave/kill counters, crosshair,
# damage vignette, controls hint, and game-over overlay.
class_name GameHUD
extends CanvasLayer

var hp_bar: ProgressBar
var wave_label: Label
var kills_label: Label
var crosshair: ColorRect
var vignette: ColorRect
var hint_label: Label
var gameover_panel: CenterContainer


func _ready() -> void:
	# HP bar
	var hp_title := Label.new()
	hp_title.text = "VITALITY"
	hp_title.position = Vector2(20, 8)
	add_child(hp_title)
	hp_bar = ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	hp_bar.position = Vector2(20, 28)
	hp_bar.custom_minimum_size = Vector2(260, 22)
	add_child(hp_bar)

	wave_label = Label.new()
	wave_label.text = "WAVE 0"
	wave_label.add_theme_font_size_override("font_size", 28)
	wave_label.anchor_left = 0.5
	wave_label.anchor_right = 0.5
	wave_label.offset_left = -80
	wave_label.offset_right = 80
	wave_label.offset_top = 12
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(wave_label)

	kills_label = Label.new()
	kills_label.text = "KILLS 0"
	kills_label.add_theme_font_size_override("font_size", 22)
	kills_label.anchor_left = 1.0
	kills_label.anchor_right = 1.0
	kills_label.offset_left = -180
	kills_label.offset_right = -20
	kills_label.offset_top = 16
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(kills_label)

	# crosshair (aim mode)
	crosshair = ColorRect.new()
	crosshair.color = Color(0.75, 0.9, 1.0, 0.95)
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -3
	crosshair.offset_top = -3
	crosshair.offset_right = 3
	crosshair.offset_bottom = 3
	crosshair.visible = false
	add_child(crosshair)

	# damage vignette
	vignette = ColorRect.new()
	vignette.color = Color(0.6, 0.02, 0.03, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	# controls hint
	hint_label = Label.new()
	hint_label.text = "WASD move · Mouse look · LMB attack · E heavy · F throw axe · R recall · RMB aim · Space dodge-roll · Shift sprint"
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = -460
	hint_label.offset_right = 460
	hint_label.offset_top = -52
	hint_label.offset_bottom = -28
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	_fade_hint()

	# game over
	gameover_panel = CenterContainer.new()
	gameover_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_panel.visible = false
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "YOU DIED"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.75, 0.1, 0.12))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "Press R to rise again"
	sub.add_theme_font_size_override("font_size", 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)
	panel.add_child(vbox)
	gameover_panel.add_child(panel)
	add_child(gameover_panel)


func _fade_hint() -> void:
	await get_tree().create_timer(10.0).timeout
	if not is_instance_valid(hint_label):
		return
	var tw := create_tween()
	tw.tween_property(hint_label, "modulate:a", 0.0, 2.0)


func set_hp(v: float, max_v: float) -> void:
	hp_bar.max_value = max_v
	hp_bar.value = v
	# flash red vignette
	vignette.color.a = 0.45
	var tw := create_tween()
	tw.tween_property(vignette, "color:a", 0.0, 0.5)


func set_wave(n: int) -> void:
	wave_label.text = "WAVE %d" % n


func set_kills(n: int) -> void:
	kills_label.text = "KILLS %d" % n


func set_crosshair(v: bool) -> void:
	crosshair.visible = v


func show_game_over() -> void:
	gameover_panel.visible = true
