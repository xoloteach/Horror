class_name Draugr
extends CharacterBody3D
## Undead Nordic warrior.
##
## Behaviour: shamble toward the player, telegraph a wind-up the player can read
## and dodge, lunge, then recover. Enough damage inside a short window breaks the
## attack and staggers it, which is what makes the axe feel like it has authority.
##
## Steering is plain vector pursuit plus separation rather than a baked
## NavigationMesh: the arena floor is flat and convex, and this keeps the build
## free of a nav-bake step.

signal died(d: Draugr)

enum St { IDLE, PURSUE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }

const MAX_HEALTH := 100.0
const SPEED := 3.35
const ACCEL := 9.0
const GRAVITY := 24.0
const TURN_SPEED := 7.5

const SIGHT := 30.0
const ATTACK_RANGE := 2.30
const LUNGE_SPEED := 8.6

const WINDUP_TIME := 0.55
const STRIKE_TIME := 0.20
const RECOVER_TIME := 0.46
const STAGGER_TIME := 0.52

const DAMAGE := 14.0
const STAGGER_THRESHOLD := 30.0
const STAGGER_DECAY := 22.0   # per second

const SEPARATION_RADIUS := 1.45
const SEPARATION_FORCE := 4.2

const CAP_HEIGHT := 1.63
const CAP_RADIUS := 0.28
const MODEL_Y := 0.04

var state: St = St.IDLE
var health := MAX_HEALTH

var model: Node3D
var chest: Node3D
var _player: Node3D
var _limbs := {}
var _rest := {}

var _facing := 0.0
var _phase := 0.0
var _timer := 0.0
var _cooldown := 0.0
var _stagger_accum := 0.0
var _struck := false
var _step_flag := false
var _world_root: Node3D

const LIMB_NAMES := [
	"Hips", "ChestPivot", "NeckPivot", "HeadPivot",
	"Shoulder_R", "UpperArm_R", "Forearm_R", "Hand_R",
	"Shoulder_L", "UpperArm_L", "Forearm_L", "Hand_L",
	"Thigh_R", "Shin_R", "Thigh_L", "Shin_L",
]


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2
	_world_root = get_parent() as Node3D

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	shape.shape = cap
	shape.position = Vector3(0, CAP_HEIGHT * 0.5, 0)
	add_child(shape)

	model = load("res://assets/models/draugr.glb").instantiate()
	model.position = Vector3(0, MODEL_Y, 0)
	add_child(model)
	for n in LIMB_NAMES:
		var node := model.find_child(n, true, false)
		if node is Node3D:
			_limbs[n] = node
			_rest[n] = (node as Node3D).rotation
	chest = _limbs.get("ChestPivot", model)

	_phase = randf() * TAU
	_cooldown = randf_range(0.2, 1.1)
	_facing = randf_range(-PI, PI)


func set_player(p: Node3D) -> void:
	_player = p


## Where the axe parents itself when it sticks in this body.
func embed_anchor() -> Node3D:
	return chest if chest != null else model


func _rot(name: String, euler: Vector3) -> void:
	var n: Node3D = _limbs.get(name)
	if n == null:
		return
	n.rotation = (_rest[name] as Vector3) + euler


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)

	_cooldown = maxf(0.0, _cooldown - delta)
	_stagger_accum = maxf(0.0, _stagger_accum - STAGGER_DECAY * delta)

	if state == St.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		move_and_slide()
		return

	var to_player := Vector3.ZERO
	var dist := 999.0
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()

	match state:
		St.IDLE:
			_brake(delta)
			if dist < SIGHT:
				state = St.PURSUE
		St.PURSUE:
			_do_pursue(delta, to_player, dist)
		St.WINDUP:
			_do_windup(delta, to_player)
		St.STRIKE:
			_do_strike(delta, dist)
		St.RECOVER:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				state = St.PURSUE
		St.STAGGER:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				state = St.PURSUE
				_cooldown = maxf(_cooldown, 0.35)

	move_and_slide()
	_animate(delta)


func _brake(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 16.0 * delta)


func _do_pursue(delta: float, to_player: Vector3, dist: float) -> void:
	if dist > SIGHT * 1.3:
		state = St.IDLE
		return
	var dir := to_player.normalized() if dist > 0.01 else Vector3.ZERO
	dir += _separation()
	if dir.length_squared() > 0.001:
		dir = dir.normalized()

	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.move_toward(dir * SPEED, ACCEL * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	_face(to_player, delta)

	if dist <= ATTACK_RANGE and _cooldown <= 0.0:
		_begin_windup()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not is_instance_valid(other):
			continue
		var d: Vector3 = global_position - (other as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.001 and l < SEPARATION_RADIUS:
			push += d.normalized() * (1.0 - l / SEPARATION_RADIUS)
	return push * SEPARATION_FORCE * 0.25


func _begin_windup() -> void:
	state = St.WINDUP
	_timer = WINDUP_TIME
	_struck = false
	Sfx.play_3d("roar", global_position + Vector3.UP * 1.3, -2.0)


func _do_windup(delta: float, to_player: Vector3) -> void:
	_brake(delta)
	_face(to_player, delta * 0.8)
	_timer -= delta
	if _timer <= 0.0:
		state = St.STRIKE
		_timer = STRIKE_TIME


func _do_strike(delta: float, dist: float) -> void:
	_timer -= delta
	var fwd := -Vector3(sin(_facing), 0, cos(_facing))
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.move_toward(fwd * LUNGE_SPEED, 34.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	if not _struck and _timer <= STRIKE_TIME * 0.55:
		_struck = true
		if is_instance_valid(_player) and dist <= ATTACK_RANGE + 0.95:
			var to: Vector3 = _player.global_position - global_position
			to.y = 0.0
			if to.length_squared() > 0.001 and fwd.dot(to.normalized()) > 0.25:
				if _player.has_method("take_hit"):
					_player.take_hit(DAMAGE, to.normalized())

	if _timer <= 0.0:
		state = St.RECOVER
		_timer = RECOVER_TIME
		_cooldown = randf_range(0.55, 1.5)


func _face(to_player: Vector3, delta: float) -> void:
	if to_player.length_squared() < 0.001:
		return
	var want := atan2(-to_player.x, -to_player.z)
	_facing = _facing + wrapf(want - _facing, -PI, PI) \
			* clampf(TURN_SPEED * delta, 0.0, 1.0)


# --------------------------------------------------------------------- damage

func take_hit(amount: float, from_dir: Vector3, heavy: bool) -> void:
	if state == St.DEAD:
		return
	health -= amount
	_stagger_accum += amount

	if health <= 0.0:
		_die(from_dir)
		return

	# heavy blows always break the attack; light ones need to accumulate
	if heavy or _stagger_accum >= STAGGER_THRESHOLD or state == St.WINDUP:
		state = St.STAGGER
		_timer = STAGGER_TIME
		_stagger_accum = 0.0
		Sfx.play_3d("stagger", global_position + Vector3.UP * 1.1, -1.0)
	velocity += from_dir.normalized() * (5.2 if heavy else 2.4)


func _die(from_dir: Vector3) -> void:
	state = St.DEAD
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 1
	Sfx.play_3d("death_draugr", global_position + Vector3.UP, 0.0)
	died.emit(self)

	# topple in the direction of the blow, then sink and vanish
	var fall := Vector3(from_dir.z, 0.0, -from_dir.x).normalized()
	if fall.length_squared() < 0.001:
		fall = Vector3.RIGHT
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation",
			Vector3(fall.x * 1.45, _facing, fall.z * 1.45), 0.55) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(model, "position:y", MODEL_Y - 0.10, 0.55)
	tw.chain().tween_interval(1.10)
	tw.chain().tween_property(model, "position:y", MODEL_Y - 2.0, 0.85) \
			.set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


# ------------------------------------------------------------------ animation

func _animate(delta: float) -> void:
	if model == null:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var spd := flat.length()
	model.rotation = Vector3(0, _facing, 0)

	var gait: float = clampf(spd / SPEED, 0.0, 1.5)
	_phase += delta * (1.5 + gait * 6.0)
	var sw: float = sin(_phase)
	var sw2: float = sin(_phase + PI)

	# shambling gait: shorter stride, heavier drag than the player's
	var leg: float = 0.46 * gait
	_rot("Thigh_R", Vector3(sw * leg, 0, 0))
	_rot("Thigh_L", Vector3(sw2 * leg * 0.85, 0, 0))
	_rot("Shin_R", Vector3(-maxf(0.0, -sw) * 0.85 * gait, 0, 0))
	_rot("Shin_L", Vector3(-maxf(0.0, -sw2) * 0.95 * gait, 0, 0))

	var hips: Node3D = _limbs.get("Hips")
	if hips != null:
		hips.position.y = 0.86 + sin(_phase * 2.0) * 0.030 * gait

	var down := sw < 0.0
	if gait > 0.3 and down != _step_flag:
		_step_flag = down
		if is_on_floor():
			Sfx.play_3d("step", global_position, -9.0, 0.82)
	elif gait <= 0.3:
		_step_flag = down

	match state:
		St.WINDUP:
			# both arms hauled overhead, torso arched back: unmissable tell
			var k: float = 1.0 - clampf(_timer / WINDUP_TIME, 0.0, 1.0)
			var e: float = k * k * (3.0 - 2.0 * k)
			_rot("UpperArm_R", Vector3(lerpf(-0.2, -2.55, e), 0, -0.45 * e))
			_rot("UpperArm_L", Vector3(lerpf(-0.2, -2.55, e), 0, 0.45 * e))
			_rot("Forearm_R", Vector3(lerpf(-0.5, -1.15, e), 0, 0))
			_rot("Forearm_L", Vector3(lerpf(-0.5, -1.15, e), 0, 0))
			_rot("ChestPivot", Vector3(-0.30 * e, 0, 0))
			_rot("NeckPivot", Vector3(-0.32 * e, 0, 0))
		St.STRIKE:
			var k2: float = 1.0 - clampf(_timer / STRIKE_TIME, 0.0, 1.0)
			var e2: float = k2 * k2
			_rot("UpperArm_R", Vector3(lerpf(-2.55, 0.85, e2), 0, 0))
			_rot("UpperArm_L", Vector3(lerpf(-2.55, 0.85, e2), 0, 0))
			_rot("Forearm_R", Vector3(lerpf(-1.15, -0.25, e2), 0, 0))
			_rot("Forearm_L", Vector3(lerpf(-1.15, -0.25, e2), 0, 0))
			_rot("ChestPivot", Vector3(lerpf(-0.30, 0.42, e2), 0, 0))
			_rot("NeckPivot", Vector3(lerpf(-0.32, 0.20, e2), 0, 0))
		St.STAGGER:
			var k3: float = clampf(_timer / STAGGER_TIME, 0.0, 1.0)
			var shudder: float = sin(_timer * 46.0) * 0.22 * k3
			_rot("ChestPivot", Vector3(-0.34 * k3, shudder, 0))
			_rot("NeckPivot", Vector3(-0.26 * k3, -shudder, 0))
			_rot("UpperArm_R", Vector3(0.55 * k3, 0, -0.42 * k3))
			_rot("UpperArm_L", Vector3(0.55 * k3, 0, 0.42 * k3))
			_rot("Forearm_R", Vector3(-0.42, 0, 0))
			_rot("Forearm_L", Vector3(-0.42, 0, 0))
		_:
			# idle/pursue: arms hang forward and sway, classic shuffle
			_rot("UpperArm_R", Vector3(-0.62 + sw2 * 0.26 * gait, 0, -0.16))
			_rot("UpperArm_L", Vector3(-0.62 + sw * 0.26 * gait, 0, 0.16))
			_rot("Forearm_R", Vector3(-0.78, 0, 0))
			_rot("Forearm_L", Vector3(-0.78, 0, 0))
			_rot("ChestPivot", Vector3(0.0, -sw * 0.10 * gait, 0))
			_rot("NeckPivot", Vector3(0.0, sw * 0.06 * gait, 0))
