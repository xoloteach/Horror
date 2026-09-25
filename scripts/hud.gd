class_name Hud
extends CanvasLayer
## Responsive production HUD, title, pause, boon and results flow.
## Uses Cinzel/Alegreya Sans (OFL) and a restrained iron/rune palette instead of
## fallback-font immediate-mode rectangles.

signal start_requested
signal boon_chosen(index: int)
signal restart_requested
signal pause_requested
signal resume_requested

const DISPLAY_FONT := preload("res://assets/production/fonts/Cinzel-Variable.ttf")
const BODY_FONT := preload("res://assets/production/fonts/AlegreyaSans-Regular.ttf")
const RUNE_FONT := preload("res://assets/production/fonts/NotoSansRunic-Regular.ttf")
const DIVIDER := preload("res://assets/production/ui/divider-fade-004.png")

const INK := Color(0.018, 0.025, 0.045, 0.94)
const IRON := Color(0.14, 0.18, 0.25, 0.94)
const BORDER := Color(0.38, 0.53, 0.72, 0.70)
const BONE := Color(0.88, 0.91, 0.94)
const MUTED := Color(0.57, 0.65, 0.74)
const RUNE := Color(0.36, 0.82, 1.0)
const BLOOD := Color(0.76, 0.055, 0.035)
const FOCUS := Color(0.15, 0.58, 0.92)
const GOLD := Color(0.95, 0.61, 0.18)

var health := 1.0
var health_shown := 1.0
var focus := 1.0
var axe_label := "IN HAND"
var axe_ready := true
var wave := 0
var enemies_left := 0
var kills := 0
var aim_blend := 0.0
var hurt_flash := 0.0
var game_over := false
var victory := false

var _rig: CameraRig
var _root: Control
var _combat_root: Control
var _overlay: Control
var _title_overlay: Control
var _boon_overlay: Control
var _pause_overlay: Control
var _settings_overlay: Control
var _settings_from_title := true
var _results_overlay: Control
var _vitality: ProgressBar
var _vitality_lag: ProgressBar
var _focus: ProgressBar
var _axe_status: Label
var _wave_title: Label
var _wave_subtitle: Label
var _kill_label: Label
var _message_panel: PanelContainer
var _message_label: Label
var _message_timer := 0.0
var _boss_panel: PanelContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_phase_label: Label
var _combo_label: Label
var _combo_timer := 0.0
var _boon_cards: HBoxContainer
var _result_title: Label
var _result_stats: Label
var _pause_button: Button


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 18
	_root.theme = theme
	add_child(_root)
	_build_combat_hud()
	_build_title()
	_build_boon_overlay()
	_build_pause_overlay()
	_build_settings_overlay()
	_build_results_overlay()


func bind(player: Player) -> void:
	_rig = player.rig
	player.health_changed.connect(_on_health)
	player.focus_changed.connect(_on_focus)
	player.combo_changed.connect(_on_combo)
	player.perfect_dodge.connect(_on_perfect_dodge)
	player.axe.state_changed.connect(_on_axe_state)
	_on_health(player.health, player.max_health)
	_on_focus(player.focus, player.max_focus)


# ------------------------------------------------------------------- builders

func _build_combat_hud() -> void:
	_combat_root = Control.new()
	_combat_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combat_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_combat_root)

	# Vitals plate: lower-left, safe-area inset.
	var vitals := _panel(Vector2(410, 126))
	vitals.anchor_top = 1.0
	vitals.anchor_bottom = 1.0
	vitals.offset_left = 26
	vitals.offset_top = -154
	vitals.offset_right = 436
	vitals.offset_bottom = -28
	_combat_root.add_child(vitals)
	var vitals_box := VBoxContainer.new()
	vitals_box.add_theme_constant_override("separation", 4)
	vitals.add_child(vitals_box)
	vitals_box.add_child(_small_heading("EIRIK · OATHBOUND"))
	_vitality_lag = _bar(BLOOD.darkened(0.48), 17)
	_vitality = _bar(BLOOD, 17)
	var health_stack := Control.new()
	health_stack.custom_minimum_size = Vector2(370, 18)
	health_stack.add_child(_vitality_lag)
	health_stack.add_child(_vitality)
	vitals_box.add_child(health_stack)
	var labels := HBoxContainer.new()
	labels.add_child(_caption("VITALITY"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(spacer)
	labels.add_child(_caption("RUNIC FOCUS · HEAVY COST 24"))
	vitals_box.add_child(labels)
	_focus = _bar(FOCUS, 9)
	vitals_box.add_child(_focus)

	# Axe plate: lower-right.
	var axe_panel := _panel(Vector2(300, 76))
	axe_panel.anchor_left = 1.0
	axe_panel.anchor_right = 1.0
	axe_panel.anchor_top = 1.0
	axe_panel.anchor_bottom = 1.0
	axe_panel.offset_left = -326
	axe_panel.offset_top = -104
	axe_panel.offset_right = -26
	axe_panel.offset_bottom = -28
	_combat_root.add_child(axe_panel)
	var axe_box := VBoxContainer.new()
	axe_box.add_theme_constant_override("separation", 2)
	axe_panel.add_child(axe_box)
	axe_box.add_child(_small_heading("LEVIATHAN"))
	_axe_status = Label.new()
	_axe_status.text = "RUNE  ·  IN HAND"
	_axe_status.add_theme_font_override("font", DISPLAY_FONT)
	_axe_status.add_theme_font_size_override("font_size", 18)
	_axe_status.add_theme_color_override("font_color", RUNE)
	axe_box.add_child(_axe_status)

	# Encounter banner.
	var wave_box := VBoxContainer.new()
	wave_box.anchor_left = 0.5
	wave_box.anchor_right = 0.5
	wave_box.offset_left = -270
	wave_box.offset_right = 270
	wave_box.offset_top = 22
	wave_box.offset_bottom = 92
	wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_combat_root.add_child(wave_box)
	_wave_title = Label.new()
	_wave_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_title.add_theme_font_override("font", DISPLAY_FONT)
	_wave_title.add_theme_font_size_override("font_size", 24)
	_wave_title.add_theme_color_override("font_color", BONE)
	wave_box.add_child(_wave_title)
	_wave_subtitle = _caption("")
	_wave_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_box.add_child(_wave_subtitle)

	_kill_label = _small_heading("SLAIN  0")
	_kill_label.anchor_left = 1.0
	_kill_label.anchor_right = 1.0
	_kill_label.offset_left = -190
	_kill_label.offset_right = -28
	_kill_label.offset_top = 30
	_kill_label.offset_bottom = 60
	_kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_root.add_child(_kill_label)

	_pause_button = _button("PAUSE", 12)
	_pause_button.anchor_left = 1.0
	_pause_button.anchor_right = 1.0
	_pause_button.offset_left = -62
	_pause_button.offset_right = -20
	_pause_button.offset_top = 76
	_pause_button.offset_bottom = 118
	_pause_button.tooltip_text = "Pause (P)"
	_pause_button.pressed.connect(func(): pause_requested.emit())
	_combat_root.add_child(_pause_button)

	_message_panel = _panel(Vector2(580, 74), Color(0.018, 0.025, 0.045, 0.86))
	_message_panel.anchor_left = 0.5
	_message_panel.anchor_right = 0.5
	_message_panel.anchor_top = 0.20
	_message_panel.anchor_bottom = 0.20
	_message_panel.offset_left = -290
	_message_panel.offset_right = 290
	_message_panel.offset_top = -37
	_message_panel.offset_bottom = 37
	_message_panel.visible = false
	_combat_root.add_child(_message_panel)
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_font_override("font", DISPLAY_FONT)
	_message_label.add_theme_font_size_override("font_size", 21)
	_message_label.add_theme_color_override("font_color", BONE)
	_message_panel.add_child(_message_label)

	_combo_label = Label.new()
	_combo_label.anchor_left = 0.5
	_combo_label.anchor_right = 0.5
	_combo_label.anchor_top = 0.62
	_combo_label.anchor_bottom = 0.62
	_combo_label.offset_left = 120
	_combo_label.offset_right = 320
	_combo_label.offset_top = -25
	_combo_label.offset_bottom = 25
	_combo_label.add_theme_font_override("font", DISPLAY_FONT)
	_combo_label.add_theme_font_size_override("font_size", 25)
	_combo_label.add_theme_color_override("font_color", GOLD)
	_combo_label.visible = false
	_combat_root.add_child(_combo_label)

	_boss_panel = _panel(Vector2(650, 82), Color(0.025, 0.015, 0.018, 0.92), Color(0.75, 0.12, 0.06, 0.82))
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	_boss_panel.offset_left = -325
	_boss_panel.offset_right = 325
	_boss_panel.offset_top = 94
	_boss_panel.offset_bottom = 176
	_boss_panel.visible = false
	_combat_root.add_child(_boss_panel)
	var boss_box := VBoxContainer.new()
	boss_box.add_theme_constant_override("separation", 3)
	_boss_panel.add_child(boss_box)
	_boss_name = _small_heading("HROTHGAR · THE BONE JARL")
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color(0.78, 0.06, 0.025), 14)
	boss_box.add_child(_boss_bar)
	_boss_phase_label = _caption("PHASE I · THE OATH")
	_boss_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(_boss_phase_label)

	_overlay = _Overlay.new()
	_overlay.owner_ref = self
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_combat_root.add_child(_overlay)


func _build_title() -> void:
	_title_overlay = _full_overlay(Color(0.006, 0.010, 0.022, 0.84))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_overlay.add_child(center)
	var panel := _panel(Vector2(720, 520), Color(0.018, 0.027, 0.050, 0.97), Color(0.34, 0.66, 0.94, 0.72))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var rune := Label.new()
	rune.text = "ᛟ ᛏ ᛃ"
	rune.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rune.add_theme_font_override("font", RUNE_FONT)
	rune.add_theme_font_size_override("font_size", 34)
	rune.add_theme_color_override("font_color", RUNE)
	box.add_child(rune)
	var title := Label.new()
	title.text = "MIDGARD FURY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", DISPLAY_FONT)
	title.add_theme_font_size_override("font_size", 62)
	title.add_theme_color_override("font_color", BONE)
	box.add_child(title)
	var subtitle := _caption("THE OATHBOUND AXE  ·  A COMPLETE SIX-ENCOUNTER SAGA")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	box.add_child(subtitle)
	var divider := TextureRect.new()
	divider.texture = DIVIDER
	divider.custom_minimum_size = Vector2(560, 18)
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(divider)
	var story := Label.new()
	story.text = "The Bone Jarl has broken death's covenant.\nEnter the frozen keep. Reclaim every oath with Leviathan."
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(600, 66)
	story.add_theme_font_size_override("font_size", 20)
	story.add_theme_color_override("font_color", MUTED)
	box.add_child(story)
	var start := _button("BEGIN THE HUNT", 22)
	start.custom_minimum_size = Vector2(330, 58)
	start.pressed.connect(func(): start_requested.emit())
	var start_center := CenterContainer.new()
	start_center.add_child(start)
	box.add_child(start_center)
	var options := _button("OPTIONS & ACCESSIBILITY", 16)
	options.custom_minimum_size = Vector2(330, 44)
	options.pressed.connect(func(): show_settings(true))
	var options_center := CenterContainer.new()
	options_center.add_child(options)
	box.add_child(options_center)
	start.grab_focus.call_deferred()
	var controls := _caption("WASD MOVE   ·   LMB COMBO   ·   F HEAVY   ·   RMB AIM + LMB THROW   ·   R RECALL   ·   SPACE DODGE   ·   P PAUSE")
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size = Vector2(620, 50)
	box.add_child(controls)
	var credits := _caption("CC0 PRODUCTION ART · KAYKIT / KENNEY · MUSIC & SFX CREDITS IN REPOSITORY")
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_color_override("font_color", Color(MUTED, 0.65))
	box.add_child(credits)
	_root.add_child(_title_overlay)


func _build_boon_overlay() -> void:
	_boon_overlay = _full_overlay(Color(0.006, 0.010, 0.022, 0.86))
	_boon_overlay.visible = false
	var column := VBoxContainer.new()
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = -540
	column.offset_right = 540
	column.offset_top = -245
	column.offset_bottom = 245
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 20)
	_boon_overlay.add_child(column)
	var heading := _heading("CHOOSE AN OATH")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var sub := _caption("ONE POWER FOLLOWS YOU INTO THE NEXT ENCOUNTER")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	_boon_cards = HBoxContainer.new()
	_boon_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	_boon_cards.add_theme_constant_override("separation", 22)
	column.add_child(_boon_cards)
	_root.add_child(_boon_overlay)


func _build_pause_overlay() -> void:
	_pause_overlay = _full_overlay(Color(0.006, 0.010, 0.022, 0.80))
	_pause_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var panel := _panel(Vector2(440, 340))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var title := _heading("THE WORLD HOLDS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := _button("RESUME", 20)
	resume.custom_minimum_size = Vector2(300, 52)
	resume.pressed.connect(func(): resume_requested.emit())
	box.add_child(resume)
	var options := _button("OPTIONS & ACCESSIBILITY", 16)
	options.custom_minimum_size = Vector2(300, 46)
	options.pressed.connect(func(): show_settings(false))
	box.add_child(options)
	var restart := _button("RESTART RUN", 18)
	restart.custom_minimum_size = Vector2(300, 48)
	restart.pressed.connect(func(): restart_requested.emit())
	box.add_child(restart)
	box.add_child(_caption("P · TOGGLE PAUSE   |   C · SWAP SHOULDER"))
	_root.add_child(_pause_overlay)


func _build_settings_overlay() -> void:
	_settings_overlay = _full_overlay(Color(0.006, 0.010, 0.022, 0.88))
	_settings_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_overlay.add_child(center)
	var panel := _panel(Vector2(610, 590))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 11)
	panel.add_child(box)
	var title := _heading("OPTIONS & ACCESSIBILITY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _caption("CHANGES SAVE AUTOMATICALLY")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_add_slider(box, "MASTER VOLUME", Settings.master_volume,
			func(value: float): Settings.set_master(value))
	_add_slider(box, "MUSIC", Settings.music_volume,
			func(value: float): Settings.set_music(value))
	_add_slider(box, "SFX & VOICE", Settings.sfx_volume,
			func(value: float): Settings.set_sfx(value))
	_add_slider(box, "CAMERA SHAKE", Settings.shake_scale,
			func(value: float): Settings.set_shake(value))
	_add_slider(box, "DAMAGE FLASH", Settings.flash_scale,
			func(value: float): Settings.set_flash(value))
	var stop := CheckButton.new()
	stop.text = "IMPACT HIT-STOP"
	stop.button_pressed = Settings.hit_stop_enabled
	stop.add_theme_font_override("font", BODY_FONT)
	stop.add_theme_font_size_override("font_size", 18)
	stop.add_theme_color_override("font_color", BONE)
	stop.toggled.connect(func(enabled: bool): Settings.set_hit_stop(enabled))
	box.add_child(stop)
	var close := _button("BACK", 18)
	close.custom_minimum_size = Vector2(260, 48)
	close.pressed.connect(_close_settings)
	box.add_child(close)
	_root.add_child(_settings_overlay)


func _add_slider(container: VBoxContainer, title: String, value: float,
		callback: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := _caption(title)
	label.add_theme_color_override("font_color", BONE)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.custom_minimum_size = Vector2(520, 28)
	slider.value_changed.connect(callback)
	row.add_child(slider)
	container.add_child(row)


func show_settings(from_title: bool) -> void:
	_settings_from_title = from_title
	_title_overlay.visible = false
	_pause_overlay.visible = false
	_settings_overlay.visible = true


func _close_settings() -> void:
	_settings_overlay.visible = false
	if _settings_from_title:
		_title_overlay.visible = true
	else:
		_pause_overlay.visible = true


func _build_results_overlay() -> void:
	_results_overlay = _full_overlay(Color(0.005, 0.008, 0.018, 0.88))
	_results_overlay.visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results_overlay.add_child(center)
	var panel := _panel(Vector2(650, 430))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	_result_title = _heading("THE DEAD LIE STILL")
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_stats = Label.new()
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_stats.custom_minimum_size = Vector2(560, 160)
	_result_stats.add_theme_font_size_override("font_size", 22)
	_result_stats.add_theme_color_override("font_color", MUTED)
	box.add_child(_result_stats)
	var again := _button("RISE AGAIN", 21)
	again.custom_minimum_size = Vector2(320, 56)
	again.pressed.connect(func(): restart_requested.emit())
	box.add_child(again)
	_root.add_child(_results_overlay)


func _full_overlay(color: Color) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = color
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	return root


func _panel(minimum: Vector2, background := INK, border := BORDER) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum
	panel.add_theme_stylebox_override("panel", _style(background, border, 1, 10, 16))
	return panel


func _style(background: Color, border: Color, width: int, radius: int,
		margin: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = margin
	style.content_margin_top = margin
	style.content_margin_right = margin
	style.content_margin_bottom = margin
	return style


func _button(text: String, size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", DISPLAY_FONT)
	button.add_theme_font_size_override("font_size", size)
	button.add_theme_color_override("font_color", BONE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(IRON, BORDER, 1, 7, 10))
	button.add_theme_stylebox_override("hover", _style(Color(0.12, 0.31, 0.48, 0.98), RUNE, 2, 7, 10))
	button.add_theme_stylebox_override("pressed", _style(Color(0.08, 0.20, 0.34, 0.98), Color.WHITE, 2, 7, 10))
	button.focus_mode = Control.FOCUS_ALL
	return button


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(100, height)
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color(0.015, 0.020, 0.030, 0.92), Color(0.28, 0.34, 0.42), 1, 2, 1))
	bar.add_theme_stylebox_override("fill", _style(color, color.lightened(0.32), 1, 2, 1))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bar


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", 38)
	label.add_theme_color_override("font_color", BONE)
	return label


func _small_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", DISPLAY_FONT)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", BONE)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", MUTED)
	return label


# ------------------------------------------------------------------- updates

func _on_health(current: float, maximum: float) -> void:
	var next := current / maxf(maximum, 0.001)
	if next < health:
		hurt_flash = 1.0
	health = next


func _on_focus(current: float, maximum: float) -> void:
	focus = current / maxf(maximum, 0.001)


func _on_combo(step: int) -> void:
	_combo_label.text = "COMBO  ×%d" % step
	_combo_label.visible = step > 1
	_combo_timer = 0.75


func _on_perfect_dodge() -> void:
	message("PERFECT DODGE · FOCUS RESTORED", 0.9)


func _on_axe_state(next: int) -> void:
	match next:
		LeviathanAxe.State.EQUIPPED:
			axe_label = "IN HAND"
			axe_ready = true
		LeviathanAxe.State.AIRBORNE_THROW:
			axe_label = "IN FLIGHT"
			axe_ready = false
		LeviathanAxe.State.EMBEDDED_WORLD:
			axe_label = "EMBEDDED · R TO RECALL"
			axe_ready = false
		LeviathanAxe.State.EMBEDDED_ENEMY:
			axe_label = "BURIED IN BONE · R TO RECALL"
			axe_ready = false
		LeviathanAxe.State.RECALLING:
			axe_label = "RETURNING"
			axe_ready = false


func message(text: String, duration := 3.0) -> void:
	_message_label.text = text
	_message_timer = duration
	_message_panel.visible = true
	_message_panel.modulate.a = 1.0


func set_session_state(_state: int) -> void:
	pass


func show_title() -> void:
	_title_overlay.visible = true
	_combat_root.visible = false


func hide_title() -> void:
	_title_overlay.visible = false
	_combat_root.visible = true


func show_pause(visible: bool) -> void:
	_pause_overlay.visible = visible


func show_boons(options: Array[Dictionary]) -> void:
	for child in _boon_cards.get_children():
		child.queue_free()
	for i in options.size():
		var option := options[i]
		var card := _button("", 18)
		card.custom_minimum_size = Vector2(320, 270)
		var box := VBoxContainer.new()
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 18
		box.offset_top = 16
		box.offset_right = -18
		box.offset_bottom = -16
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 12)
		card.add_child(box)
		var rune := Label.new()
		rune.text = option["rune"]
		rune.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rune.add_theme_font_override("font", RUNE_FONT)
		rune.add_theme_font_size_override("font_size", 58)
		rune.add_theme_color_override("font_color", RUNE)
		box.add_child(rune)
		var title := _small_heading("[%d]  %s" % [i + 1, option["title"]])
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(title)
		var description := _caption(option["description"])
		description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(270, 72)
		box.add_child(description)
		var choice_index := i
		card.pressed.connect(func(): boon_chosen.emit(choice_index))
		_boon_cards.add_child(card)
	_boon_overlay.visible = true
	_combat_root.visible = false


func hide_boons() -> void:
	_boon_overlay.visible = false
	_combat_root.visible = true


func show_boss(title: String, maximum: float) -> void:
	_boss_name.text = title
	_boss_bar.max_value = maximum
	_boss_bar.value = maximum
	_boss_phase_label.text = "PHASE I · THE OATH"
	_boss_panel.visible = true


func set_boss_health(current: float, maximum: float) -> void:
	_boss_bar.max_value = maximum
	_boss_bar.value = current


func boss_phase(phase: int) -> void:
	_boss_phase_label.text = "PHASE %s · THE BLOOD OATH" % ("II" if phase == 2 else str(phase))


func hide_boss() -> void:
	_boss_panel.visible = false


func show_results(won: bool, slain: int, reached: int,
		run_time: float, boons: Array[StringName]) -> void:
	victory = won
	game_over = not won
	_result_title.text = "THE DEAD LIE STILL" if won else "VALHALLA DENIES YOU"
	_result_title.add_theme_color_override("font_color", RUNE if won else BLOOD.lightened(0.18))
	var minutes := int(run_time) / 60
	var seconds := int(run_time) % 60
	var boon_text := "NONE" if boons.is_empty() else ", ".join(boons)
	_result_stats.text = "DRAUGR SLAIN  %d\nENCOUNTER REACHED  %d / 6\nTIME  %02d:%02d\nOATHS CLAIMED  %s" % [
		slain, reached, minutes, seconds, boon_text.to_upper()]
	_results_overlay.visible = true
	_combat_root.visible = false


func _process(delta: float) -> void:
	health_shown = move_toward(health_shown, health, delta * 0.55)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.4)
	aim_blend = _rig.aim_blend if _rig != null else 0.0
	_vitality.value = health * 100.0
	_vitality_lag.value = health_shown * 100.0
	_focus.value = focus * 100.0
	_axe_status.text = "RUNE  ·  " + axe_label
	_axe_status.add_theme_color_override("font_color", RUNE if axe_ready else MUTED)
	_wave_title.text = "PREPARE" if wave <= 0 else "ENCOUNTER  %d / 6" % wave
	_wave_subtitle.text = "THE KEEP WAITS" if wave <= 0 else "%d HOSTILES REMAIN" % enemies_left
	_kill_label.text = "SLAIN  %d" % kills
	_message_timer = maxf(0.0, _message_timer - delta)
	if _message_timer <= 0.0:
		_message_panel.visible = false
	elif _message_timer < 0.35:
		_message_panel.modulate.a = _message_timer / 0.35
	_combo_timer = maxf(0.0, _combo_timer - delta)
	if _combo_timer <= 0.0:
		_combo_label.visible = false
	_overlay.queue_redraw()


class _Overlay extends Control:
	var owner_ref: Hud

	func _draw() -> void:
		if owner_ref == null:
			return
		var viewport := size
		if owner_ref.hurt_flash > 0.001:
			var alpha := owner_ref.hurt_flash * 0.38 * Settings.flash_scale
			var width := 105.0
			draw_rect(Rect2(0, 0, viewport.x, width), Color(BLOOD, alpha))
			draw_rect(Rect2(0, viewport.y - width, viewport.x, width), Color(BLOOD, alpha))
			draw_rect(Rect2(0, 0, width, viewport.y), Color(BLOOD, alpha * 0.75))
			draw_rect(Rect2(viewport.x - width, 0, width, viewport.y), Color(BLOOD, alpha * 0.75))
		if owner_ref.aim_blend > 0.01:
			var center := viewport * 0.5
			var blend := owner_ref.aim_blend
			var color := Color(RUNE, 0.35 + blend * 0.62)
			var gap := 10.0
			for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + direction * gap, center + direction * (gap + 10), color, 2.0, true)
			draw_circle(center, 2.2, Color(0.9, 0.98, 1.0, blend))
			draw_arc(center, 26, 0, TAU, 40, Color(RUNE, 0.20 * blend), 1.5, true)
