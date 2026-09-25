class_name Draugr
extends CharacterBody3D
## Shared production enemy actor for four skeleton roles and the Jarl boss.
## Every role uses the same KayKit humanoid contract but a different mesh,
## authored animation vocabulary, combat spacing, telegraph color and weapon.

signal died(enemy: Draugr)
signal health_changed(current: float, maximum: float)
signal boss_phase_changed(phase: int)

enum Archetype { WARRIOR, ROGUE, MAGE, MINION, BOSS }
enum State { SPAWN, PURSUE, WINDUP, STRIKE, RECOVER, STAGGER, DEAD }
enum AttackMode { MELEE, PROJECTILE, SHOCKWAVE }

const MAX_HEALTH := 100.0
const GRAVITY := 24.0
const SIGHT := 34.0
const TURN_SPEED := 8.5
const SEPARATION_RADIUS := 1.55
const STAGGER_DECAY := 24.0
const BOLT := preload("res://scripts/bone_bolt.gd")
const CIRCLE_TEXTURE := preload("res://assets/production/vfx/circle_03.png")

const MODEL_PATHS := {
	Archetype.WARRIOR: "res://assets/production/actors/Skeleton_Warrior.glb",
	Archetype.ROGUE: "res://assets/production/actors/Skeleton_Rogue.glb",
	Archetype.MAGE: "res://assets/production/actors/Skeleton_Mage.glb",
	Archetype.MINION: "res://assets/production/actors/Skeleton_Minion.glb",
	Archetype.BOSS: "res://assets/production/actors/Skeleton_Warrior.glb",
}
const WEAPON_PATHS := {
	Archetype.WARRIOR: "res://assets/production/weapons/Skeleton_Axe.gltf",
	Archetype.ROGUE: "res://assets/production/weapons/Skeleton_Blade.gltf",
	Archetype.MAGE: "res://assets/production/weapons/Skeleton_Staff.gltf",
	Archetype.MINION: "res://assets/production/weapons/Skeleton_Blade.gltf",
	Archetype.BOSS: "res://assets/production/weapons/Skeleton_Axe.gltf",
}
const TINTS := {
	Archetype.WARRIOR: Color(0.72, 0.50, 0.48),
	Archetype.ROGUE: Color(0.56, 0.40, 0.76),
	Archetype.MAGE: Color(0.74, 0.30, 0.62),
	Archetype.MINION: Color(0.62, 0.68, 0.70),
	Archetype.BOSS: Color(0.42, 0.16, 0.12),
}
const TELEGRAPH_COLORS := {
	Archetype.WARRIOR: Color(1.0, 0.27, 0.12),
	Archetype.ROGUE: Color(0.85, 0.22, 0.60),
	Archetype.MAGE: Color(0.62, 0.20, 1.0),
	Archetype.MINION: Color(1.0, 0.48, 0.14),
	Archetype.BOSS: Color(1.0, 0.08, 0.02),
}

var archetype: Archetype = Archetype.WARRIOR
var state: State = State.SPAWN
var health := MAX_HEALTH
var max_health := MAX_HEALTH
var rank := 1
var is_boss := false

var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var chest: Node3D

var _player: Node3D
var _world_root: Node3D
var _current_animation: StringName = &""
var _facing := 0.0
var _timer := 0.0
var _cooldown := 0.0
var _stagger_accum := 0.0
var _stagger_threshold := 32.0
var _move_speed := 3.5
var _acceleration := 11.0
var _damage := 14.0
var _attack_range := 2.35
var _windup_time := 0.58
var _strike_time := 0.22
var _recover_time := 0.52
var _lunge_speed := 8.5
var _attack_mode: AttackMode = AttackMode.MELEE
var _attack_counter := 0
var _enraged := false
var _step_phase := 0.0
var _step_side := false
var _telegraph: MeshInstance3D
var _telegraph_material: StandardMaterial3D
var _telegraph_tween: Tween
var _aura_light: OmniLight3D
var _dead := false


func configure(player: Node3D, role: Archetype, difficulty_rank := 1) -> void:
	_player = player
	archetype = role
	rank = maxi(1, difficulty_rank)


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	_world_root = get_parent() as Node3D
	_configure_stats()
	_build_collision()
	_build_model()
	_build_telegraph()
	if is_boss:
		_build_boss_aura()
	_timer = 0.74
	_cooldown = 0.8
	_play_timed("Spawn_Ground_Skeletons", _timer, 0.0)
	health_changed.emit(health, max_health)


func _configure_stats() -> void:
	match archetype:
		Archetype.WARRIOR:
			max_health = 112.0 + rank * 9.0
			_move_speed = 3.55
			_damage = 15.0 + rank * 0.8
		Archetype.ROGUE:
			max_health = 78.0 + rank * 6.0
			_move_speed = 5.15
			_acceleration = 17.0
			_damage = 11.0 + rank * 0.65
			_attack_range = 2.05
			_windup_time = 0.34
			_recover_time = 0.32
			_lunge_speed = 11.0
			_stagger_threshold = 24.0
		Archetype.MAGE:
			max_health = 82.0 + rank * 6.0
			_move_speed = 3.05
			_damage = 13.0 + rank * 0.85
			_attack_range = 9.5
			_windup_time = 0.78
			_recover_time = 0.68
			_attack_mode = AttackMode.PROJECTILE
			_stagger_threshold = 22.0
		Archetype.MINION:
			max_health = 48.0 + rank * 4.0
			_move_speed = 4.45
			_acceleration = 15.0
			_damage = 8.0 + rank * 0.45
			_attack_range = 1.85
			_windup_time = 0.38
			_recover_time = 0.36
			_lunge_speed = 9.5
			_stagger_threshold = 16.0
		Archetype.BOSS:
			is_boss = true
			max_health = 690.0
			_move_speed = 3.9
			_acceleration = 14.0
			_damage = 25.0
			_attack_range = 3.0
			_windup_time = 0.72
			_strike_time = 0.28
			_recover_time = 0.58
			_lunge_speed = 10.0
			_stagger_threshold = 95.0
	health = max_health


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var scale_factor := 1.48 if is_boss else (0.78 if archetype == Archetype.MINION else 1.0)
	capsule.radius = 0.34 * scale_factor
	capsule.height = 1.72 * scale_factor
	collision.shape = capsule
	collision.position = Vector3(0, capsule.height * 0.5, 0)
	add_child(collision)


func _build_model() -> void:
	var packed: PackedScene = load(MODEL_PATHS[archetype])
	model = packed.instantiate()
	model.name = "SkeletonVisual"
	var visual_scale := 1.0
	if archetype == Archetype.MINION:
		visual_scale = 0.78
	elif is_boss:
		visual_scale = 1.48
	model.scale = Vector3.ONE * visual_scale
	add_child(model)
	_tune_visual(model, TINTS[archetype])
	animation_player = _find_animation_player(model)
	skeleton = _find_skeleton(model)
	if animation_player == null or skeleton == null:
		push_error("Skeleton actor missing production animation contract")
		return

	var hand := _bone_socket("handslot.r", "WeaponSocket")
	var weapon_scene: PackedScene = load(WEAPON_PATHS[archetype])
	var weapon: Node3D = weapon_scene.instantiate()
	weapon.name = "EnemyWeapon"
	if is_boss:
		weapon.scale = Vector3.ONE * 1.22
	hand.add_child(weapon)
	chest = _bone_socket("chest", "EmbedSocket")


func _tune_visual(node: Node, tint: Color) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.get_surface_override_material_count():
			var source := mesh_node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color *= tint
				material.roughness = maxf(material.roughness, 0.62)
				if is_boss:
					material.emission_enabled = true
					material.emission = Color(0.32, 0.025, 0.01)
					material.emission_energy_multiplier = 1.1
				mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_tune_visual(child, tint)


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


func _build_telegraph() -> void:
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "AttackTelegraph"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.35, 1.35)
	_telegraph_material = StandardMaterial3D.new()
	_telegraph_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_telegraph_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_telegraph_material.albedo_texture = CIRCLE_TEXTURE
	_telegraph_material.albedo_color = Color(TELEGRAPH_COLORS[archetype], 0.0)
	quad.material = _telegraph_material
	_telegraph.mesh = quad
	_telegraph.rotation.x = -PI * 0.5
	_telegraph.position.y = 0.035
	_telegraph.visible = false
	add_child(_telegraph)


func _build_boss_aura() -> void:
	_aura_light = OmniLight3D.new()
	_aura_light.light_color = Color(1.0, 0.12, 0.03)
	_aura_light.light_energy = 2.0
	_aura_light.omni_range = 7.5
	_aura_light.shadow_enabled = false
	_aura_light.position.y = 1.7
	add_child(_aura_light)


func set_player(player: Node3D) -> void:
	_player = player


func embed_anchor() -> Node3D:
	return chest if chest != null else model


func hit_point() -> Vector3:
	var height := 1.45 if is_boss else (0.78 if archetype == Archetype.MINION else 1.0)
	return global_position + Vector3.UP * height


func archetype_name() -> String:
	return Archetype.keys()[archetype].capitalize()


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = maxf(velocity.y, -0.1)
	_cooldown = maxf(0.0, _cooldown - delta)
	_stagger_accum = maxf(0.0, _stagger_accum - STAGGER_DECAY * delta)

	if state == State.DEAD:
		_brake(delta, 18.0)
		move_and_slide()
		return

	var to_player := Vector3.ZERO
	var distance := 999.0
	if is_instance_valid(_player):
		to_player = _player.global_position - global_position
		to_player.y = 0.0
		distance = to_player.length()

	match state:
		State.SPAWN:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				state = State.PURSUE
		State.PURSUE:
			_pursue(delta, to_player, distance)
		State.WINDUP:
			_windup(delta, to_player)
		State.STRIKE:
			_strike(delta, distance)
		State.RECOVER:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				state = State.PURSUE
		State.STAGGER:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				state = State.PURSUE
				_cooldown = maxf(_cooldown, 0.30)

	move_and_slide()
	# KayKit characters are authored facing +Z; AI/gameplay forward is -Z.
	model.rotation.y = _facing + PI
	_update_locomotion(delta)
	if is_boss and not _enraged and health <= max_health * 0.50:
		_enrage()


func _pursue(delta: float, to_player: Vector3, distance: float) -> void:
	if distance > SIGHT * 1.3:
		_brake(delta)
		return
	var direction := to_player.normalized() if distance > 0.01 else Vector3.ZERO
	if archetype == Archetype.MAGE:
		if distance < 5.4:
			direction = -direction
		elif distance <= 8.2:
			direction = Vector3(-direction.z, 0, direction.x) * (1.0 if get_instance_id() % 2 == 0 else -1.0)
	elif archetype == Archetype.ROGUE and distance > 2.4:
		var flank := Vector3(-direction.z, 0, direction.x)
		direction = (direction * 0.72 + flank * (0.42 if get_instance_id() % 2 == 0 else -0.42)).normalized()
	direction = _steer_around_world(direction)
	direction = (direction + _separation()).normalized()

	var desired_speed := _move_speed
	if archetype == Archetype.MAGE and distance >= 5.4 and distance <= 8.2:
		desired_speed *= 0.55
	var flat := Vector3(velocity.x, 0, velocity.z)
	flat = flat.move_toward(direction * desired_speed, _acceleration * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	_face(to_player, delta)

	var ready_range := _attack_range
	if archetype == Archetype.MAGE:
		ready_range = 9.0
	if distance <= ready_range and _cooldown <= 0.0:
		_begin_windup()


func _steer_around_world(direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.01:
		return direction
	var origin := global_position + Vector3.UP * 0.52
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1.55)
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return direction
	var side := Vector3(-direction.z, 0, direction.x)
	if get_instance_id() % 2 != 0:
		side = -side
	return (side * 0.85 - (hit["normal"] as Vector3) * 0.35).normalized()


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if candidate == self or not is_instance_valid(candidate):
			continue
		var other := candidate as Node3D
		if other == null:
			continue
		var offset := global_position - other.global_position
		offset.y = 0
		var distance := offset.length()
		if distance > 0.001 and distance < SEPARATION_RADIUS:
			push += offset.normalized() * (1.0 - distance / SEPARATION_RADIUS)
	return push * 0.82


func _begin_windup() -> void:
	state = State.WINDUP
	_timer = _windup_time
	set_meta("attack_landed", false)
	_attack_counter += 1
	_attack_mode = AttackMode.PROJECTILE if archetype == Archetype.MAGE else AttackMode.MELEE
	var clip := "1H_Melee_Attack_Chop"
	if archetype == Archetype.ROGUE:
		clip = "1H_Melee_Attack_Stab"
	elif archetype == Archetype.MINION:
		clip = "Unarmed_Melee_Attack_Punch_A"
	elif archetype == Archetype.MAGE:
		clip = "Spellcast_Shoot"
	elif is_boss:
		if _attack_counter % 3 == 0:
			clip = "Spellcast_Raise"
			_attack_mode = AttackMode.SHOCKWAVE
		elif _attack_counter % 2 == 0:
			clip = "2H_Melee_Attack_Spin"
		else:
			clip = "1H_Melee_Attack_Jump_Chop"
	_play_timed(clip, _windup_time + _strike_time, 0.10)
	_show_telegraph()
	Sfx.play_3d("roar", global_position + Vector3.UP * 1.25, -3.0 if not is_boss else 1.0,
			0.82 if is_boss else 1.0)


func _show_telegraph() -> void:
	_telegraph.visible = true
	_telegraph.scale = Vector3.ONE * 0.25
	_telegraph_material.albedo_color = Color(TELEGRAPH_COLORS[archetype], 0.18)
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var end_scale := 3.8 if is_boss else (2.2 if archetype == Archetype.MAGE else 1.45)
	_telegraph_tween.tween_property(_telegraph, "scale", Vector3.ONE * end_scale, _windup_time)
	_telegraph_tween.tween_property(_telegraph_material, "albedo_color:a", 0.92, _windup_time)


func _windup(delta: float, to_player: Vector3) -> void:
	_brake(delta, 20.0)
	_face(to_player, delta * 0.72)
	_timer -= delta
	if _timer <= 0.0:
		state = State.STRIKE
		_timer = _strike_time
		_telegraph.visible = false
		_execute_attack()


func _execute_attack() -> void:
	match _attack_mode:
		AttackMode.PROJECTILE:
			_fire_bolt()
		AttackMode.SHOCKWAVE:
			_shockwave()
		AttackMode.MELEE:
			pass


func _strike(delta: float, distance: float) -> void:
	_timer -= delta
	if _attack_mode == AttackMode.MELEE:
		var forward := _forward()
		var flat := Vector3(velocity.x, 0, velocity.z)
		flat = flat.move_toward(forward * _lunge_speed, 38.0 * delta)
		velocity.x = flat.x
		velocity.z = flat.z
		if _timer <= _strike_time * 0.52:
			_try_melee_damage(distance)
	if _timer <= 0.0:
		state = State.RECOVER
		_timer = _recover_time
		_cooldown = randf_range(0.55, 1.25) * (0.72 if _enraged else 1.0)


func _try_melee_damage(distance: float) -> void:
	if not is_instance_valid(_player) or get_meta("attack_landed", false):
		return
	var reach := _attack_range + (0.95 if is_boss else 0.65)
	if distance > reach:
		return
	var toward := _player.global_position - global_position
	toward.y = 0
	if toward.length_squared() < 0.001 or _forward().dot(toward.normalized()) < 0.24:
		return
	if _world_occludes(_player.global_position + Vector3.UP):
		return
	set_meta("attack_landed", true)
	if _player.has_method("take_hit"):
		_player.take_hit(_damage, toward.normalized())


func _fire_bolt() -> void:
	if not is_instance_valid(_player):
		return
	var bolt := BOLT.new() as BoneBolt
	_world_root.add_child(bolt)
	bolt.setup(_player, global_position + Vector3.UP * 1.45,
			_damage, 12.5 + rank * 0.4, get_rid(), TELEGRAPH_COLORS[archetype])


func _shockwave() -> void:
	var wave := MeshInstance3D.new()
	wave.name = "JarlShockwave"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = CIRCLE_TEXTURE
	material.albedo_color = Color(1.0, 0.12, 0.025, 0.95)
	quad.material = material
	wave.mesh = quad
	wave.rotation.x = -PI * 0.5
	_world_root.add_child(wave)
	wave.global_position = global_position + Vector3.UP * 0.06
	wave.scale = Vector3.ONE * 0.4
	var tween := wave.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector3.ONE * 10.0, 0.58) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.58)
	tween.chain().tween_callback(wave.queue_free)
	if is_instance_valid(_player):
		var offset := _player.global_position - global_position
		offset.y = 0
		if offset.length() < 5.2 and not _world_occludes(_player.global_position + Vector3.UP):
			_player.take_hit(_damage * 0.82, offset.normalized())
	Juice.impact(0.36, Vector3.UP, 0.16, 0.055)


func _world_occludes(target: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target)
	query.collision_mask = 1
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _face(to_player: Vector3, delta: float) -> void:
	if to_player.length_squared() < 0.001:
		return
	var target := atan2(-to_player.x, -to_player.z)
	_facing += wrapf(target - _facing, -PI, PI) * clampf(TURN_SPEED * delta, 0.0, 1.0)


func _brake(delta: float, rate := 18.0) -> void:
	velocity.x = move_toward(velocity.x, 0.0, rate * delta)
	velocity.z = move_toward(velocity.z, 0.0, rate * delta)


func _forward() -> Vector3:
	return -Vector3(sin(_facing), 0, cos(_facing))


# -------------------------------------------------------------------- damage

func take_hit(amount: float, from_direction: Vector3, heavy: bool) -> void:
	if state == State.DEAD:
		return
	health = maxf(0.0, health - amount)
	_stagger_accum += amount
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die(from_direction)
		return
	var can_heavy_stagger := heavy and (not is_boss or _stagger_accum >= _stagger_threshold * 0.55)
	if can_heavy_stagger or _stagger_accum >= _stagger_threshold or state == State.WINDUP:
		state = State.STAGGER
		_timer = 0.48 if not is_boss else 0.34
		_stagger_accum = 0.0
		_telegraph.visible = false
		_play_timed("Hit_A" if randi() % 2 == 0 else "Hit_B", _timer, 0.04)
		Sfx.play_3d("stagger", global_position + Vector3.UP, -1.0)
	velocity += from_direction.normalized() * (3.0 if is_boss else (5.0 if heavy else 2.2))


func _enrage() -> void:
	_enraged = true
	_move_speed *= 1.24
	_damage *= 1.22
	_recover_time *= 0.72
	if _aura_light != null:
		_aura_light.light_energy = 4.2
		_aura_light.light_color = Color(1.0, 0.03, 0.01)
	_play_timed("Taunt_Longer", 1.05, 0.08)
	state = State.STAGGER
	_timer = 1.05
	boss_phase_changed.emit(2)
	Sfx.play_3d("roar", global_position + Vector3.UP * 1.8, 3.0, 0.72)
	Juice.impact(0.48, Vector3.UP, 0.18, 0.09)


func _die(from_direction: Vector3) -> void:
	_dead = true
	state = State.DEAD
	remove_from_group("enemy")
	collision_layer = 0
	collision_mask = 1
	_telegraph.visible = false
	_play_timed("Death_C_Skeletons" if animation_player.has_animation("Death_C_Skeletons") else "Death_A",
			1.15 if not is_boss else 1.65, 0.05)
	Sfx.play_3d("death_draugr", global_position + Vector3.UP, 0.0, 0.78 if is_boss else 1.0)
	died.emit(self)
	var delay := 2.5 if is_boss else 1.5
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(model, "position:y", -2.2, 0.95).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
	velocity += from_direction.normalized() * (2.0 if is_boss else 3.8)


func is_dead() -> bool:
	return _dead


# ---------------------------------------------------------------- animation

func _play_animation(name: StringName, blend := 0.14, speed := 1.0) -> void:
	if animation_player == null or not animation_player.has_animation(name):
		push_warning("Enemy animation missing: %s" % name)
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
	_play_animation(name, blend, clip.length / maxf(duration, 0.05))


func _update_locomotion(delta: float) -> void:
	if state not in [State.PURSUE]:
		return
	var speed := Vector3(velocity.x, 0, velocity.z).length()
	if speed < 0.18:
		_play_animation("Idle_Combat", 0.16, 1.0)
		return
	var clip := "Running_C" if archetype == Archetype.ROGUE else \
			("Walking_D_Skeletons" if archetype == Archetype.MINION else "Running_A")
	_play_animation(clip, 0.16, clampf(speed / maxf(_move_speed * 0.78, 0.2), 0.68, 1.45))
	_step_phase += delta * speed * 1.4
	var side := sin(_step_phase) >= 0.0
	if side != _step_side and is_on_floor():
		_step_side = side
		Sfx.play_3d("step", global_position, -9.0, 0.84 if is_boss else 1.0)
