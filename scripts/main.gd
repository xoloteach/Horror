# Main: builds the world, wires player/camera/axe/HUD, runs endless draugr
# waves, hit-stop-friendly game-over/restart. `--smoke` cmdline flag runs a
# scripted headless test (throw -> embed -> recall -> melee) instead of waves.
extends Node3D

var rig: CameraRig
var player: Player
var axe: LeviathanAxe
var hud: GameHUD
var spawn_points: Array = []

var wave := 0
var kills := 0
var enemies_alive := 0
var pending_spawns := 0
var spawn_timer := 0.0
var wave_pause := 2.0
var game_over := false
const MAX_CONCURRENT := 8

var _smoke := false
var _smoke_t := 0.0
var _smoke_stage := 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var info: Dictionary = ArenaBuilder.build(self)
	spawn_points = info["spawn_points"]

	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0, 0, 4)
	add_child(player)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.target = player
	rig.global_position = player.global_position + Vector3(0, 1.55, 0)
	Game.register_camera(rig)
	player.camera_rig = rig

	axe = LeviathanAxe.new()
	axe.name = "LeviathanAxe"
	add_child(axe)
	axe.player = player
	axe.hand_socket = player.get_hand_socket()
	axe.attach_to_hand()
	player.axe = axe

	hud = GameHUD.new()
	hud.name = "HUD"
	add_child(hud)
	player.hp_changed.connect(hud.set_hp)
	player.died.connect(_on_player_died)

	_smoke = "--smoke" in OS.get_cmdline_args()
	if _smoke:
		_smoke_setup()
	else:
		hud.set_wave(0)


func _smoke_setup() -> void:
	print("[SMOKE] starting scripted combat test")
	for i in 3:
		var e := Enemy.new()
		e.position = Vector3((i - 1) * 3.0, 0, -8)
		add_child(e)
		e.player_ref = player
		e.died.connect(_on_enemy_died)
		enemies_alive += 1


func _physics_process(delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("recall_axe"):
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		return
	if _smoke:
		_smoke_step(delta)
		return
	# endless waves (cap concurrent enemies to keep draw calls sane)
	if pending_spawns > 0 and enemies_alive < MAX_CONCURRENT:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_enemy()
			spawn_timer = 0.35
	elif pending_spawns <= 0 and enemies_alive <= 0:
		wave_pause -= delta
		if wave_pause <= 0.0:
			_start_wave()


func _process(_delta: float) -> void:
	if hud != null and player != null:
		hud.set_crosshair(player.aiming and not game_over)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# click to recapture (needed on web after Esc)
	if event is InputEventMouseButton and not game_over:
		var mb := event as InputEventMouseButton
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _start_wave() -> void:
	wave += 1
	pending_spawns = mini(2 + wave, 12)
	spawn_timer = 0.2
	wave_pause = 2.5
	hud.set_wave(wave)
	print("[WAVE] starting wave ", wave, " (", pending_spawns, " draugr)")


func _spawn_enemy() -> void:
	var e := Enemy.new()
	var base: Vector3 = spawn_points[randi() % spawn_points.size()]
	e.position = base + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	add_child(e)
	e.player_ref = player
	e.died.connect(_on_enemy_died)
	enemies_alive += 1
	pending_spawns -= 1
	FX.spawn_dust(e.position + Vector3(0, 0.5, 0), Vector3.UP)
	AudioManager.play_3d("roar_enemy", e.position, -5.0, randf_range(0.85, 1.1))


func _on_enemy_died(_enemy: Enemy) -> void:
	kills += 1
	enemies_alive = maxi(0, enemies_alive - 1)
	hud.set_kills(kills)


func _on_player_died() -> void:
	game_over = true
	hud.show_game_over()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[GAME] player died on wave ", wave, " with ", kills, " kills")


# Scripted headless combat test: throw at enemy -> embed -> recall through
# the line of enemies -> melee swings. Verifies the axe state machine.
func _smoke_step(delta: float) -> void:
	_smoke_t += delta
	match _smoke_stage:
		0:
			if _smoke_t > 0.6:
				player.face_direction(Vector3(0, 0, -1))
				rig.yaw = 0.0
				var foes := get_tree().get_nodes_in_group("enemies")
				if foes.size() > 0:
					var e: Node3D = foes[1]
					var from: Vector3 = axe.global_position
					var dir: Vector3 = (e.chest_position() - from).normalized()
					axe.throw_from(from, dir)
					print("[SMOKE] threw axe, state=", axe.state, " (1=AIRBORNE_THROW)")
				_smoke_stage = 1
		1:
			if _smoke_t > 2.4:
				print("[SMOKE] pre-recall: axe state=", axe.state, " (3=EMBEDDED_ENEMY) host=", axe.host_enemy != null)
				for f in get_tree().get_nodes_in_group("enemies"):
					print("[SMOKE]   enemy hp=", f.get("hp"), " alive=", f.get("alive"), " pos=", f.global_position)
				player.recall_axe()
				print("[SMOKE] recalling, state=", axe.state, " (4=RECALLING)")
				_smoke_stage = 2
		2:
			if _smoke_t > 4.0:
				print("[SMOKE] post-recall: axe state=", axe.state, " (0=EQUIPPED) kills=", kills)
				player.light_attack()
				player.heavy_attack()
				_smoke_stage = 3
		3:
			if _smoke_t > 5.5:
				print("[SMOKE] RESULT hp=", player.hp, " kills=", kills, " axe_state=", axe.state,
					" enemies_alive=", enemies_alive, " player_dead=", player.dead,
					" time_scale=", Engine.time_scale)
				_smoke_stage = 4
		4:
			if _smoke_t > 7.0:
				# exercise the real camera-ray throw path (as F / LMB-in-aim does)
				player.throw_axe()
				print("[SMOKE] camera-ray throw, state=", axe.state)
				_smoke_stage = 5
		5:
			if _smoke_t > 9.5:
				print("[SMOKE] pre-recall2: axe state=", axe.state)
				player.recall_axe()
				_smoke_stage = 6
		6:
			if _smoke_t > 11.5:
				print("[SMOKE] FINAL hp=", player.hp, " kills=", kills, " axe_state=", axe.state,
					" (0=EQUIPPED) time_scale=", Engine.time_scale)
				_smoke_stage = 7
