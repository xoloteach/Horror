# Enemy: draugr CharacterBody3D with a simple robust state machine.
# IDLE -> CHASE -> WINDUP (telegraph) -> LUNGE -> RECOVER, plus STAGGER and DYING.
# Uses flat-arena pursuit steering with separation (no NavigationServer).
class_name Enemy
extends CharacterBody3D

signal died(enemy: Enemy)

enum S { IDLE, CHASE, WINDUP, LUNGE, RECOVER, STAGGER, DYING }

const GRAVITY := 22.0

var max_hp := 60.0
var hp := 60.0
var alive := true
var speed := 3.4
var state: int = S.IDLE
var state_t := 0.0
var player_ref: Node3D = null

var _stagger_pool := 0.0
var _lunge_dir := Vector3.ZERO
var _lunge_hit := false
var _death_t := 0.0
var _walk_phase := 0.0

var visual: Node3D
var rig: CharRig
var chest_socket: Node3D   # direct child named "ChestSocket" (axe embed point)
var _chest_attach: BoneAttachment3D = null  # real-rig chest tracker, if any


func _ready() -> void:
	add_to_group("enemies")
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	visual = MeshFactory.create_draugr()
	add_child(visual)
	rig = CharRig.from_node(visual)
	# Axe embed point: keep the "ChestSocket" direct-child contract, but have
	# it track the real chest bone when the GLB rig is in use.
	_chest_attach = rig.chest_attachment()
	chest_socket = Node3D.new()
	chest_socket.name = "ChestSocket"
	add_child(chest_socket)
	if _chest_attach != null:
		chest_socket.global_transform = _chest_attach.global_transform
	else:
		chest_socket.position = Vector3(0, 1.25, 0)
	rig.set_arm("L", -1.0)
	rig.set_arm("R", -1.0)
	state = S.IDLE
	state_t = 0.6


func chest_position() -> Vector3:
	return chest_socket.global_position


func take_damage(amount: float, _from_pos: Vector3, heavy: bool) -> void:
	if not alive:
		return
	hp -= amount
	if hp <= 0.0:
		die()
		return
	_stagger_pool += amount
	if heavy or _stagger_pool >= 25.0:
		_stagger_pool = 0.0
		state = S.STAGGER
		state_t = 0.45


func die() -> void:
	if not alive:
		return
	alive = false
	state = S.DYING
	_death_t = 0.0
	# drop the axe if it was embedded in this body
	var axes := get_tree().get_nodes_in_group("axe")
	if axes.size() > 0:
		var a: Node = axes[0]
		if a.get("host_enemy") == self:
			a.on_host_died()
	AudioManager.play_3d("blood_impact", chest_position(), -2.0, 0.8)
	died.emit(self)


func _physics_process(delta: float) -> void:
	# keep the embed socket glued to the real chest bone
	if _chest_attach != null and is_instance_valid(_chest_attach):
		chest_socket.global_transform = _chest_attach.global_transform
	if not alive:
		_death_t += delta
		var k := clampf(_death_t / 0.45, 0.0, 1.0)
		visual.rotation.z = lerpf(0.0, 1.5, k)
		if _death_t > 0.9:
			position.y -= delta * 1.1
		if _death_t > 1.8:
			queue_free()
		return
	if player_ref == null or not is_instance_valid(player_ref):
		return

	state_t -= delta
	match state:
		S.IDLE:
			_decel(delta)
			if state_t <= 0.0:
				state = S.CHASE
		S.CHASE:
			var to_p := player_ref.global_position - global_position
			to_p.y = 0.0
			var dist := to_p.length()
			var dir := to_p.normalized() if dist > 0.05 else Vector3.ZERO
			var push := _separation()
			var v := dir * speed + push
			velocity.x = v.x
			velocity.z = v.z
			_face(dir, delta)
			_walk_anim(delta, true)
			if dist < 2.3:
				state = S.WINDUP
				state_t = 0.55
				AudioManager.play_3d("roar_enemy", chest_position(), -3.0, randf_range(0.9, 1.15))
		S.WINDUP:
			_decel(delta)
			var wk := 1.0 - exp(-8.0 * delta)
			rig.set_torso(lerpf(rig.get_torso(), -0.55, wk))
			rig.set_arm("L", lerpf(rig.get_arm("L"), -2.2, wk))
			rig.set_arm("R", lerpf(rig.get_arm("R"), -2.2, wk))
			if player_ref != null:
				_face((player_ref.global_position - global_position), delta)
			if state_t <= 0.0:
				var tp := player_ref.global_position - global_position
				tp.y = 0.0
				_lunge_dir = tp.normalized() if tp.length() > 0.05 else -global_transform.basis.z
				state = S.LUNGE
				state_t = 0.32
				_lunge_hit = false
		S.LUNGE:
			velocity.x = _lunge_dir.x * 9.5
			velocity.z = _lunge_dir.z * 9.5
			rig.set_torso(lerpf(rig.get_torso(), 0.45, 1.0 - exp(-10.0 * delta)))
			if not _lunge_hit:
				var d := player_ref.global_position - global_position
				d.y = 0.0
				if d.length() < 1.9:
					_lunge_hit = true
					if player_ref.has_method("take_damage"):
						player_ref.take_damage(12.0)
			if state_t <= 0.0:
				state = S.RECOVER
				state_t = 0.5
		S.RECOVER:
			_decel(delta)
			rig.set_torso(lerpf(rig.get_torso(), 0.28, 1.0 - exp(-6.0 * delta)))
			if state_t <= 0.0:
				state = S.CHASE
		S.STAGGER:
			_decel(delta)
			var sk := 1.0 - exp(-10.0 * delta)
			rig.set_torso(lerpf(rig.get_torso(), 0.5, sk))
			rig.set_head(lerpf(rig.get_head(), -0.4, sk))
			if state_t <= 0.0:
				rig.set_torso(0.28)
				rig.set_head(0.0)
				state = S.CHASE

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()


func _to_chase() -> void:
	state = S.CHASE


func _decel(delta: float) -> void:
	var k := 1.0 - exp(-14.0 * delta)
	velocity.x = lerpf(velocity.x, 0.0, k)
	velocity.z = lerpf(velocity.z, 0.0, k)


func _face(dir: Vector3, delta: float) -> void:
	var d := dir
	d.y = 0.0
	if d.length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-8.0 * delta))


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d := global_position - (o as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 2.0:
			push += d.normalized() * (2.0 - l) * 2.5
	return push


func _walk_anim(delta: float, moving: bool) -> void:
	var hs := Vector2(velocity.x, velocity.z).length()
	_walk_phase += hs * delta * 2.0
	var sw := sin(_walk_phase) * clampf(hs / 3.0, 0.0, 1.0)
	rig.set_leg("L", sw * 0.5)
	rig.set_leg("R", -sw * 0.5)
	if state == S.CHASE:
		rig.set_arm("L", lerpf(rig.get_arm("L"), -1.0 - sw * 0.2, delta * 6.0))
		rig.set_arm("R", lerpf(rig.get_arm("R"), -1.0 + sw * 0.2, delta * 6.0))
