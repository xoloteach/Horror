class_name Player
extends CharacterBody3D
## Nordic warrior: movement, dodge roll, melee combo, axe throw/recall, and a
## fully procedural animation layer driven off the glTF pivot hierarchy.
##
## The body itself never rotates -- only `model` does. That keeps the camera rig
## (a child of the body) free of the character's turning and rolling, so aiming
## stays stable while the warrior spins underneath it.

signal health_changed(current: float, maximum: float)
signal died

enum St { IDLE, ATTACK, DODGE, HURT, DEAD }

const MAX_HEALTH := 100.0

const SPEED := 5.6
const AIM_SPEED := 2.7
const ACCEL := 14.0
const DECEL := 17.0
const GRAVITY := 24.0
const TURN_SPEED := 13.0

const DODGE_SPEED := 10.5
const DODGE_TIME := 0.42
const DODGE_COOLDOWN := 0.22

const ATTACK_TIME_LIGHT := 0.52
const ATTACK_TIME_HEAVY := 0.78
const DAMAGE_LIGHT := 18.0
const DAMAGE_HEAVY := 34.0
const DAMAGE_UNARMED := 9.0
const REACH := 2.45
const ARC_COS := 0.32   # ~70 degrees to either side

const CAP_HEIGHT := 1.76
const CAP_RADIUS := 0.30
const MODEL_Y := 0.04   # glb feet sit 4cm below its origin

var state: St = St.IDLE
var health := MAX_HEALTH

var model: Node3D
var rig: CameraRig
var axe: LeviathanAxe
var hand: Node3D

var _limbs := {}
var _rest := {}
var _facing := 0.0

var _walk_phase := 0.0
var _step_flag := false
var _breathe := 0.0

var _atk_t := 0.0
var _atk_dur := ATTACK_TIME_LIGHT
var _atk_heavy := false
var _atk_side := 1
var _atk_hits: Array = []

var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.FORWARD

var _hurt_t := 0.0
var _world_root: Node3D

const LIMB_NAMES := [
	"Hips", "ChestPivot", "NeckPivot", "HeadPivot",
	"Shoulder_R", "UpperArm_R", "Forearm_R", "Hand_R",
	"Shoulder_L", "UpperArm_L", "Forearm_L", "Hand_L",
	"Thigh_R", "Shin_R", "Thigh_L", "Shin_L",
]


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	_world_root = get_parent() as Node3D

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	shape.shape = cap
	shape.position = Vector3(0, CAP_HEIGHT * 0.5, 0)
	add_child(shape)

	model = load("res://assets/models/player.glb").instantiate()
	model.position = Vector3(0, MODEL_Y, 0)
	add_child(model)
	_bind_limbs()

	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.position = Vector3(0, 1.42, 0)
	add_child(rig)

	hand = _limbs.get("Hand_R")
	var socket := model.find_child("WeaponSocket_R", true, false)
	if socket != null:
		hand = socket

	axe = LeviathanAxe.new()
	axe.name = "Axe"
	hand.add_child(axe)
	axe.setup(self, hand, _world_root)

	health_changed.emit(health, MAX_HEALTH)


func _bind_limbs() -> void:
	for n in LIMB_NAMES:
		var node := model.find_child(n, true, false)
		if node is Node3D:
			_limbs[n] = node
			_rest[n] = (node as Node3D).rotation
		else:
			push_warning("Player: limb not found -> %s" % n)


func _rot(name: String, euler: Vector3, weight := 1.0) -> void:
	var n: Node3D = _limbs.get(name)
	if n == null:
		return
	var rest: Vector3 = _rest[name]
	n.rotation = rest + euler * weight


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if state == St.DEAD:
		return
	# On touch devices there is no pointer to capture, so skip the capture
	# handshake entirely and let the virtual buttons drive the action events.
	if event is InputEventMouseButton and event.pressed and not Boot.touch_active:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
	if event.is_action_pressed("ui_release") and not Boot.touch_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if not Boot.input_unlocked():
		return

	if event.is_action_pressed("attack_light"):
		if rig.aim_blend > 0.55 and axe.can_throw():
			_throw_axe()
		else:
			_start_attack(false)
	elif event.is_action_pressed("attack_heavy"):
		_start_attack(true)
	elif event.is_action_pressed("recall") or event.is_action_pressed("recall_mouse"):
		if axe.can_recall():
			axe.recall()
	elif event.is_action_pressed("dodge"):
		_start_dodge()


func _throw_axe() -> void:
	var exclude: Array[RID] = [get_rid()]
	var target := rig.aim_point(70.0, exclude)
	axe.throw(hand.global_position, target)
	_atk_t = 0.0
	_atk_dur = 0.34
	_atk_heavy = false
	_atk_side = 1
	_atk_hits.clear()
	state = St.ATTACK
	Sfx.play_3d("grunt", global_position + Vector3.UP * 1.4, -3.0)


func _start_attack(heavy: bool) -> void:
	if state in [St.ATTACK, St.DODGE, St.DEAD]:
		return
	_atk_heavy = heavy
	_atk_dur = ATTACK_TIME_HEAVY if heavy else ATTACK_TIME_LIGHT
	_atk_t = 0.0
	_atk_side = -_atk_side
	_atk_hits.clear()
	state = St.ATTACK
	Sfx.play_3d("swing_heavy" if heavy else "swing",
			global_position + Vector3.UP * 1.3, -1.0)
	if heavy:
		Sfx.play_3d("grunt", global_position + Vector3.UP * 1.4, -4.0)


func _start_dodge() -> void:
	if state in [St.DODGE, St.DEAD] or _dodge_cd > 0.0:
		return
	var wish := _wish_dir()
	if wish.length_squared() < 0.01:
		wish = -Vector3(sin(_facing), 0, cos(_facing))
	_dodge_dir = wish.normalized()
	_dodge_t = 0.0
	_dodge_cd = DODGE_TIME + DODGE_COOLDOWN
	state = St.DODGE
	Sfx.play_3d("dodge", global_position + Vector3.UP, -2.0)


func _wish_dir() -> Vector3:
	# merged keyboard + virtual thumbstick
	var iv := Boot.move_axis()
	if iv.length_squared() < 0.0004:
		return Vector3.ZERO
	# forward on screen = away from camera
	return (rig.flat_forward() * -iv.y + rig.flat_right() * iv.x).normalized()


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	var aiming := Input.is_action_pressed("aim") and state != St.DEAD \
			and Boot.input_unlocked()
	rig.set_aiming(aiming)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)

	match state:
		St.DODGE:
			_sim_dodge(delta)
		St.ATTACK:
			_sim_attack(delta, aiming)
		St.HURT:
			_sim_hurt(delta)
		St.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
			velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)
		_:
			_sim_move(delta, aiming)

	move_and_slide()
	_animate(delta, aiming)


func _sim_move(delta: float, aiming: bool) -> void:
	var wish := _wish_dir()
	var top := AIM_SPEED if aiming else SPEED
	var flat := Vector3(velocity.x, 0, velocity.z)
	if wish.length_squared() > 0.01:
		flat = flat.move_toward(wish * top, ACCEL * delta)
	else:
		flat = flat.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	# aiming locks facing to the camera; otherwise face travel
	var want := _facing
	if aiming:
		want = atan2(-rig.flat_forward().x, -rig.flat_forward().z)
	elif flat.length() > 0.35:
		want = atan2(-flat.x, -flat.z)
	_facing = _lerp_angle(_facing, want, TURN_SPEED * delta)


func _sim_dodge(delta: float) -> void:
	_dodge_t += delta
	var u: float = clampf(_dodge_t / DODGE_TIME, 0.0, 1.0)
	# front-loaded burst that bleeds off
	var s: float = DODGE_SPEED * (1.0 - u * u)
	velocity.x = _dodge_dir.x * s
	velocity.z = _dodge_dir.z * s
	_facing = _lerp_angle(_facing,
			atan2(-_dodge_dir.x, -_dodge_dir.z), 18.0 * delta)
	if _dodge_t >= DODGE_TIME:
		state = St.IDLE


func _sim_attack(delta: float, aiming: bool) -> void:
	_atk_t += delta
	var u: float = _atk_t / _atk_dur
	# slight forward lunge as the blow lands
	var push := 0.0
	if u > 0.25 and u < 0.55:
		push = (2.9 if _atk_heavy else 1.9)
	var fwd := -Vector3(sin(_facing), 0, cos(_facing))
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.move_toward(fwd * push, 26.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	if aiming:
		_facing = _lerp_angle(_facing,
				atan2(-rig.flat_forward().x, -rig.flat_forward().z), 16.0 * delta)

	if u >= 0.30 and u <= 0.56:
		_melee_sweep()
	if _atk_t >= _atk_dur:
		state = St.IDLE


func _sim_hurt(delta: float) -> void:
	_hurt_t -= delta
	velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)
	if _hurt_t <= 0.0:
		state = St.IDLE


func _melee_sweep() -> void:
	var dmg := DAMAGE_UNARMED
	if axe != null and axe.is_held():
		dmg = DAMAGE_HEAVY if _atk_heavy else DAMAGE_LIGHT
	var fwd := -Vector3(sin(_facing), 0, cos(_facing))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e in _atk_hits or not is_instance_valid(e):
			continue
		if not e.has_method("take_hit"):
			continue
		var to: Vector3 = e.global_position - global_position
		to.y = 0.0
		if to.length() > REACH:
			continue
		if to.length_squared() > 0.001 and fwd.dot(to.normalized()) < ARC_COS:
			continue
		_atk_hits.append(e)
		var n := to.normalized() if to.length_squared() > 0.001 else fwd
		e.take_hit(dmg, n, _atk_heavy)
		var at: Vector3 = e.global_position + Vector3.UP * 1.0
		Fx.blood(_world_root, at, -n, 1.0 if _atk_heavy else 0.75)
		Sfx.play_3d("flesh", at, 0.0)
		if _atk_heavy:
			Juice.impact(0.42, n, 0.05, 0.08)
		else:
			Juice.impact(0.22, n, 0.16, 0.045)


# ------------------------------------------------------------------- damage

func take_hit(amount: float, from_dir: Vector3) -> void:
	if state == St.DEAD or state == St.DODGE:
		return  # dodge roll grants full evasion
	health = maxf(0.0, health - amount)
	health_changed.emit(health, MAX_HEALTH)
	Juice.impact(0.5, from_dir, 0.10, 0.06)
	Sfx.play_2d("hurt_player", 0.0)
	velocity += from_dir.normalized() * 3.4
	if health <= 0.0:
		state = St.DEAD
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
	else:
		state = St.HURT
		_hurt_t = 0.22


# ---------------------------------------------------------------- animation

func _animate(delta: float, aiming: bool) -> void:
	if model == null:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var spd := flat.length()
	_breathe += delta * 1.7

	var model_roll := 0.0
	var model_pitch := 0.0

	if state == St.DODGE:
		var u: float = clampf(_dodge_t / DODGE_TIME, 0.0, 1.0)
		model_pitch = -TAU * u   # forward shoulder roll
	model.rotation = Vector3(model_pitch, _facing, model_roll)

	# ---- locomotion
	var gait: float = clampf(spd / SPEED, 0.0, 1.4)
	if state == St.DODGE:
		gait = 0.0
	_walk_phase += delta * (2.1 + gait * 7.4)
	var sw: float = sin(_walk_phase)
	var sw2: float = sin(_walk_phase + PI)

	var leg_amp: float = 0.62 * gait
	var arm_amp: float = 0.52 * gait

	_rot("Thigh_R", Vector3(sw * leg_amp, 0, 0))
	_rot("Thigh_L", Vector3(sw2 * leg_amp, 0, 0))
	# knees only bend one way
	_rot("Shin_R", Vector3(-maxf(0.0, -sw) * 1.05 * gait, 0, 0))
	_rot("Shin_L", Vector3(-maxf(0.0, -sw2) * 1.05 * gait, 0, 0))

	var hip_bob: float = sin(_walk_phase * 2.0) * 0.035 * gait
	var hips: Node3D = _limbs.get("Hips")
	if hips != null:
		hips.position.y = 0.94 + hip_bob
	_rot("Hips", Vector3(0.05 * gait, sw * 0.10 * gait, 0))
	_rot("ChestPivot", Vector3(0.04 + 0.05 * gait,
			-sw * 0.13 * gait + sin(_breathe) * 0.012, 0))

	# footstep on each downswing crossing
	var down := sw < 0.0
	if gait > 0.25 and down != _step_flag:
		_step_flag = down
		if is_on_floor():
			Sfx.play_3d("step", global_position, -4.0)
	elif gait <= 0.25:
		_step_flag = down

	# ---- arms: base swing, then attack/aim layers override the right arm
	_rot("UpperArm_L", Vector3(sw * arm_amp, 0, 0.12))
	_rot("Forearm_L", Vector3(-0.22 - maxf(0.0, sw) * 0.35 * gait, 0, 0))

	# carry the axe out from the torso so its silhouette reads against the
	# background instead of disappearing into the chest
	var r_arm := Vector3(0.12 + sw2 * arm_amp * 0.50, 0, -0.30)
	var r_fore := Vector3(-0.72, 0, 0)

	if aiming and state != St.ATTACK:
		# wind the axe back behind the head, ready to throw
		r_arm = Vector3(-2.05, -0.30, -0.55)
		r_fore = Vector3(-1.25, 0, 0)
		_rot("ChestPivot", Vector3(0.04, -0.34, 0))

	if state == St.ATTACK:
		var u: float = clampf(_atk_t / _atk_dur, 0.0, 1.0)
		var a := _attack_pose(u)
		r_arm = a[0]
		r_fore = a[1]
		_rot("ChestPivot", a[2])
		_rot("NeckPivot", Vector3(a[3].x * 0.5, a[3].y * 0.5, 0))

	_rot("UpperArm_R", r_arm)
	_rot("Forearm_R", r_fore)

	if state != St.ATTACK:
		_rot("NeckPivot", Vector3(-0.05, 0, 0))
	# head tracks the camera pitch a little while aiming
	_rot("HeadPivot", Vector3(rig.pitch * 0.35 * rig.aim_blend, 0, 0))


## Three-phase swing: wind up, strike, recover. Returns
## [upper_arm, forearm, chest, neck] euler offsets.
func _attack_pose(u: float) -> Array:
	var side := float(_atk_side)
	var wind := 0.30
	var strike := 0.56
	if u < wind:
		var k: float = u / wind
		k = k * k * (3.0 - 2.0 * k)
		return [
			Vector3(lerpf(-0.10, -2.35, k), lerpf(0.0, -0.45, k) * side,
					lerpf(-0.10, -0.62, k)),
			Vector3(lerpf(-0.95, -1.55, k), 0, 0),
			Vector3(0.04, lerpf(0.0, -0.46, k) * side, 0),
			Vector3(lerpf(0.0, -0.18, k), lerpf(0.0, -0.30, k) * side, 0),
		]
	elif u < strike:
		# fast, near-linear drive through the contact window
		var k: float = (u - wind) / (strike - wind)
		k = k * k
		return [
			Vector3(lerpf(-2.35, 0.95, k), lerpf(-0.45, 0.38, k) * side,
					lerpf(-0.62, 0.20, k)),
			Vector3(lerpf(-1.55, -0.18, k), 0, 0),
			Vector3(lerpf(0.04, 0.22, k), lerpf(-0.46, 0.40, k) * side, 0),
			Vector3(lerpf(-0.18, 0.22, k), lerpf(-0.30, 0.26, k) * side, 0),
		]
	else:
		var k: float = (u - strike) / (1.0 - strike)
		k = k * k * (3.0 - 2.0 * k)
		return [
			Vector3(lerpf(0.95, -0.10, k), lerpf(0.38, 0.0, k) * side,
					lerpf(0.20, -0.10, k)),
			Vector3(lerpf(-0.18, -0.95, k), 0, 0),
			Vector3(lerpf(0.22, 0.04, k), lerpf(0.40, 0.0, k) * side, 0),
			Vector3(lerpf(0.22, 0.0, k), lerpf(0.26, 0.0, k) * side, 0),
		]


static func _lerp_angle(from: float, to: float, w: float) -> float:
	return from + wrapf(to - from, -PI, PI) * clampf(w, 0.0, 1.0)


func revive() -> void:
	health = MAX_HEALTH
	state = St.IDLE
	velocity = Vector3.ZERO
	health_changed.emit(health, MAX_HEALTH)
