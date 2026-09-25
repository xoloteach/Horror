class_name Player
extends CharacterBody3D
## Production player controller driven by KayKit's authored Skeleton3D clips.
##
## Gameplay owns movement/combat timing; the view consumes semantic states. Hit
## windows trace the animated axe between its previous/current blade positions
## and reject targets hidden behind world geometry. Light inputs buffer into a
## three-hit chain instead of being discarded during an active attack.

signal health_changed(current: float, maximum: float)
signal focus_changed(current: float, maximum: float)
signal died
signal combo_changed(step: int)
signal perfect_dodge

const MODEL := preload("res://assets/production/actors/Barbarian.glb")
const SHIELD := preload("res://assets/production/weapons/shield_round_barbarian.gltf")

enum State { MOVE, ATTACK, DODGE, HURT, RECALL, CATCH, DEAD }
enum AttackKind { NONE, LIGHT, HEAVY, THROW }

const BASE_MAX_HEALTH := 125.0
const BASE_MAX_FOCUS := 100.0
const SPEED := 6.2
const AIM_SPEED := 3.1
const ACCEL := 19.0
const DECEL := 22.0
const GRAVITY := 24.0
const TURN_SPEED := 15.0
const CAP_HEIGHT := 1.68
const CAP_RADIUS := 0.34

const DODGE_SPEED := 11.8
const DODGE_TIME := 0.48
const DODGE_COOLDOWN := 0.20
const DODGE_INVULN_START := 0.07
const DODGE_INVULN_END := 0.36

const LIGHT_DURATIONS := [0.48, 0.52, 0.62]
const LIGHT_CLIPS := [
	"1H_Melee_Attack_Slice_Diagonal",
	"1H_Melee_Attack_Slice_Horizontal",
	"1H_Melee_Attack_Chop",
]
const LIGHT_WINDOWS := [Vector2(0.27, 0.52), Vector2(0.26, 0.54), Vector2(0.31, 0.60)]
const HEAVY_DURATION := 0.82
const THROW_DURATION := 0.70
const DAMAGE_LIGHT := [18.0, 21.0, 28.0]
const DAMAGE_HEAVY := 46.0
const DAMAGE_HEAVY_UNPOWERED := 34.0
const HEAVY_FOCUS_COST := 24.0
const DAMAGE_UNARMED := 10.0
const MELEE_RANGE := 3.1
const HIT_RADIUS := 0.88

var state: State = State.MOVE
var attack_kind: AttackKind = AttackKind.NONE
var health := BASE_MAX_HEALTH
var max_health := BASE_MAX_HEALTH
var focus := BASE_MAX_FOCUS
var max_focus := BASE_MAX_FOCUS
var damage_multiplier := 1.0
var control_enabled := true

var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var rig: CameraRig
var axe: LeviathanAxe
var hand: Node3D

var _world_root: Node3D
var _facing := 0.0
var _current_animation: StringName = &""
var _locomotion_phase := 0.0
var _step_side := false

var _attack_time := 0.0
var _attack_duration := 0.5
var _combo_step := 0
var _combo_timeout := 0.0
var _queued_kind: AttackKind = AttackKind.NONE
var _attack_hits: Array[Node] = []
var _active_started := false
var _pending_throw_target := Vector3.ZERO
var _throw_released := false
var _empowered_heavy := false
var _previous_blade := Vector3.ZERO
var _attack_target_ref: WeakRef

var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _dodge_direction := Vector3.FORWARD
var _hurt_time := 0.0
var _catch_time := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	_world_root = get_parent() as Node3D

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAP_RADIUS
	capsule.height = CAP_HEIGHT
	collision.shape = capsule
	collision.position = Vector3(0, CAP_HEIGHT * 0.5, 0)
	add_child(collision)

	model = MODEL.instantiate()
	model.name = "BarbarianVisual"
	add_child(model)
	_tune_model(model)
	animation_player = _find_animation_player(model)
	skeleton = _find_skeleton(model)
	if animation_player == null or skeleton == null:
		push_error("Player production actor is missing AnimationPlayer/Skeleton3D")
		return

	hand = _bone_socket("handslot.r", "AxeSocket")
	var shield_socket := _bone_socket("handslot.l", "ShieldSocket")
	var shield: Node3D = SHIELD.instantiate()
	shield.name = "GuardianShield"
	shield.scale = Vector3.ONE * 0.90
	shield_socket.add_child(shield)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.position = Vector3(0, 1.30, 0)
	add_child(rig)

	axe = LeviathanAxe.new()
	axe.name = "LeviathanAxe"
	hand.add_child(axe)
	axe.setup(self, hand, _world_root)
	axe.caught.connect(_on_axe_caught)

	_play_animation("Idle", 0.0, 1.0)
	health_changed.emit(health, max_health)
	focus_changed.emit(focus, max_focus)


func _tune_model(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.get_surface_override_material_count():
			var source := mesh_node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				# Cool the bright source palette into weathered iron/leather while
				# preserving the authored atlas detail and skin contrast.
				material.albedo_color *= Color(0.78, 0.84, 0.94, 1.0)
				material.roughness = maxf(material.roughness, 0.55)
				mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_tune_model(child)


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _bone_socket(bone: StringName, socket_name: String) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = socket_name
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	return attachment


# --------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled or state == State.DEAD:
		return
	if event is InputEventMouseButton and event.pressed and not Boot.touch_active:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
	if event.is_action_pressed("ui_release") and not Boot.touch_active:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not Boot.input_unlocked():
		return

	if event.is_action_pressed("attack_light"):
		if Input.is_action_pressed("aim") and axe.can_throw():
			_start_throw()
		else:
			_request_attack(AttackKind.LIGHT)
	elif event.is_action_pressed("attack_heavy"):
		_request_attack(AttackKind.HEAVY)
	elif event.is_action_pressed("recall") or event.is_action_pressed("recall_mouse"):
		_start_recall()
	elif event.is_action_pressed("dodge"):
		_start_dodge()


func _request_attack(kind: AttackKind) -> void:
	if state == State.ATTACK:
		if attack_kind != AttackKind.THROW and _attack_time / _attack_duration >= 0.36:
			_queued_kind = kind
		return
	if state in [State.DODGE, State.HURT, State.RECALL, State.CATCH, State.DEAD]:
		return
	_begin_attack(kind)


func _begin_attack(kind: AttackKind) -> void:
	state = State.ATTACK
	attack_kind = kind
	_attack_time = 0.0
	_attack_hits.clear()
	_active_started = false
	_throw_released = false
	_previous_blade = axe.edge_world_position() if axe != null else global_position
	_attack_target_ref = null
	var assisted := _best_assist_target()
	if assisted != null:
		_attack_target_ref = weakref(assisted)

	if kind == AttackKind.LIGHT:
		if _combo_timeout <= 0.0:
			_combo_step = 0
		_attack_duration = LIGHT_DURATIONS[_combo_step]
		_play_timed(LIGHT_CLIPS[_combo_step], _attack_duration, 0.06)
		Sfx.play_3d("swing", global_position + Vector3.UP * 1.15, -1.0,
				1.0 + _combo_step * 0.03)
		rig.add_fov_kick(0.75 + _combo_step * 0.22)
		combo_changed.emit(_combo_step + 1)
	elif kind == AttackKind.HEAVY:
		_attack_duration = HEAVY_DURATION
		_empowered_heavy = focus >= HEAVY_FOCUS_COST
		if _empowered_heavy:
			focus -= HEAVY_FOCUS_COST
			focus_changed.emit(focus, max_focus)
		_play_timed("2H_Melee_Attack_Chop", _attack_duration, 0.08)
		Sfx.play_3d("swing_heavy", global_position + Vector3.UP * 1.15, 1.5)
		Sfx.play_3d("grunt", global_position + Vector3.UP * 1.35, -3.0)
		rig.add_fov_kick(2.2)


func _start_throw() -> void:
	if state in [State.ATTACK, State.DODGE, State.HURT, State.RECALL, State.CATCH, State.DEAD]:
		return
	var exclude: Array[RID] = [get_rid()]
	_pending_throw_target = rig.aim_point(70.0, exclude)
	state = State.ATTACK
	attack_kind = AttackKind.THROW
	_attack_time = 0.0
	_attack_duration = THROW_DURATION
	_attack_hits.clear()
	_throw_released = false
	_play_timed("Throw", THROW_DURATION, 0.05)
	rig.add_fov_kick(1.35)
	Sfx.play_3d("grunt", global_position + Vector3.UP * 1.35, -4.0)


func _start_recall() -> void:
	if not axe.can_recall() or state in [State.DODGE, State.HURT, State.DEAD]:
		return
	axe.recall()
	state = State.RECALL
	attack_kind = AttackKind.NONE
	_play_animation("Block", 0.10, 1.15)


func _on_axe_caught() -> void:
	if state == State.DEAD:
		return
	state = State.CATCH
	_catch_time = 0.34
	rig.add_fov_kick(1.6)
	_play_timed("Block_Hit", _catch_time, 0.02)


func _start_dodge() -> void:
	if state in [State.DODGE, State.HURT, State.DEAD] or _dodge_cooldown > 0.0:
		return
	var wish := _wish_direction()
	if wish.length_squared() < 0.01:
		wish = _forward()
	_dodge_direction = wish.normalized()
	_dodge_time = 0.0
	_dodge_cooldown = DODGE_TIME + DODGE_COOLDOWN
	state = State.DODGE
	attack_kind = AttackKind.NONE
	_queued_kind = AttackKind.NONE

	var local_direction := model.global_transform.basis.inverse() * _dodge_direction
	var clip := "Dodge_Forward"
	if absf(local_direction.x) > absf(local_direction.z):
		clip = "Dodge_Right" if local_direction.x > 0 else "Dodge_Left"
	elif local_direction.z > 0.15:
		clip = "Dodge_Backward"
	_play_timed(clip, DODGE_TIME, 0.04)
	Sfx.play_3d("dodge", global_position + Vector3.UP, -1.0)


func _wish_direction() -> Vector3:
	var input := Boot.move_axis()
	if input.length_squared() < 0.0004:
		return Vector3.ZERO
	return (rig.flat_forward() * -input.y + rig.flat_right() * input.x).normalized()


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_combo_timeout = maxf(0.0, _combo_timeout - delta)
	focus = minf(max_focus, focus + delta * 8.0)
	var aiming := control_enabled and Input.is_action_pressed("aim") and state != State.DEAD \
			and Boot.input_unlocked()
	rig.set_aiming(aiming)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)

	match state:
		State.DODGE:
			_simulate_dodge(delta)
		State.ATTACK:
			_simulate_attack(delta, aiming)
		State.HURT:
			_simulate_hurt(delta)
		State.RECALL:
			_simulate_recall(delta)
		State.CATCH:
			_simulate_catch(delta)
		State.DEAD:
			_brake(delta)
		_:
			_simulate_move(delta, aiming)

	move_and_slide()
	# KayKit characters are authored facing +Z; gameplay forward is -Z.
	model.rotation.y = _facing + PI
	_update_locomotion_animation(delta, aiming)


func _simulate_move(delta: float, aiming: bool) -> void:
	var wish := _wish_direction() if control_enabled else Vector3.ZERO
	var top_speed := AIM_SPEED if aiming else SPEED
	var flat := Vector3(velocity.x, 0, velocity.z)
	if wish.length_squared() > 0.01:
		flat = flat.move_toward(wish * top_speed, ACCEL * delta)
	else:
		flat = flat.move_toward(Vector3.ZERO, DECEL * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	var target_facing := _facing
	if aiming:
		target_facing = atan2(-rig.flat_forward().x, -rig.flat_forward().z)
	elif flat.length() > 0.35:
		target_facing = atan2(-flat.x, -flat.z)
	_facing = _lerp_angle(_facing, target_facing, TURN_SPEED * delta)


func _simulate_dodge(delta: float) -> void:
	_dodge_time += delta
	var normalized := clampf(_dodge_time / DODGE_TIME, 0.0, 1.0)
	var speed := DODGE_SPEED * (1.0 - normalized * normalized)
	velocity.x = _dodge_direction.x * speed
	velocity.z = _dodge_direction.z * speed
	_facing = _lerp_angle(_facing,
			atan2(-_dodge_direction.x, -_dodge_direction.z), 18.0 * delta)
	if _dodge_time >= DODGE_TIME:
		state = State.MOVE


func _simulate_attack(delta: float, aiming: bool) -> void:
	_attack_time += delta
	var normalized := clampf(_attack_time / _attack_duration, 0.0, 1.0)
	var push := 0.0
	if attack_kind == AttackKind.LIGHT and normalized > 0.22 and normalized < 0.58:
		push = 2.4 + _combo_step * 0.35
	elif attack_kind == AttackKind.HEAVY and normalized > 0.28 and normalized < 0.65:
		push = 3.7
	var forward := _forward()
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.move_toward(forward * push, 30.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	if aiming:
		_facing = _lerp_angle(_facing,
				atan2(-rig.flat_forward().x, -rig.flat_forward().z), 18.0 * delta)
	elif _attack_target_ref != null:
		var assisted_target := _attack_target_ref.get_ref() as Node3D
		if is_instance_valid(assisted_target):
			var toward := assisted_target.global_position - global_position
			toward.y = 0.0
			if toward.length_squared() > 0.01 and toward.length() < 5.2:
				_facing = _lerp_angle(_facing,
						atan2(-toward.x, -toward.z), 20.0 * delta)

	if attack_kind == AttackKind.THROW:
		if not _throw_released and normalized >= 0.33:
			_throw_released = true
			axe.throw(hand.global_position, _pending_throw_target)
	else:
		var window := Vector2(0.33, 0.61)
		if attack_kind == AttackKind.LIGHT:
			window = LIGHT_WINDOWS[_combo_step]
		if normalized >= window.x and normalized <= window.y:
			if not _active_started:
				_active_started = true
				_previous_blade = axe.edge_world_position()
			_weapon_sweep(attack_kind == AttackKind.HEAVY)
		_previous_blade = axe.edge_world_position()

	if _attack_time >= _attack_duration:
		if _queued_kind != AttackKind.NONE and axe.is_held():
			var next := _queued_kind
			_queued_kind = AttackKind.NONE
			if next == AttackKind.LIGHT:
				_combo_step = (_combo_step + 1) % LIGHT_CLIPS.size()
				_combo_timeout = 0.72
			_begin_attack(next)
		else:
			_combo_timeout = 0.62 if attack_kind == AttackKind.LIGHT else 0.0
			if attack_kind == AttackKind.LIGHT and _combo_step >= LIGHT_CLIPS.size() - 1:
				_combo_step = 0
			state = State.MOVE
			attack_kind = AttackKind.NONE


func _simulate_hurt(delta: float) -> void:
	_hurt_time -= delta
	_brake(delta)
	if _hurt_time <= 0.0:
		state = State.MOVE


func _simulate_recall(delta: float) -> void:
	_brake(delta, 15.0)
	if axe.is_held():
		_on_axe_caught()


func _simulate_catch(delta: float) -> void:
	_catch_time -= delta
	_brake(delta, 16.0)
	if _catch_time <= 0.0:
		state = State.MOVE


func _brake(delta: float, rate := DECEL) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _weapon_sweep(heavy: bool) -> void:
	if axe == null or not axe.is_held():
		_unarmed_sweep(heavy)
		return
	var blade := axe.edge_world_position()
	var hand_position := hand.global_position
	for candidate in get_tree().get_nodes_in_group("enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy in _attack_hits or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_hit"):
			continue
		var target := enemy.global_position + Vector3.UP * 0.95
		if enemy.has_method("hit_point"):
			target = enemy.hit_point()
		if global_position.distance_to(target) > MELEE_RANGE:
			continue
		var swept := LeviathanAxe.segment_distance(_previous_blade, blade, target)
		var haft := LeviathanAxe.segment_distance(hand_position, blade, target)
		if minf(swept, haft) > HIT_RADIUS:
			continue
		if _world_occludes(target):
			continue
		_register_melee_hit(enemy, target, heavy)


func _unarmed_sweep(heavy: bool) -> void:
	var forward := _forward()
	for candidate in get_tree().get_nodes_in_group("enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy in _attack_hits or not enemy.has_method("take_hit"):
			continue
		var to_enemy := enemy.global_position - global_position
		to_enemy.y = 0
		if to_enemy.length() <= 1.65 and forward.dot(to_enemy.normalized()) > 0.35:
			_register_melee_hit(enemy, enemy.global_position + Vector3.UP, heavy)


func _best_assist_target() -> Node3D:
	var best: Node3D
	var best_score := INF
	var forward := _forward()
	for candidate in get_tree().get_nodes_in_group("enemy"):
		var enemy := candidate as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var offset := enemy.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance < 0.05 or distance > 5.4:
			continue
		var alignment := forward.dot(offset / distance)
		if alignment < 0.20:
			continue
		if _world_occludes(enemy.global_position + Vector3.UP):
			continue
		var score := distance - alignment * 1.8
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _world_occludes(target: Vector3) -> bool:
	var from := global_position + Vector3.UP * 1.15
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _register_melee_hit(enemy: Node3D, target: Vector3, heavy: bool) -> void:
	_attack_hits.append(enemy)
	var direction := target - global_position
	direction.y = 0
	direction = direction.normalized() if direction.length_squared() > 0.001 else _forward()
	var damage: float = (DAMAGE_HEAVY if _empowered_heavy else DAMAGE_HEAVY_UNPOWERED) \
			if heavy else float(DAMAGE_LIGHT[_combo_step])
	if not axe.is_held():
		damage = DAMAGE_UNARMED
	damage *= damage_multiplier
	enemy.take_hit(damage, direction, heavy)
	Fx.blood(_world_root, target, -direction, 1.25 if heavy else 0.85)
	if heavy and _empowered_heavy:
		Fx.rune_flash(_world_root, target)
	Sfx.play_3d("flesh", target, 1.0)
	Juice.impact(0.48 if heavy else 0.26, direction,
			0.05 if heavy else 0.14, 0.082 if heavy else 0.045)
	focus = minf(max_focus, focus + (12.0 if heavy else 6.0))
	focus_changed.emit(focus, max_focus)


# -------------------------------------------------------------------- damage

func take_hit(amount: float, from_direction: Vector3) -> void:
	if get_meta("qa_invulnerable", false):
		return
	if state == State.DEAD:
		return
	if state == State.DODGE and _dodge_time >= DODGE_INVULN_START \
			and _dodge_time <= DODGE_INVULN_END:
		focus = minf(max_focus, focus + 18.0)
		focus_changed.emit(focus, max_focus)
		perfect_dodge.emit()
		Juice.add_trauma(0.12, -from_direction)
		return
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	Juice.impact(0.52, from_direction, 0.10, 0.06)
	Sfx.play_2d("hurt_player", 0.0)
	velocity += from_direction.normalized() * 3.8
	if health <= 0.0:
		state = State.DEAD
		control_enabled = false
		_play_timed("Death_A", 1.15, 0.06)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
	else:
		state = State.HURT
		_hurt_time = 0.34
		_play_timed("Hit_A" if randi() % 2 == 0 else "Hit_B", _hurt_time, 0.04)


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)


func apply_upgrade(id: StringName) -> void:
	match id:
		&"fury":
			damage_multiplier += 0.18
		&"vitality":
			max_health += 28.0
			health = minf(max_health, health + 28.0)
		&"focus":
			max_focus += 25.0
			focus = max_focus
	health_changed.emit(health, max_health)
	focus_changed.emit(focus, max_focus)


func set_control_enabled(enabled: bool) -> void:
	control_enabled = enabled
	rig.enabled = enabled
	if not enabled:
		Boot.reset_virtual_input()


func hit_point() -> Vector3:
	return global_position + Vector3.UP * 1.05


func is_alive() -> bool:
	return state != State.DEAD


# ---------------------------------------------------------------- animation

func _play_animation(name: StringName, blend := 0.14, speed := 1.0) -> void:
	if animation_player == null or not animation_player.has_animation(name):
		push_warning("Player animation missing: %s" % name)
		return
	if _current_animation == name and animation_player.is_playing():
		animation_player.speed_scale = speed
		return
	_current_animation = name
	animation_player.play(name, blend, speed)


func _play_timed(name: StringName, duration: float, blend := 0.08) -> void:
	if animation_player == null or not animation_player.has_animation(name):
		return
	var clip := animation_player.get_animation(name)
	var speed := clip.length / maxf(duration, 0.05)
	_play_animation(name, blend, speed)


func _update_locomotion_animation(delta: float, aiming: bool) -> void:
	if state in [State.ATTACK, State.DODGE, State.HURT, State.CATCH, State.DEAD]:
		return
	if state == State.RECALL:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var speed := flat.length()
	if speed < 0.22:
		var idle_clip := "Unarmed_Idle"
		if axe.is_held():
			idle_clip = "2H_Melee_Idle" if aiming else "Idle"
		_play_animation(idle_clip, 0.18, 1.0)
		return

	var clip := "Running_A"
	if aiming:
		var local := model.global_transform.basis.inverse() * flat.normalized()
		if absf(local.x) > 0.46:
			clip = "Running_Strafe_Right" if local.x > 0 else "Running_Strafe_Left"
		elif local.z > 0.30:
			clip = "Walking_Backwards"
	var animation_speed := clampf(speed / (SPEED * 0.72), 0.70, 1.45)
	_play_animation(clip, 0.16, animation_speed)

	_locomotion_phase += delta * speed * 1.35
	var side := sin(_locomotion_phase) >= 0.0
	if side != _step_side and is_on_floor():
		_step_side = side
		Sfx.play_3d("step", global_position, -4.0, randf_range(0.94, 1.04))


func _forward() -> Vector3:
	return -Vector3(sin(_facing), 0, cos(_facing))


static func _lerp_angle(from: float, to: float, weight: float) -> float:
	return from + wrapf(to - from, -PI, PI) * clampf(weight, 0.0, 1.0)


func revive() -> void:
	max_health = BASE_MAX_HEALTH
	health = max_health
	focus = max_focus
	damage_multiplier = 1.0
	state = State.MOVE
	attack_kind = AttackKind.NONE
	velocity = Vector3.ZERO
	control_enabled = true
	_play_animation("Idle", 0.0, 1.0)
	health_changed.emit(health, max_health)
	focus_changed.emit(focus, max_focus)
