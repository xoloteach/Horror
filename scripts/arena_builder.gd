# ArenaBuilder: constructs the frozen ruined arena. Returns {"spawn_points": [...]}.
class_name ArenaBuilder
extends RefCounted

const ARENA_HALF := 21.0


static func build(parent: Node3D) -> Dictionary:
	_build_environment(parent)
	_build_ground(parent)
	_build_walls(parent)
	_build_pillars(parent)
	_build_slabs(parent)
	_build_rune_stones(parent)
	_build_snow(parent)
	return {"spawn_points": _spawn_points()}


static func _build_environment(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.055, 0.095)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.48, 0.62)
	env.ambient_light_energy = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.55, 0.7)
	env.fog_density = 0.02
	env.fog_sky_affect = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "MoonLight"
	sun.light_color = Color(0.72, 0.8, 1.0)
	sun.light_energy = 1.15
	sun.rotation = Vector3(-0.9, -0.5, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	parent.add_child(sun)


static func _build_ground(parent: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.add_to_group("earth")
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ARENA_HALF * 2.0 + 2.0, ARENA_HALF * 2.0 + 2.0)
	pm.material = MeshFactory.earth_mat()
	mi.mesh = pm
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(ARENA_HALF * 2.0 + 2.0, 1.0, ARENA_HALF * 2.0 + 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.51, 0)
	body.add_child(col)
	parent.add_child(body)


static func _build_walls(parent: Node3D) -> void:
	var length := ARENA_HALF * 2.0 + 2.0
	var h := 5.0
	var specs := [
		[Vector3(0, 0, -ARENA_HALF - 0.8), 0.0],
		[Vector3(0, 0, ARENA_HALF + 0.8), PI],
		[Vector3(-ARENA_HALF - 0.8, 0, 0), PI * 0.5],
		[Vector3(ARENA_HALF + 0.8, 0, 0), -PI * 0.5],
	]
	for s in specs:
		var wall := MeshFactory.create_wall(length, h)
		wall.position = s[0]
		wall.rotation.y = s[1]
		parent.add_child(wall)


static func _build_pillars(parent: Node3D) -> void:
	for i in 8:
		var ang := TAU * i / 8.0 + randf_range(-0.2, 0.2)
		var r := randf_range(10.5, 15.5)
		var pillar := MeshFactory.create_pillar(randf_range(3.0, 5.5), randf() < 0.45)
		pillar.position = Vector3(cos(ang) * r, 0, sin(ang) * r)
		pillar.rotation.y = randf() * TAU
		parent.add_child(pillar)


static func _build_slabs(parent: Node3D) -> void:
	for i in 10:
		var ang := randf() * TAU
		var r := randf_range(4.0, 17.0)
		var slab := MeshFactory.create_slab()
		slab.position = Vector3(cos(ang) * r, 0.05, sin(ang) * r)
		parent.add_child(slab)


static func _build_rune_stones(parent: Node3D) -> void:
	# Glowing rune decals mounted on three monoliths near the arena edge.
	for i in 3:
		var ang := TAU * i / 3.0 + 0.5
		var r := 18.5
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		var mono := MeshFactory.create_pillar(3.2, false)
		mono.position = pos
		parent.add_child(mono)
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.3, 1.3)
		qm.material = MeshFactory.rune_mat()
		quad.mesh = qm
		parent.add_child(quad)
		quad.position = pos + Vector3(0, 1.7, 0)
		# face away from arena center
		var outward := (pos - Vector3.ZERO).normalized()
		quad.position += outward * 0.62
		quad.look_at(quad.position + outward, Vector3.UP)


static func _build_snow(parent: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "Snow"
	p.amount = 220
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.visibility_aabb = AABB(Vector3(-24, -10, -24), Vector3(48, 24, 48))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, -0.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.9, 0.93, 1.0, 0.85)
	quad.material = m
	p.draw_pass_1 = quad
	p.position = Vector3(0, 9, 0)
	parent.add_child(p)


static func _spawn_points() -> Array:
	var pts: Array = []
	for i in 8:
		var ang := TAU * i / 8.0
		pts.append(Vector3(cos(ang) * 17.0, 0.0, sin(ang) * 17.0))
	return pts
