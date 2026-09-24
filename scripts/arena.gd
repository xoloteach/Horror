class_name Arena
extends Node3D
## Builds the ruined Nordic arena: floor, perimeter wall ring, pillars, braziers,
## lighting and atmosphere. Collision is authored here (the GLBs carry none) using
## primitive shapes, which is both cheaper and more reliable than trimesh bodies.

const RADIUS := 20.0
const WALL_SEGMENTS := 20
const WALL_W := 4.33
const WALL_H := 2.48
const WALL_D := 0.75

const PILLAR_RING := 14.0
const PILLAR_COUNT := 10
const PILLAR_R := 0.46
const PILLAR_H := 3.85

const BRAZIER_RING := 10.5
const BRAZIER_COUNT := 6

var _lights: Array[OmniLight3D] = []
var _base_energy: Array[float] = []
var _noise: FastNoiseLite
var _t := 0.0


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 1.6
	_build_environment()
	_build_floor()
	_build_walls()
	_build_pillars()
	_build_braziers()


# ------------------------------------------------------------------- materials

static func _tex(name: String) -> Texture2D:
	var path := "res://assets/textures/%s.jpg" % name
	if ResourceLoader.exists(path):
		return load(path)
	return null


## PBR material from the CC0 ambientCG sets, tiled by `uv`.
static func pbr(base: String, uv: float, tint := Color.WHITE,
		rough_mult := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(base + "_albedo")
	m.normal_texture = _tex(base + "_normal")
	if m.normal_texture != null:
		m.normal_enabled = true
		m.normal_scale = 1.0
	m.roughness_texture = _tex(base + "_rough")
	var metal := _tex(base + "_metal")
	if metal != null:
		m.metallic_texture = metal
		m.metallic = 1.0
	m.albedo_color = tint
	m.roughness = clampf(rough_mult, 0.0, 1.0)
	m.uv1_scale = Vector3(uv, uv, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


static func _apply(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_apply(c, mat)


# ----------------------------------------------------------------- environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.045, 0.062, 0.115)
	sky_mat.sky_horizon_color = Color(0.105, 0.125, 0.170)
	sky_mat.ground_bottom_color = Color(0.030, 0.034, 0.042)
	sky_mat.ground_horizon_color = Color(0.085, 0.095, 0.120)
	sky_mat.sun_angle_max = 24.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.ambient_light_energy = 0.75

	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.13, 0.19)
	env.fog_light_energy = 0.8
	env.fog_density = 0.018
	env.fog_sky_affect = 0.35

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05

	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.64, 0.74, 0.98)
	sun.light_energy = 0.70
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	add_child(sun)

	# cold bounce from the opposite side so silhouettes never go fully black
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.30, 0.38, 0.58)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-24.0, -150.0, 0.0)
	add_child(fill)


# ----------------------------------------------------------------------- floor

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(RADIUS * 3.0, 1.0, RADIUS * 3.0)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(RADIUS * 3.0, RADIUS * 3.0)
	pm.subdivide_width = 2
	pm.subdivide_depth = 2
	plane.mesh = pm
	plane.material_override = pbr("frost", 15.0, Color(0.70, 0.76, 0.88), 0.86)
	body.add_child(plane)

	# central flagstone platform: 3x3 cracked slabs
	var slab_res: PackedScene = load("res://assets/models/slab.glb")
	var slab_mat := pbr("stone", 2.2, Color(0.86, 0.88, 0.94), 0.88)
	for gx in 3:
		for gz in 3:
			var s: Node3D = slab_res.instantiate()
			s.position = Vector3((gx - 1) * 3.0, 0.02, (gz - 1) * 3.0)
			s.rotation.y = randf_range(-0.03, 0.03)
			_apply(s, slab_mat)
			add_child(s)

	# frozen earth patches further out for material variety
	var earth_mat := pbr("earth", 3.0, Color(0.52, 0.53, 0.56), 0.92)
	for i in 10:
		var a := randf() * TAU
		var r := randf_range(7.0, 17.0)
		var patch := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(randf_range(3.0, 6.5), randf_range(3.0, 6.5))
		patch.mesh = q
		patch.material_override = earth_mat
		patch.position = Vector3(cos(a) * r, 0.012, sin(a) * r)
		patch.rotation.y = randf() * TAU
		add_child(patch)


# ----------------------------------------------------------------------- walls

func _build_walls() -> void:
	var res: PackedScene = load("res://assets/models/wall.glb")
	var mat := pbr("stone", 3.0, Color(0.74, 0.78, 0.86), 0.90)
	# scale each segment so the ring closes without gaps
	var circumference := TAU * RADIUS
	var scale_x: float = (circumference / float(WALL_SEGMENTS)) / WALL_W

	for i in WALL_SEGMENTS:
		var a := float(i) / float(WALL_SEGMENTS) * TAU
		var pos := Vector3(cos(a) * RADIUS, 0.0, sin(a) * RADIUS)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pos
		# face the ring centre
		body.rotation.y = -a + PI * 0.5
		add_child(body)

		var vis: Node3D = res.instantiate()
		vis.scale = Vector3(scale_x, 1.0, 1.0)
		_apply(vis, mat)
		body.add_child(vis)

		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_W * scale_x, WALL_H, WALL_D)
		cs.shape = box
		cs.position = Vector3(0, WALL_H * 0.5, 0)
		body.add_child(cs)


# --------------------------------------------------------------------- pillars

func _build_pillars() -> void:
	var whole: PackedScene = load("res://assets/models/pillar.glb")
	var broken: PackedScene = load("res://assets/models/pillar_broken.glb")
	var mat := pbr("stone", 2.4, Color(0.82, 0.85, 0.92), 0.88)

	for i in PILLAR_COUNT:
		var a := float(i) / float(PILLAR_COUNT) * TAU + 0.14
		var is_broken := (i % 3) == 2
		var h := 1.99 if is_broken else PILLAR_H
		var pos := Vector3(cos(a) * PILLAR_RING, 0.0, sin(a) * PILLAR_RING)

		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pos
		body.rotation.y = randf() * TAU
		add_child(body)

		var vis: Node3D = (broken if is_broken else whole).instantiate()
		_apply(vis, mat)
		body.add_child(vis)

		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = PILLAR_R
		cyl.height = h
		cs.shape = cyl
		cs.position = Vector3(0, h * 0.5, 0)
		body.add_child(cs)


# -------------------------------------------------------------------- braziers

func _build_braziers() -> void:
	var res: PackedScene = load("res://assets/models/brazier.glb")
	var mat := pbr("iron", 1.6, Color(0.42, 0.40, 0.40), 0.55)

	for i in BRAZIER_COUNT:
		var a := float(i) / float(BRAZIER_COUNT) * TAU + 0.5
		var pos := Vector3(cos(a) * BRAZIER_RING, 0.0, sin(a) * BRAZIER_RING)

		var holder := Node3D.new()
		holder.position = pos
		add_child(holder)

		var vis: Node3D = res.instantiate()
		# keep the emissive coals: only retexture the iron body
		var body_node: Node = vis.find_child("Brazier", true, false)
		if body_node != null:
			_apply(body_node, mat)
		holder.add_child(vis)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.63, 0.30)
		light.light_energy = 2.6
		light.omni_range = 13.0
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.position = Vector3(0, 0.95, 0)
		holder.add_child(light)
		_lights.append(light)
		_base_energy.append(light.light_energy)

		var cs_body := StaticBody3D.new()
		cs_body.collision_layer = 1
		cs_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.40
		cyl.height = 0.80
		cs.shape = cyl
		cs.position = Vector3(0, 0.40, 0)
		cs_body.add_child(cs)
		holder.add_child(cs_body)


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():
		var n := _noise.get_noise_2d(_t * 2.6, float(i) * 11.0)
		_lights[i].light_energy = _base_energy[i] * (1.0 + n * 0.28)


## Ring positions used to spawn waves out of the dark, away from the player.
func spawn_points(count: int, avoid: Vector3, min_dist := 9.0) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var tries := 0
	while out.size() < count and tries < count * 40:
		tries += 1
		var a := randf() * TAU
		var r := randf_range(PILLAR_RING - 3.0, RADIUS - 3.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if p.distance_to(avoid) < min_dist:
			continue
		var ok := true
		for q in out:
			if p.distance_to(q) < 2.2:
				ok = false
				break
		if ok:
			out.append(p)
	while out.size() < count:
		var a2 := randf() * TAU
		out.append(Vector3(cos(a2) * (RADIUS - 4.0), 0.0,
				sin(a2) * (RADIUS - 4.0)))
	return out
