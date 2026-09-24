# Player: Nordic warrior CharacterBody3D. WASD camera-relative movement,
# sprint, dodge-roll with i-frames, light/heavy melee, axe throw/recall.
class_name Player
extends CharacterBody3D

signal hp_changed(hp: float, max_hp: float)
signal died

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.2
const AIM_SPEED := 2.9
const ACCEL := 12.0
const GRAVITY := 22.0
const DODGE_SPEED := 11.0
const DODGE_TIME := 0.38
const DODGE_COOLDOWN := 0.75

var max_hp := 100.0
var hp := 100.0
var dead := false
var aiming := false
var iframes := false

var camera_rig: Node = null   # CameraRig, set by main
var axe: Node = null          # LeviathanAxe, set by main

var visual: Node3D
var rig: CharRig
var hand_socket: Node3D

var _dodge_timer := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _attack_cd := 0.0
var _attack_anim := 0.0
var _attack_dur := 0.32
var _walk_phase := 0.0
var _step_timer := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	col.shape = cap
	col.position = Vector3(0, 0.95, 0)
	add_child(col)
	visual = MeshFactory.create_player()
	add_child(visual)
	rig = CharRig.from_node(visual)
	hand_socket = rig.hand_socket()
	rig.set_arm("R", -0.25)


func get_hand_socket() -> Node3D:
	return hand_socket


func facing_dir() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)


func face_direction(dir: Vector3) -> void:
	var d := dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	rotation.y = atan2(-d.x, -d.z)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	aiming = Input.is_action_pressed("aim")
	if camera_rig != null:
		camera_rig.aiming = aiming

	# --- attacks ---
	if Input.is_action_just_pressed("attack"):
		if aiming:
			throw_axe()
		else:
			light_attack()
	if Input.is_action_just_pressed("heavy_attack"):
		heavy_attack()
	if Input.is_action_just_pressed("throw_axe"):
		throw_axe()
	if Input.is_action_just_pressed("recall_axe"):
		recall_axe()

	# --- dodge ---
	if Input.is_action_just_pressed("dodge") and _dodge_cd <= 0.0 and _dodge_timer <= 0.0:
		_dodge_timer = DODGE_TIME
		_dodge_cd = DODGE_COOLDOWN
		var d := _input_dir()
		_dodge_dir = d if d.length() > 0.1 else facing_dir()
		iframes = true
		face_direction(_dodge_dir)
		AudioManager.play_2d("swing_light", -10.0, 1.4)

	# --- movement ---
	var target_v := Vector3.ZERO
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		target_v = _dodge_dir * DODGE_SPEED
		if _dodge_timer <= 0.0:
			iframes = false
	else:
		var md := _input_dir()
		var spd := AIM_SPEED if aiming else (SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED)
		target_v = md * spd
		if md.length() > 0.1 and not aiming:
			face_direction(md)
	if aiming and camera_rig != null:
		rotation.y = lerp_angle(rotation.y, camera_rig.yaw, 1.0 - exp(-12.0 * delta))

	var k := 1.0 - exp(-ACCEL * delta)
	velocity.x = lerpf(velocity.x, target_v.x, k)
	velocity.z = lerpf(velocity.z, target_v.z, k)
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# footsteps
	var hs := Vector2(velocity.x, velocity.z).length()
	if hs > 2.0 and is_on_floor():
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 2.6 / hs
			AudioManager.play_2d("footstep_heavy", -12.0, randf_range(0.9, 1.1))


func _input_dir() -> Vector3:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if camera_rig == null:
		return Vector3(iv.x, 0, iv.y)
	var f: Vector3 = camera_rig.forward_flat()
	var r := f.cross(Vector3.UP).normalized()
	return r * iv.x + f * -iv.y


func _process(delta: float) -> void:
	if dead:
		return
	# walk cycle
	var hs := Vector2(velocity.x, velocity.z).length()
	_walk_phase += hs * delta * 1.9
	var sw := sin(_walk_phase) * clampf(hs / WALK_SPEED, 0.0, 1.0)
	rig.set_leg("L", sw * 0.6)
	rig.set_leg("R", -sw * 0.6)
	if _attack_anim <= 0.0:
		rig.set_arm("L", -sw * 0.35)
		rig.set_arm("R", lerpf(rig.get_arm("R"), -0.25 + sw * 0.15, delta * 10.0))
		rig.set_torso(lerpf(rig.get_torso(), 0.0, delta * 8.0))
	else:
		# overhead chop: raise then slam
		_attack_anim -= delta
		var t := clampf(1.0 - _attack_anim / _attack_dur, 0.0, 1.0)
		var swing := sin(t * PI)
		rig.set_arm("R", lerpf(-0.25, -2.4, swing))
		rig.set_torso(0.35 * swing)
	if _dodge_timer > 0.0:
		var p := 1.0 - _dodge_timer / DODGE_TIME
		visual.rotation.x = TAU * p
	else:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, delta * 12.0)


func light_attack() -> void:
	if _attack_cd > 0.0 or _dodge_timer > 0.0 or dead:
		return
	_attack_cd = 0.42
	_attack_anim = 0.32
	_attack_dur = 0.32
	_melee_hit(15.0, 2.7)
	AudioManager.play_2d("swing_light", 0.0, randf_range(0.95, 1.05))
	velocity += facing_dir() * 2.2


func heavy_attack() -> void:
	if _attack_cd > 0.0 or _dodge_timer > 0.0 or dead:
		return
	_attack_cd = 0.95
	_attack_anim = 0.55
	_attack_dur = 0.55
	_melee_hit(32.0, 3.0)
	AudioManager.play_2d("swing_heavy")
	AudioManager.play_2d("grunt_player", -4.0, randf_range(0.9, 1.05))
	Game.hit_stop(0.09, 0.05)
	Game.add_trauma(0.35)
	velocity += facing_dir() * 3.2


func _melee_hit(damage: float, reach: float) -> void:
	var fwd := facing_dir()
	var hits := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.get("alive"):
			continue
		var to: Vector3 = e.chest_position() - global_position
		to.y = 0.0
		if to.length() > reach:
			continue
		if fwd.dot(to.normalized()) < 0.3:
			continue
		e.take_damage(damage, e.chest_position(), damage >= 30.0)
		FX.spawn_blood(e.chest_position())
		hits += 1
	if hits > 0:
		AudioManager.play_3d("flesh_slice", global_position + fwd * 1.5)
		AudioManager.play_3d("blood_impact", global_position + fwd * 1.5, -3.0)


func throw_axe() -> void:
	if axe == null or dead or camera_rig == null:
		return
	if axe.get("state") != 0:  # LeviathanAxe.State.EQUIPPED == 0
		return
	var origin: Vector3 = camera_rig.aim_origin()
	var dir: Vector3 = camera_rig.aim_dir()
	var to := origin + dir * 70.0
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else to
	var hand_pos: Vector3 = axe.global_position
	var throw_dir: Vector3 = (target - hand_pos).normalized()
	axe.throw_from(hand_pos, throw_dir)
	AudioManager.play_2d("grunt_player", -8.0, 1.1)


func recall_axe() -> void:
	if axe == null or dead:
		return
	axe.start_recall()


func take_damage(amount: float) -> void:
	if iframes or dead:
		return
	hp = maxf(0.0, hp - amount)
	hp_changed.emit(hp, max_hp)
	Game.add_trauma(0.5)
	AudioManager.play_2d("blood_impact", -4.0, 0.9)
	if hp <= 0.0:
		_die()


func _die() -> void:
	dead = true
	iframes = false
	died.emit()
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", -1.45, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
