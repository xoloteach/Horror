class_name LeviathanAxe
extends Node3D
## Production Leviathan axe simulation + presentation.
##
## The gameplay root owns the authoritative five-state machine. The downloaded
## KayKit axe is only a visual child, rotated so this node keeps the original
## physics contract: +Y follows the haft, -Z is the cutting edge/travel axis and
## +X is the tumble axis. Because the gameplay node—not an enemy corpse—owns the
## axe, a lethal embed can never free the player's defining weapon.

enum State { EQUIPPED, AIRBORNE_THROW, EMBEDDED_WORLD, EMBEDDED_ENEMY, RECALLING }

signal state_changed(new_state: State)
signal caught
signal impacted(point: Vector3, enemy_hit: bool)

const MODEL := preload("res://assets/production/weapons/axe_1handed.gltf")
const TRAIL_TEXTURE := preload("res://assets/production/vfx/magic_03.png")

# KayKit model after 0.85 scale: the bit reaches roughly 0.50m from the root.
const VISUAL_SCALE := 0.85
const BLADE_REACH := 0.50
const EMBED_DEPTH := 0.13
const EDGE_LOCAL := Vector3(0.0, 0.64, -BLADE_REACH)

const THROW_SPEED := 33.0
const THROW_SPIN := 29.0
const GRAVITY := 10.0
const GRAVITY_DELAY := 0.38
const MAX_FLIGHT := 3.2
const THROW_DAMAGE := 46.0

const RECALL_SPEED := 28.0
const RECALL_MIN_TIME := 0.28
const RECALL_MAX_TIME := 0.74
const RECALL_SPIN := 42.0
const RECALL_DAMAGE := 30.0
const RECALL_HIT_RADIUS := 0.68
const ARC_RATIO := 0.30
const ARC_MIN := 0.90
const ARC_MAX := 3.60

# The visual is rotated -90 degrees around Y to map its -X bit to gameplay -Z.
# +90 here cancels that while held, restoring KayKit's authored hand pose.
const HOLD_ROT := Vector3(0.0, PI * 0.5, 0.0)
const HOLD_POS := Vector3.ZERO
const MASK_WORLD := 1
const MASK_ENEMY := 4

var state: State = State.EQUIPPED

var _player: Node3D
var _hand: Node3D
var _world_root: Node3D
var _visual: Node3D
var _trail: GPUParticles3D
var _glow: OmniLight3D

var _vel := Vector3.ZERO
var _travel := Vector3.FORWARD
var _spin := 0.0
var _flight_time := 0.0

var _p0 := Vector3.ZERO
var _recall_t := 0.0
var _recall_dur := 0.5
var _recall_hit: Array[Node] = []
var _last_pos := Vector3.ZERO

# Embedded enemies are followed with a weak reference and a local transform.
# The axe itself remains a child of the world root, so corpse deletion is safe.
var _anchor_ref: WeakRef
var _anchor_local := Transform3D.IDENTITY

var _rune_mats: Array[StandardMaterial3D] = []
var _rune_tween: Tween


func setup(player: Node3D, hand: Node3D, world_root: Node3D) -> void:
	_player = player
	_hand = hand
	_world_root = world_root

	_visual = MODEL.instantiate()
	_visual.name = "KayKitAxe"
	_visual.scale = Vector3.ONE * VISUAL_SCALE
	_visual.rotation.y = -PI * 0.5
	add_child(_visual)
	_tune_visual(_visual)
	_build_runes()
	_build_trail()
	_build_glow()
	_attach_to_hand()


func _tune_visual(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.get_surface_override_material_count():
			var source := mesh_node.get_active_material(surface)
			if source is StandardMaterial3D:
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color *= Color(0.72, 0.82, 0.98, 1.0)
				material.metallic = maxf(material.metallic, 0.62)
				material.roughness = 0.34
				mesh_node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_tune_visual(child)


func _build_runes() -> void:
	var rune_material := StandardMaterial3D.new()
	rune_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rune_material.albedo_color = Color(0.45, 0.88, 1.0, 1.0)
	rune_material.emission_enabled = true
	rune_material.emission = Color(0.25, 0.72, 1.0)
	rune_material.emission_energy_multiplier = 5.5
	_rune_mats.append(rune_material)

	# Three tiny inlaid strokes on each cheek of the blade. They are geometry,
	# not a decal, so the glyphs stay crisp in the WebGL build at any mip level.
	var strokes := [
		[Vector3(0.085, 0.68, -0.18), Vector3(0.018, 0.19, 0.016), 0.0],
		[Vector3(0.086, 0.72, -0.28), Vector3(0.018, 0.14, 0.016), 0.52],
		[Vector3(0.087, 0.58, -0.27), Vector3(0.018, 0.13, 0.016), -0.60],
	]
	for side in [-1.0, 1.0]:
		for stroke in strokes:
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.name = "Rune"
			var box := BoxMesh.new()
			box.size = stroke[1] as Vector3
			box.material = rune_material
			mesh_instance.mesh = box
			var position: Vector3 = stroke[0]
			position.x *= side
			mesh_instance.position = position
			mesh_instance.rotation.z = float(stroke[2])
			add_child(mesh_instance)


func _build_trail() -> void:
	_trail = GPUParticles3D.new()
	_trail.name = "FrostTrail"
	_trail.amount = 42
	_trail.lifetime = 0.34
	_trail.fixed_fps = 30
	_trail.local_coords = false
	_trail.randomness = 0.55
	_trail.visibility_aabb = AABB(Vector3(-12, -12, -12), Vector3(24, 24, 24))
	_trail.emitting = false

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.075
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.45
	process.gravity = Vector3(0, 0.25, 0)
	process.damping_min = 2.0
	process.damping_max = 5.0
	process.scale_min = 0.08
	process.scale_max = 0.19
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.70, 0.96, 1.0, 0.92))
	gradient.set_color(1, Color(0.18, 0.48, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	_trail.process_material = process

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = TRAIL_TEXTURE
	material.albedo_color = Color(0.60, 0.90, 1.0, 0.85)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	quad.material = material
	_trail.draw_pass_1 = quad
	add_child(_trail)


func _build_glow() -> void:
	_glow = OmniLight3D.new()
	_glow.name = "RuneLight"
	_glow.light_color = Color(0.28, 0.72, 1.0)
	_glow.light_energy = 0.18
	_glow.omni_range = 3.5
	_glow.omni_attenuation = 1.55
	_glow.shadow_enabled = false
	add_child(_glow)


func _set_state(next: State) -> void:
	state = next
	if _trail != null:
		_trail.emitting = next in [State.AIRBORNE_THROW, State.RECALLING]
	if _glow != null:
		_glow.light_energy = 1.45 if next in [State.AIRBORNE_THROW, State.RECALLING] else 0.18
	state_changed.emit(next)


func can_throw() -> bool:
	return state == State.EQUIPPED


func can_recall() -> bool:
	return state in [State.AIRBORNE_THROW, State.EMBEDDED_WORLD, State.EMBEDDED_ENEMY]


func is_held() -> bool:
	return state == State.EQUIPPED


func edge_world_position() -> Vector3:
	return global_transform * EDGE_LOCAL


func blade_center_world() -> Vector3:
	return global_transform * Vector3(0, 0.58, -0.26)


func _attach_to_hand() -> void:
	_anchor_ref = null
	if get_parent() != _hand:
		if get_parent() != null:
			reparent(_hand, false)
		else:
			_hand.add_child(self)
	transform = Transform3D(Basis.from_euler(HOLD_ROT), HOLD_POS)
	_set_state(State.EQUIPPED)


# ------------------------------------------------------------------------ throw

func throw(from: Vector3, target: Vector3) -> void:
	if not can_throw():
		return
	reparent(_world_root, true)
	global_position = from
	_travel = target - from
	if _travel.length_squared() < 0.01:
		_travel = -_hand.global_transform.basis.z
	_travel = _travel.normalized()
	_vel = _travel * THROW_SPEED
	_spin = 0.0
	_flight_time = 0.0
	_last_pos = global_position
	global_transform = Transform3D(_flight_basis(_travel, 0.0), global_position)
	_set_state(State.AIRBORNE_THROW)
	Sfx.play_3d("throw_release", from, 1.5)
	Juice.add_trauma(0.10, _travel)


func recall() -> void:
	if not can_recall():
		return
	_anchor_ref = null
	if get_parent() != _world_root:
		reparent(_world_root, true)
	_p0 = global_position
	_last_pos = _p0
	_recall_t = 0.0
	_recall_hit.clear()
	var gap := _p0.distance_to(_hand_point())
	_recall_dur = clampf(gap / RECALL_SPEED, RECALL_MIN_TIME, RECALL_MAX_TIME)
	_set_state(State.RECALLING)
	Sfx.play_3d("recall_whistle", _p0, 0.0)
	_pulse_runes()


func _hand_point() -> Vector3:
	if is_instance_valid(_hand):
		return _hand.global_position
	return _player.global_position + Vector3.UP * 1.15


func _bezier_points() -> Array[Vector3]:
	var p3 := _hand_point()
	var gap := _p0.distance_to(p3)
	var direction := p3 - _p0
	direction = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD
	var arc := clampf(gap * ARC_RATIO, ARC_MIN, ARC_MAX)
	var side := direction.cross(Vector3.UP).normalized()
	# A small lateral hook presents the recall as a designed curve from the
	# over-the-shoulder camera instead of an edge-on vertical parabola.
	var lateral := side * minf(1.25, gap * 0.10)
	var p1 := _p0 - direction * gap * 0.12 + Vector3.UP * arc + lateral
	var p2 := p3 - direction * gap * 0.30 + Vector3.UP * arc * 0.62 + lateral * 0.35
	return [_p0, p1, p2, p3]


static func _bezier(points: Array[Vector3], t: float) -> Vector3:
	var u := 1.0 - t
	return points[0] * (u * u * u) \
		+ points[1] * (3.0 * u * u * t) \
		+ points[2] * (3.0 * u * t * t) \
		+ points[3] * (t * t * t)


func _physics_process(delta: float) -> void:
	match state:
		State.AIRBORNE_THROW:
			_tick_flight(delta)
		State.EMBEDDED_ENEMY:
			_tick_embedded_enemy()
		State.RECALLING:
			_tick_recall(delta)
		_:
			pass


func _tick_flight(delta: float) -> void:
	_flight_time += delta
	if _flight_time > GRAVITY_DELAY:
		_vel.y -= GRAVITY * delta
	_travel = _vel.normalized()
	var from := global_position
	var to := from + _vel * delta
	var probe := to + _travel * BLADE_REACH
	var hit := _cast(from, probe)
	if not hit.is_empty():
		_resolve_hit(hit)
		return
	global_position = to
	_spin += THROW_SPIN * delta
	global_transform = Transform3D(_flight_basis(_travel, _spin), to)
	if _flight_time > MAX_FLIGHT:
		_land_after_miss()


func _tick_embedded_enemy() -> void:
	if _anchor_ref == null:
		_set_state(State.EMBEDDED_WORLD)
		return
	var anchor := _anchor_ref.get_ref() as Node3D
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		_anchor_ref = null
		_set_state(State.EMBEDDED_WORLD)
		return
	global_transform = anchor.global_transform * _anchor_local


func _tick_recall(delta: float) -> void:
	_recall_t = minf(1.0, _recall_t + delta / _recall_dur)
	var eased: float = pow(_recall_t, 1.48)
	var points := _bezier_points()
	var position := _bezier(points, eased)
	_sweep_damage(_last_pos, position)
	var tangent := position - _last_pos
	if tangent.length_squared() > 0.000001:
		_travel = tangent.normalized()
	_last_pos = position
	_spin += RECALL_SPIN * delta
	global_transform = Transform3D(_flight_basis(_travel, _spin), position)
	if _recall_t >= 1.0:
		_catch()


func _sweep_damage(from: Vector3, to: Vector3) -> void:
	for candidate in get_tree().get_nodes_in_group("enemy"):
		var enemy := candidate as Node3D
		if enemy == null or enemy in _recall_hit or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_hit"):
			continue
		var target := enemy.global_position + Vector3.UP * 0.95
		if enemy.has_method("hit_point"):
			target = enemy.hit_point()
		if segment_distance(from, to, target) > RECALL_HIT_RADIUS:
			continue
		_recall_hit.append(enemy)
		var normal := (target - from).normalized()
		enemy.take_hit(RECALL_DAMAGE, normal, false)
		Fx.blood(_world_root, target, -normal, 0.9)
		Sfx.play_3d("flesh", target, 1.0)
		Juice.impact(0.26, normal, 0.10, 0.05)


static func segment_distance(from: Vector3, to: Vector3, point: Vector3) -> float:
	var segment := to - from
	var length_squared := segment.length_squared()
	if length_squared < 0.000001:
		return from.distance_to(point)
	var t := clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
	return (from + segment * t).distance_to(point)


func _catch() -> void:
	_attach_to_hand()
	Sfx.play_2d("catch_metal", 2.0)
	Fx.rune_flash(_world_root, _hand_point())
	Juice.impact(0.32, -_travel, 0.14, 0.085)
	caught.emit()


# ------------------------------------------------------------------- collision

func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = MASK_WORLD | MASK_ENEMY
	query.collide_with_areas = false
	if is_instance_valid(_player) and _player is CollisionObject3D:
		query.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func _resolve_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	if collider != null and collider.has_method("take_hit"):
		_embed_in_enemy(collider, point, normal)
	else:
		_embed_in_world(point, normal, collider)


func _embed_in_world(point: Vector3, normal: Vector3, collider: Object) -> void:
	var basis := _embed_basis(normal, _travel)
	basis = basis.rotated(basis.z, randf_range(-0.16, 0.16))
	global_transform = Transform3D(basis, point + normal * (BLADE_REACH - EMBED_DEPTH))
	_set_state(State.EMBEDDED_WORLD)
	var surface := "stone"
	if collider != null and collider.has_meta("surface_kind"):
		surface = str(collider.get_meta("surface_kind"))
	Sfx.play_3d("embed_wood" if surface == "wood" else "embed_stone", point, 2.0)
	Fx.sparks(_world_root, point, normal)
	Fx.dust(_world_root, point, normal)
	Juice.impact(0.36, -normal, 0.08, 0.055)
	impacted.emit(point, false)


func _embed_in_enemy(enemy: Object, point: Vector3, normal: Vector3) -> void:
	# Resolve damage first, then obtain the still-valid death/stagger anchor.
	enemy.take_hit(THROW_DAMAGE, -normal, true)
	var anchor := enemy as Node3D
	if enemy.has_method("embed_anchor"):
		var candidate: Variant = enemy.embed_anchor()
		if candidate is Node3D:
			anchor = candidate as Node3D
	var basis := _embed_basis(normal, _travel)
	basis = basis.rotated(basis.z, randf_range(-0.14, 0.14))
	global_transform = Transform3D(basis, point + normal * (BLADE_REACH - EMBED_DEPTH * 1.55))
	if is_instance_valid(anchor):
		_anchor_ref = weakref(anchor)
		_anchor_local = anchor.global_transform.affine_inverse() * global_transform
		_set_state(State.EMBEDDED_ENEMY)
	else:
		_set_state(State.EMBEDDED_WORLD)
	Sfx.play_3d("flesh", point, 2.0)
	Fx.blood(_world_root, point, normal, 1.35)
	Juice.impact(0.58, -normal, 0.05, 0.085)
	impacted.emit(point, true)


func _land_after_miss() -> void:
	var from := global_position
	var to := from + Vector3.DOWN * 40.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = MASK_WORLD
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_embed_in_world(hit["position"], hit["normal"], hit["collider"])
	else:
		global_transform = Transform3D(_embed_basis(Vector3.UP, _travel), global_position)
		_set_state(State.EMBEDDED_WORLD)


# ---------------------------------------------------------------- orientation

static func _flight_basis(travel: Vector3, spin: float) -> Basis:
	var direction := travel.normalized()
	var x := direction.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := -direction
	var y := z.cross(x).normalized()
	return Basis(x, y, z) * Basis.from_euler(Vector3(spin, 0.0, 0.0))


static func _embed_basis(normal: Vector3, travel: Vector3) -> Basis:
	var z := normal.normalized()
	var y := Vector3.UP - z * Vector3.UP.dot(z)
	if y.length_squared() < 0.02:
		y = -(travel - z * travel.dot(z))
	if y.length_squared() < 0.02:
		y = Vector3.FORWARD
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


func _pulse_runes() -> void:
	if _rune_mats.is_empty():
		return
	if _rune_tween != null and _rune_tween.is_valid():
		_rune_tween.kill()
	_rune_tween = create_tween()
	_rune_tween.set_parallel(true)
	for material in _rune_mats:
		_rune_tween.tween_property(material, "emission_energy_multiplier", 15.0, 0.10)
	_rune_tween.chain()
	for material in _rune_mats:
		_rune_tween.tween_property(material, "emission_energy_multiplier", 5.5, 0.38)
