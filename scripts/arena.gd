class_name Arena
extends Node3D
## Authored frozen-keep composition built from curated KayKit/Kenney CC0 modules.
##
## The old circular ring repeated one wall twenty times. This keep has a readable
## north gate, four towers, damaged wall rhythm, a central fighting court,
## graveyard flank, crypt silhouette, tree/rock depth layers, animated fire,
## blowing snow and collision-aware spawn markers.

const HALF_EXTENT := 16.0
const FLOOR_TILE := 4.0
const DUNGEON := "res://assets/production/environment/dungeon/"
const CASTLE := "res://assets/production/environment/castle/"
const GRAVE := "res://assets/production/environment/graveyard/"
const NATURE := "res://assets/production/environment/nature/"
const FLAME_TEXTURE := preload("res://assets/production/vfx/flame_05.png")
const SMOKE_TEXTURE := preload("res://assets/production/vfx/smoke_07.png")
const SNOW_TEXTURE := preload("res://assets/production/vfx/circle_03.png")

var _scene_cache := {}
var _fire_lights: Array[OmniLight3D] = []
var _fire_energy: Array[float] = []
var _noise := FastNoiseLite.new()
var _time := 0.0
var _spawn_markers: Array[Vector3] = []


func _ready() -> void:
	_noise.seed = 0xF2057
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.6
	_build_environment()
	_build_ground()
	_build_courtyard()
	_build_keep_walls()
	_build_landmarks()
	_build_graveyard_flank()
	_build_natural_silhouette()
	_build_fire()
	_build_snow()
	_build_spawn_markers()


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "FrozenNight"
	var environment := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.012, 0.020, 0.055)
	sky_material.sky_horizon_color = Color(0.105, 0.145, 0.235)
	sky_material.ground_bottom_color = Color(0.008, 0.011, 0.018)
	sky_material.ground_horizon_color = Color(0.060, 0.075, 0.105)
	sky_material.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.72
	environment.ambient_light_energy = 0.48
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.94
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.09, 0.13, 0.21)
	environment.fog_light_energy = 0.72
	environment.fog_density = 0.012
	environment.fog_height = 0.0
	environment.fog_height_density = 0.08
	environment.fog_sky_affect = 0.46
	world.environment = environment
	add_child(world)

	var moon := DirectionalLight3D.new()
	moon.name = "MoonKey"
	moon.rotation_degrees = Vector3(-52, -38, 0)
	moon.light_color = Color(0.51, 0.66, 1.0)
	moon.light_energy = 0.88
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 48.0
	moon.directional_shadow_fade_start = 0.72
	add_child(moon)

	var warm_rim := DirectionalLight3D.new()
	warm_rim.name = "DawnRim"
	warm_rim.rotation_degrees = Vector3(-18, 142, 0)
	warm_rim.light_color = Color(1.0, 0.48, 0.24)
	warm_rim.light_energy = 0.18
	warm_rim.shadow_enabled = false
	add_child(warm_rim)

	# Oversized moon disc gives the north gate a memorable silhouette without an HDRI.
	var moon_disc := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.8
	sphere.height = 5.6
	sphere.radial_segments = 24
	sphere.rings = 12
	var moon_material := StandardMaterial3D.new()
	moon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_material.albedo_color = Color(0.50, 0.68, 0.96)
	moon_material.emission_enabled = true
	moon_material.emission = Color(0.36, 0.56, 0.96)
	moon_material.emission_energy_multiplier = 1.8
	sphere.material = moon_material
	moon_disc.mesh = sphere
	moon_disc.position = Vector3(-16, 20, -52)
	add_child(moon_disc)


func _snow_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/textures/frost_albedo.jpg")
	material.normal_enabled = true
	material.normal_texture = load("res://assets/textures/frost_normal.jpg")
	material.normal_scale = 0.38
	material.roughness_texture = load("res://assets/textures/frost_rough.jpg")
	material.roughness = 0.92
	material.albedo_color = Color(0.58, 0.67, 0.82)
	material.uv1_scale = Vector3(10, 10, 1)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "SnowGround"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface_kind", "snow")
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1.0, 80)
	collision.shape = box
	collision.position.y = -0.52
	body.add_child(collision)
	var visual := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	visual.mesh = plane
	visual.material_override = _snow_material()
	body.add_child(visual)
	add_child(body)


# ---------------------------------------------------------------- composition

func _build_courtyard() -> void:
	var variants := [
		"floor_tile_large.gltf.glb", "floor_tile_large.gltf.glb",
		"floor_tile_large_rocks.gltf.glb", "floor_tile_small_broken_A.gltf.glb",
		"floor_tile_small_broken_B.gltf.glb",
	]
	for x in range(-3, 4):
		for z in range(-3, 4):
			var edge: int = maxi(abs(x), abs(z))
			var index: int = abs(x * 13 + z * 7 + x * z) % variants.size()
			var file: String = variants[index]
			if edge < 2:
				file = "floor_tile_large.gltf.glb"
			_model(DUNGEON + file, Vector3(x * FLOOR_TILE, 0.02, z * FLOOR_TILE),
					0.0 if (x + z) % 2 == 0 else PI * 0.5)

	# Raised rune dais focuses the play space and catches moon/fire highlights.
	for x in [-8.5, 8.5]:
		for z in [-8.5, 8.5]:
			_model(DUNGEON + "pillar_decorated.gltf.glb", Vector3(x, 0.05, z), 0, Vector3.ONE * 1.18)


func _build_keep_walls() -> void:
	var north_pattern := ["wall.gltf.glb", "wall_cracked.gltf.glb", "wall_doorway.glb",
			"wall_doorway.glb", "wall_broken.gltf.glb", "wall.gltf.glb", "wall_cracked.gltf.glb"]
	var side_pattern := ["wall_broken.gltf.glb", "wall.gltf.glb", "wall_cracked.gltf.glb",
			"wall_archedwindow_open.gltf.glb", "wall.gltf.glb", "wall_broken.gltf.glb", "wall.gltf.glb"]
	for i in 7:
		var offset := (i - 3) * 4.0
		var north_file: String = north_pattern[i]
		var south_file: String = side_pattern[6 - i]
		_static_model(DUNGEON + north_file, Vector3(offset, 0, -HALF_EXTENT),
				0, Vector3.ONE, Vector3(4, 4, 1), "stone", "NorthWall")
		_static_model(DUNGEON + south_file, Vector3(offset, 0, HALF_EXTENT),
				PI, Vector3.ONE, Vector3(4, 4, 1), "stone", "SouthWall")

	for i in 7:
		var offset := (i - 3) * 4.0
		var east_file: String = side_pattern[i]
		var west_file: String = side_pattern[6 - i]
		_static_model(DUNGEON + east_file, Vector3(HALF_EXTENT, 0, offset),
				PI * 0.5, Vector3.ONE, Vector3(4, 4, 1), "stone", "EastWall")
		_static_model(DUNGEON + west_file, Vector3(-HALF_EXTENT, 0, offset),
				-PI * 0.5, Vector3.ONE, Vector3(4, 4, 1), "stone", "WestWall")

	# Four stacked castle towers break the flat wall horizon.
	for corner in [Vector3(-16, 0, -16), Vector3(16, 0, -16),
			Vector3(-16, 0, 16), Vector3(16, 0, 16)]:
		for level in 3:
			_model(CASTLE + ("tower-base.glb" if level == 0 else "tower-square-mid-windows.glb"),
					corner + Vector3.UP * level * 3.8, 0, Vector3.ONE * 3.0)
		_model(CASTLE + "tower-top.glb", corner + Vector3.UP * 11.4, 0, Vector3.ONE * 3.0)
		_static_box("TowerCollision", corner + Vector3.UP * 5.2,
				Vector3(3.4, 10.4, 3.4), 0, "stone")

	# The north portal is layered over the two doorway modules.
	_model(CASTLE + "gate.glb", Vector3(0, 0.05, -15.45), PI * 0.5, Vector3.ONE * 5.4)
	_model(DUNGEON + "banner_triple_red.gltf.glb", Vector3(0, 4.25, -15.35), PI)


func _build_landmarks() -> void:
	# Broken oath altar and trophy weapons define the west side.
	_static_model(GRAVE + "altar-stone.glb", Vector3(-9.5, 0, -6.8), 0.25,
			Vector3.ONE * 2.1, Vector3(2.2, 1.1, 1.7), "stone", "OathAltar")
	_model(DUNGEON + "sword_shield_broken.gltf.glb", Vector3(-9.5, 1.18, -6.8), -0.4, Vector3.ONE * 1.7)
	_model(DUNGEON + "rubble_large.gltf.glb", Vector3(-7.7, 0.04, -8.1), 1.2)
	_model(DUNGEON + "rubble_half.gltf.glb", Vector3(-11.0, 0.04, -5.0), -0.8)

	# East crypt cluster gives the mage side a tall, asymmetric backdrop.
	_static_model(GRAVE + "crypt-large.glb", Vector3(10.7, 0, -7.8), -0.28,
			Vector3.ONE * 2.25, Vector3(4.4, 2.3, 5.4), "stone", "JarlCrypt")
	_model(GRAVE + "pillar-obelisk.glb", Vector3(7.8, 0, -9.0), 0.1, Vector3.ONE * 2.4)
	_model(GRAVE + "coffin-old.glb", Vector3(10.0, 0.1, -4.4), -0.6, Vector3.ONE * 1.4)

	# Damaged siege silhouettes beyond the southern wall sell a larger conflict.
	_model(CASTLE + "siege-ballista-demolished.glb", Vector3(-9, 0, 20), 0.4, Vector3.ONE * 3.0)
	_model(CASTLE + "siege-catapult-demolished.glb", Vector3(8, 0, 22), -0.5, Vector3.ONE * 3.2)


func _build_graveyard_flank() -> void:
	var stones := ["gravestone-bevel.glb", "gravestone-broken.glb",
			"gravestone-decorative.glb", "gravestone-round.glb"]
	for i in 14:
		var row := i / 7
		var col := i % 7
		var position := Vector3(-13.0 + col * 1.65, 0.02, 8.0 + row * 2.25)
		position.x += sin(float(i) * 2.1) * 0.32
		_model(GRAVE + stones[i % stones.size()], position,
				-0.22 + sin(float(i)) * 0.20, Vector3.ONE * 1.15)
	for i in 5:
		_model(GRAVE + "gravestone-debris.glb", Vector3(-12 + i * 2.3, 0.02, 12.7),
				float(i) * 0.6, Vector3.ONE * 1.1)


func _build_natural_silhouette() -> void:
	var tree_files := ["tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb"]
	for i in 18:
		var angle := float(i) / 18.0 * TAU + 0.12
		var radius := 25.0 + float(i % 4) * 2.1
		var scale := 3.8 + float((i * 7) % 5) * 0.34
		_model(NATURE + tree_files[i % tree_files.size()],
				Vector3(cos(angle) * radius, -0.1, sin(angle) * radius),
				-angle + 0.4, Vector3.ONE * scale)
	for i in 14:
		var angle := float(i) / 14.0 * TAU + 0.3
		var radius := 20.5 + float(i % 3) * 1.4
		_model(NATURE + ("rock_largeA.glb" if i % 2 == 0 else "rock_largeC.glb"),
				Vector3(cos(angle) * radius, -0.08, sin(angle) * radius),
				angle, Vector3.ONE * (3.4 + (i % 4) * 0.4))


# ---------------------------------------------------------------- fire / snow

func _build_fire() -> void:
	var positions := [
		Vector3(-6.8, 0, -10.8), Vector3(6.8, 0, -10.8),
		Vector3(-11.8, 0, 2.0), Vector3(11.8, 0, 2.0),
		Vector3(-6.8, 0, 11.0), Vector3(6.8, 0, 11.0),
	]
	for i in positions.size():
		var holder := Node3D.new()
		holder.name = "Brazier_%02d" % i
		holder.position = positions[i]
		add_child(holder)
		var basket := _model(GRAVE + "fire-basket.glb", Vector3.ZERO, 0, Vector3.ONE * 1.35, holder)
		_static_box("BrazierCollision", positions[i] + Vector3.UP * 0.45,
				Vector3(0.9, 0.9, 0.9), 0, "metal")
		_build_flame_emitter(holder)
		var light := OmniLight3D.new()
		light.position.y = 1.2
		light.light_color = Color(1.0, 0.39, 0.12)
		light.light_energy = 2.25
		light.omni_range = 9.5
		light.omni_attenuation = 1.55
		light.shadow_enabled = false
		holder.add_child(light)
		_fire_lights.append(light)
		_fire_energy.append(light.light_energy)

	# Wall torches are emissive landmarks; only every second receives a light.
	for x in [-12.0, -8.0, 8.0, 12.0]:
		_model(DUNGEON + "torch_mounted.gltf.glb", Vector3(x, 2.15, -15.35), PI)
		_model(DUNGEON + "torch_mounted.gltf.glb", Vector3(x, 2.15, 15.35), 0)


func _build_flame_emitter(holder: Node3D) -> void:
	var particles := GPUParticles3D.new()
	particles.position.y = 1.0
	particles.amount = 22
	particles.lifetime = 0.72
	particles.fixed_fps = 30
	particles.randomness = 0.55
	particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 3, 2))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.16
	process.direction = Vector3.UP
	process.spread = 24.0
	process.initial_velocity_min = 0.65
	process.initial_velocity_max = 1.7
	process.gravity = Vector3(0, 0.35, 0)
	process.scale_min = 0.22
	process.scale_max = 0.52
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.82, 0.30, 0.95))
	gradient.set_color(0.45, Color(1.0, 0.18, 0.025, 0.82))
	gradient.set_color(1, Color(0.18, 0.04, 0.02, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	particles.draw_pass_1 = _particle_quad(FLAME_TEXTURE, Vector2(0.52, 0.72), true)
	holder.add_child(particles)

	var smoke := GPUParticles3D.new()
	smoke.position.y = 1.35
	smoke.amount = 8
	smoke.lifetime = 2.8
	smoke.fixed_fps = 20
	smoke.randomness = 0.7
	smoke.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 7, 4))
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_process.emission_sphere_radius = 0.18
	smoke_process.direction = Vector3(0.28, 1, 0.1)
	smoke_process.spread = 18.0
	smoke_process.initial_velocity_min = 0.35
	smoke_process.initial_velocity_max = 0.8
	smoke_process.gravity = Vector3(0.12, 0.25, 0.04)
	smoke_process.scale_min = 0.35
	smoke_process.scale_max = 0.9
	var smoke_gradient := Gradient.new()
	smoke_gradient.set_color(0, Color(0.16, 0.18, 0.22, 0.28))
	smoke_gradient.set_color(1, Color(0.08, 0.10, 0.15, 0.0))
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke_gradient
	smoke_process.color_ramp = smoke_ramp
	smoke.process_material = smoke_process
	smoke.draw_pass_1 = _particle_quad(SMOKE_TEXTURE, Vector2(0.75, 0.75), false)
	holder.add_child(smoke)


func _particle_quad(texture: Texture2D, size: Vector2, additive: bool) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material
	return quad


func _build_snow() -> void:
	var snow := GPUParticles3D.new()
	snow.name = "BlowingSnow"
	snow.position = Vector3(0, 7, 0)
	snow.amount = 260
	snow.lifetime = 8.0
	snow.preprocess = 8.0
	snow.fixed_fps = 20
	snow.randomness = 0.85
	snow.visibility_aabb = AABB(Vector3(-24, -10, -24), Vector3(48, 22, 48))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(22, 6, 22)
	process.direction = Vector3(0.34, -1.0, 0.16)
	process.spread = 16.0
	process.initial_velocity_min = 0.65
	process.initial_velocity_max = 1.6
	process.gravity = Vector3(0.22, -0.55, 0.08)
	process.scale_min = 0.018
	process.scale_max = 0.065
	process.color = Color(0.82, 0.90, 1.0, 0.62)
	snow.process_material = process
	snow.draw_pass_1 = _particle_quad(SNOW_TEXTURE, Vector2(0.07, 0.07), false)
	add_child(snow)


# -------------------------------------------------------------------- helpers

func _model(path: String, position: Vector3, yaw := 0.0,
		scale := Vector3.ONE, parent: Node = self) -> Node3D:
	var packed: PackedScene
	if _scene_cache.has(path):
		packed = _scene_cache[path]
	else:
		packed = load(path)
		_scene_cache[path] = packed
	var instance: Node3D = packed.instantiate()
	instance.position = position
	instance.rotation.y = yaw
	instance.scale = scale
	parent.add_child(instance)
	return instance


func _static_model(path: String, position: Vector3, yaw: float,
		scale: Vector3, collision_size: Vector3, surface: String,
		body_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = position
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface_kind", surface)
	add_child(body)
	_model(path, Vector3.ZERO, 0, scale, body)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision_size
	collision.shape = box
	collision.position.y = collision_size.y * 0.5
	body.add_child(collision)
	return body


func _static_box(body_name: String, position: Vector3, size: Vector3,
		yaw: float, surface: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = position
	body.rotation.y = yaw
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface_kind", surface)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	add_child(body)
	return body


func _build_spawn_markers() -> void:
	_spawn_markers = [
		Vector3(-12.5, 0.1, -11.0), Vector3(12.5, 0.1, -11.0),
		Vector3(-12.5, 0.1, 11.0), Vector3(12.5, 0.1, 11.0),
		Vector3(-14.0, 0.1, -3.5), Vector3(14.0, 0.1, -3.5),
		Vector3(-14.0, 0.1, 5.0), Vector3(14.0, 0.1, 5.0),
		Vector3(-6.0, 0.1, -13.0), Vector3(6.0, 0.1, -13.0),
		Vector3(-6.0, 0.1, 13.0), Vector3(6.0, 0.1, 13.0),
	]


func spawn_points(count: int, avoid: Vector3, min_distance := 8.0) -> Array[Vector3]:
	var candidates := _spawn_markers.duplicate()
	# Farthest-first provides readable entrances and prevents a spawn behind the
	# camera/player at point-blank range.
	candidates.sort_custom(func(a: Vector3, b: Vector3):
		return a.distance_squared_to(avoid) > b.distance_squared_to(avoid))
	var result: Array[Vector3] = []
	for point in candidates:
		if result.size() >= count:
			break
		if point.distance_to(avoid) < min_distance or not _spawn_clear(point):
			continue
		var separated := true
		for selected in result:
			if point.distance_to(selected) < 2.4:
				separated = false
				break
		if separated:
			result.append(point)
	while result.size() < count:
		var angle := float(result.size()) / maxf(1.0, float(count)) * TAU
		result.append(Vector3(cos(angle) * 12.5, 0.1, sin(angle) * 12.5))
	return result


func _spawn_clear(point: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.75)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _process(delta: float) -> void:
	_time += delta
	for i in _fire_lights.size():
		var flicker := _noise.get_noise_2d(_time * 3.2, float(i) * 9.7)
		_fire_lights[i].light_energy = _fire_energy[i] * (1.0 + flicker * 0.24)
