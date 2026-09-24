class_name Hud
extends CanvasLayer
## Diegetic-ish overlay: health, axe state, wave progress, aim crosshair,
## damage vignette and the end-of-run screens. Everything is drawn in code so the
## build carries no UI texture or theme dependencies.

const RED := Color(0.78, 0.13, 0.11)
const RUNE := Color(0.58, 0.86, 1.0)
const BONE := Color(0.90, 0.88, 0.82)

var health := 1.0
var health_shown := 1.0
var axe_label := "EQUIPPED"
var axe_ready := true
var wave := 0
var enemies_left := 0
var kills := 0

var aim_blend := 0.0
var hurt_flash := 0.0
var game_over := false
var victory := false

var _msg := ""
var _msg_t := 0.0
var _painter: Control
var _rig: CameraRig


func _ready() -> void:
	layer = 1
	_painter = _Draw.new()
	_painter.owner_ref = self
	_painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_painter)


func bind(player: Player) -> void:
	_rig = player.rig
	player.health_changed.connect(_on_health)
	player.axe.state_changed.connect(_on_axe_state)


func _on_health(cur: float, maximum: float) -> void:
	var next: float = cur / maxf(maximum, 0.001)
	if next < health:
		hurt_flash = 1.0
	health = next


func _on_axe_state(s: int) -> void:
	match s:
		LeviathanAxe.State.EQUIPPED:
			axe_label = "IN HAND"
			axe_ready = true
		LeviathanAxe.State.AIRBORNE_THROW:
			axe_label = "IN FLIGHT"
			axe_ready = false
		LeviathanAxe.State.EMBEDDED_WORLD:
			axe_label = "EMBEDDED"
			axe_ready = false
		LeviathanAxe.State.EMBEDDED_ENEMY:
			axe_label = "IN THE BEAST"
			axe_ready = false
		LeviathanAxe.State.RECALLING:
			axe_label = "RETURNING"
			axe_ready = false


func message(text: String, duration := 3.0) -> void:
	_msg = text
	_msg_t = duration


func _process(delta: float) -> void:
	health_shown = move_toward(health_shown, health, delta * 0.55)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.1)
	_msg_t = maxf(0.0, _msg_t - delta)
	aim_blend = _rig.aim_blend if _rig != null else 0.0
	_painter.queue_redraw()


class _Draw extends Control:
	var owner_ref

	func _draw() -> void:
		var o = owner_ref
		if o == null:
			return
		var font := ThemeDB.fallback_font
		var vp := size

		# ---------------------------------------------------- damage vignette
		if o.hurt_flash > 0.001:
			var a: float = o.hurt_flash * 0.42
			var band := 90.0
			draw_rect(Rect2(0, 0, vp.x, band),
					Color(RED.r, RED.g, RED.b, a * 0.8))
			draw_rect(Rect2(0, vp.y - band, vp.x, band),
					Color(RED.r, RED.g, RED.b, a * 0.8))
			draw_rect(Rect2(0, 0, band * 0.7, vp.y),
					Color(RED.r, RED.g, RED.b, a * 0.55))
			draw_rect(Rect2(vp.x - band * 0.7, 0, band * 0.7, vp.y),
					Color(RED.r, RED.g, RED.b, a * 0.55))

		# ------------------------------------------------------- health bar
		var bw := 340.0
		var bh := 16.0
		var bx := 36.0
		var by := vp.y - 52.0
		draw_rect(Rect2(bx - 2, by - 2, bw + 4, bh + 4), Color(0, 0, 0, 0.55))
		# lagging "recent damage" bar in dark red behind the live one
		draw_rect(Rect2(bx, by, bw * o.health_shown, bh),
				Color(0.42, 0.06, 0.05, 0.95))
		draw_rect(Rect2(bx, by, bw * o.health, bh), RED)
		draw_rect(Rect2(bx, by, bw * o.health, 3.0),
				Color(1.0, 0.45, 0.35, 0.65))
		draw_string(font, Vector2(bx, by - 9.0), "VITALITY",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(BONE, 0.75))

		# -------------------------------------------------------- axe status
		var ax := bx
		var ay := by + bh + 26.0
		var col: Color = RUNE if o.axe_ready else Color(0.62, 0.58, 0.52)
		draw_circle(Vector2(ax + 7, ay - 5), 6.0, Color(col, 0.9))
		draw_string(font, Vector2(ax + 22, ay), "LEVIATHAN  ·  " + o.axe_label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col, 0.95))
		if not o.axe_ready:
			draw_string(font, Vector2(ax + 22, ay + 20.0),
					"press R to recall", HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
					Color(BONE, 0.5))

		# ------------------------------------------------------ wave / kills
		var top := ("PREPARE" if o.wave <= 0 else "WAVE %d" % o.wave)
		var tw := font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 26).x
		draw_string(font, Vector2(vp.x * 0.5 - tw * 0.5, 52.0), top,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(BONE, 0.88))
		var sub := ("the dead are stirring" if o.wave <= 0
				else "%d draugr remain" % o.enemies_left)
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT,
				-1, 15).x
		draw_string(font, Vector2(vp.x * 0.5 - sw * 0.5, 76.0), sub,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(BONE, 0.58))
		draw_string(font, Vector2(vp.x - 150.0, 52.0), "SLAIN  %d" % o.kills,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(BONE, 0.62))

		# --------------------------------------------------------- crosshair
		if o.aim_blend > 0.01:
			var c := vp * 0.5
			var a2: float = o.aim_blend
			var gap := 9.0
			var len := 13.0 - 4.0 * a2
			var cc := Color(RUNE, 0.30 + 0.60 * a2)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + d * gap, c + d * (gap + len), cc, 1.8, true)
			draw_circle(c, 1.9, Color(1, 1, 1, 0.55 * a2))
			draw_arc(c, gap + len + 7.0, 0, TAU, 32, Color(RUNE, 0.16 * a2),
					1.2, true)

		# ----------------------------------------------------------- message
		if o._msg_t > 0.0 and o._msg != "":
			var fade: float = clampf(o._msg_t, 0.0, 1.0)
			var mw := font.get_string_size(o._msg, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 20).x
			draw_string(font, Vector2(vp.x * 0.5 - mw * 0.5, vp.y * 0.30),
					o._msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
					Color(BONE, 0.30 + 0.60 * fade))

		# -------------------------------------------------------- end screens
		if o.game_over or o.victory:
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))
			var title := "THE ALL-FATHER CLAIMS YOU"
			var tint := RED
			if o.victory:
				title = "THE DEAD LIE STILL"
				tint = RUNE
			var big := 42
			var w2 := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT,
					-1, big).x
			draw_string(font, Vector2(vp.x * 0.5 - w2 * 0.5, vp.y * 0.42),
					title, HORIZONTAL_ALIGNMENT_LEFT, -1, big,
					Color(tint, 0.95))
			var line := "%d draugr slain  ·  reached wave %d" % [o.kills, o.wave]
			var w3 := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 18).x
			draw_string(font, Vector2(vp.x * 0.5 - w3 * 0.5, vp.y * 0.42 + 38.0),
					line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(BONE, 0.75))
			var hint := "press ENTER to rise again"
			var w4 := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT,
					-1, 17).x
			draw_string(font, Vector2(vp.x * 0.5 - w4 * 0.5, vp.y * 0.42 + 78.0),
					hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(BONE, 0.6))
