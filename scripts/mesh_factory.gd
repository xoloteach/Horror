# MeshFactory: real Blender GLB models behind a clean API, with the
# procedural placeholder builders kept as fallback when a GLB is missing.
# Character animation goes through CharRig (scripts/rig.gd), which drives
# either the GLB Skeleton3D bones or the placeholder Node3D pivots.
class_name MeshFactory
extends RefCounted

static var _mats: Dictionary = {}
static var _tex_cache: Dictionary = {}


# Instantiate a GLB model, or return null when the file is missing/unusable
# so callers can fall back to the procedural placeholder.
static func _inst_glb(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null or not ps.can_instantiate():
		return null
	return ps.instantiate() as Node3D


static func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t := load(path) as Texture2D
	_tex_cache[path] = t
	return t


static func mat(color: Color, rough: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var k := "%s_%.2f_%.2f" % [color.to_html(), rough, metallic]
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	_mats[k] = m
	return m


static func stone_mat() -> StandardMaterial3D:
	if _mats.has("stone"):
		return _mats["stone"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://assets/textures/stone_albedo.png")
	m.normal_texture = _tex("res://assets/textures/stone_normal.png")
	m.roughness_texture = _tex("res://assets/textures/stone_roughness.png")
	m.roughness = 1.0
	m.uv1_scale = Vector3(2.0, 2.0, 2.0)
	_mats["stone"] = m
	return m


static func iron_mat() -> StandardMaterial3D:
	if _mats.has("iron"):
		return _mats["iron"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://assets/textures/iron_albedo.png")
	m.roughness_texture = _tex("res://assets/textures/iron_roughness.png")
	m.roughness = 1.0
	m.metallic = 0.85
	_mats["iron"] = m
	return m


static func edge_mat() -> StandardMaterial3D:
	# Bright sharpened blade edge.
	return mat(Color(0.82, 0.88, 0.95), 0.35, 0.9)


static func wood_mat() -> StandardMaterial3D:
	return mat(Color(0.23, 0.15, 0.09), 0.85, 0.0)


static func leather_mat() -> StandardMaterial3D:
	return mat(Color(0.32, 0.2, 0.12), 0.95, 0.0)


static func earth_mat() -> StandardMaterial3D:
	if _mats.has("earth"):
		return _mats["earth"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://assets/textures/frozeneath_albedo.png")
	m.normal_texture = _tex("res://assets/textures/frozeneath_normal.png")
	m.roughness = 0.95
	m.uv1_scale = Vector3(11.0, 11.0, 11.0)
	_mats["earth"] = m
	return m


static func rune_mat() -> StandardMaterial3D:
	if _mats.has("rune"):
		return _mats["rune"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex("res://assets/textures/runes_alpha.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 0.8, 1.0, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.65, 1.0)
	m.emission_energy_multiplier = 1.5
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.no_depth_test = false
	_mats["rune"] = m
	return m


static func box(size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	return mi


static func cyl(r_top: float, r_bot: float, height: float, material: Material, sides: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = sides
	cm.material = material
	mi.mesh = cm
	return mi


static func ball(radius: float, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 8
	sm.material = material
	mi.mesh = sm
	return mi


# ---------------------------------------------------------------- axe ---
# Local axes: +Y along handle, blade edge faces -Z (Godot forward),
# spin axis for throws = local X.
# The real axe.glb has the haft along +Y with the blade extending +X, so the
# model is pre-rotated +90° about Y to match this convention. Origin = grip
# center. Falls back to the procedural placeholder when the GLB is missing.
static func create_axe() -> Node3D:
	var root := Node3D.new()
	root.name = "Axe"
	var glb := _inst_glb("res://assets/models/axe.glb")
	if glb != null:
		var inner := Node3D.new()
		inner.name = "Model"
		inner.rotation.y = PI * 0.5
		inner.add_child(glb)
		root.add_child(inner)
		return root
	return _create_axe_procedural()


# Cutting-edge marker ("Socket_Emit") on the real axe; null on the fallback.
static func axe_emit_point(axe_root: Node3D) -> Node3D:
	return axe_root.find_child("Socket_Emit", true, false) as Node3D


static func _create_axe_procedural() -> Node3D:
	var root := Node3D.new()
	root.name = "Axe"
	var wood := wood_mat()
	var iron := iron_mat()
	var leather := leather_mat()

	var handle := cyl(0.035, 0.045, 1.15, wood)
	handle.position = Vector3(0, 0.575, 0)
	root.add_child(handle)

	var grip := cyl(0.052, 0.052, 0.32, leather)
	grip.position = Vector3(0, 0.28, 0)
	root.add_child(grip)

	var pommel := ball(0.06, iron)
	pommel.position = Vector3(0, 0.03, 0)
	root.add_child(pommel)

	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.02, 0)
	root.add_child(head)

	var poll := box(Vector3(0.14, 0.14, 0.16), iron)
	poll.position = Vector3(0, 0, 0.1)
	head.add_child(poll)

	var blade := box(Vector3(0.1, 0.34, 0.34), iron)
	blade.position = Vector3(0, 0.02, -0.16)
	blade.rotation.x = 0.12
	head.add_child(blade)

	var edge := box(Vector3(0.07, 0.38, 0.07), edge_mat())
	edge.position = Vector3(0, 0.03, -0.33)
	edge.rotation.x = 0.12
	head.add_child(edge)

	# Placeholder runic engraving: faint emissive inlay on the blade.
	var rune_inlay := box(Vector3(0.11, 0.2, 0.02), rune_glow_mat())
	rune_inlay.position = Vector3(0, 0.02, -0.16)
	head.add_child(rune_inlay)

	var emit := Marker3D.new()
	emit.name = "EmitPoint"
	emit.position = Vector3(0, 1.02, -0.33)
	root.add_child(emit)
	return root


static func rune_glow_mat() -> StandardMaterial3D:
	if _mats.has("rune_glow"):
		return _mats["rune_glow"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.7, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.65, 1.0)
	m.emission_energy_multiplier = 2.0
	_mats["rune_glow"] = m
	return m


# -------------------------------------------------------- humanoid ---
# Real GLB characters (feet at y=0, facing -Z), falling back to the
# procedural placeholder when the import misbehaves.
static func create_player() -> Node3D:
	var glb := _inst_glb("res://assets/models/player.glb")
	if glb != null:
		return glb
	return create_humanoid({
		"tunic": Color(0.32, 0.4, 0.55),
		"pants": Color(0.28, 0.24, 0.2),
		"skin": Color(0.87, 0.66, 0.52),
		"trim": Color(0.55, 0.5, 0.45),
		"hunch": 0.0,
	})


static func create_draugr() -> Node3D:
	var glb := _inst_glb("res://assets/models/draugr.glb")
	if glb != null:
		return glb
	return create_humanoid({
		"tunic": Color(0.32, 0.36, 0.28),
		"pants": Color(0.2, 0.2, 0.18),
		"skin": Color(0.55, 0.62, 0.5),
		"trim": Color(0.3, 0.28, 0.25),
		"hunch": 0.28,
	})


# cfg: {tunic, pants, skin, trim, hunch}
# Faces -Z. Named pivots: Hips/Torso/HeadPivot/ArmL/ArmR/HandSocket/LegL/LegR.
static func create_humanoid(cfg: Dictionary) -> Node3D:
	var tunic: Color = cfg.get("tunic", Color(0.35, 0.42, 0.55))
	var pants: Color = cfg.get("pants", Color(0.25, 0.22, 0.2))
	var skin: Color = cfg.get("skin", Color(0.85, 0.65, 0.5))
	var trim: Color = cfg.get("trim", Color(0.5, 0.5, 0.55))
	var hunch: float = cfg.get("hunch", 0.0)

	var root := Node3D.new()
	root.name = "Humanoid"

	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.95, 0)
	root.add_child(hips)

	var pelvis := box(Vector3(0.42, 0.24, 0.28), mat(pants))
	pelvis.position = Vector3(0, 0.02, 0)
	hips.add_child(pelvis)

	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 0.14, 0)
	torso.rotation.x = hunch
	hips.add_child(torso)

	var chest := box(Vector3(0.5, 0.56, 0.3), mat(tunic, 0.8))
	chest.position = Vector3(0, 0.32, 0)
	torso.add_child(chest)

	for sx in [-1.0, 1.0]:
		var pad := box(Vector3(0.18, 0.12, 0.22), mat(trim, 0.6, 0.4))
		pad.position = Vector3(0.32 * sx, 0.55, 0)
		torso.add_child(pad)

	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0, 0.66, 0)
	torso.add_child(head_pivot)
	var head := box(Vector3(0.26, 0.3, 0.28), mat(skin, 0.7))
	head.position = Vector3(0, 0.16, -0.01)
	head_pivot.add_child(head)
	# eyes: two dark slits facing -Z
	for sx in [-1.0, 1.0]:
		var eye := box(Vector3(0.045, 0.045, 0.02), mat(Color(0.05, 0.05, 0.06)))
		eye.position = Vector3(0.07 * sx, 0.18, -0.15)
		head_pivot.add_child(eye)

	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var arm := Node3D.new()
		arm.name = "Arm" + side
		arm.position = Vector3(0.33 * sx, 0.5, 0)
		torso.add_child(arm)
		var upper := box(Vector3(0.15, 0.5, 0.17), mat(tunic, 0.8))
		upper.position = Vector3(0, -0.26, 0)
		arm.add_child(upper)
		var hand := box(Vector3(0.13, 0.14, 0.15), mat(skin, 0.7))
		hand.position = Vector3(0, -0.55, 0)
		arm.add_child(hand)
		if side == "R":
			var socket := Node3D.new()
			socket.name = "HandSocket"
			socket.position = Vector3(0, -0.58, -0.04)
			arm.add_child(socket)

	for side in ["L", "R"]:
		var sx := -1.0 if side == "L" else 1.0
		var leg := Node3D.new()
		leg.name = "Leg" + side
		leg.position = Vector3(0.14 * sx, 0.92, 0)
		root.add_child(leg)
		var thigh := box(Vector3(0.18, 0.88, 0.2), mat(pants))
		thigh.position = Vector3(0, -0.46, 0)
		leg.add_child(thigh)
		var boot := box(Vector3(0.19, 0.16, 0.32), leather_mat())
		boot.position = Vector3(0, -0.88, -0.05)
		leg.add_child(boot)

	return root


# ---------------------------------------------------------- arena ---
# Real GLB pieces (base at y=0), each with a matching collision shape.
# Falls back to the procedural versions when a GLB is missing.
static func create_pillar(height: float, broken: bool) -> StaticBody3D:
	# pillar.glb is ~3.4 m tall with a ruined top; scale to the height asked.
	var glb := _inst_glb("res://assets/models/pillar.glb")
	if glb != null:
		var body := StaticBody3D.new()
		body.name = "Pillar"
		body.add_to_group("stone")
		var s := height / 3.4
		glb.scale = Vector3(s, s, s)
		body.add_child(glb)
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.55 * s
		shape.height = height
		col.shape = shape
		col.position = Vector3(0, height * 0.5, 0)
		body.add_child(col)
		if broken:
			body.rotation.x = randf_range(-0.05, 0.05)
			body.rotation.z = randf_range(-0.05, 0.05)
		return body
	return _create_pillar_procedural(height, broken)


static func _create_pillar_procedural(height: float, broken: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pillar"
	body.add_to_group("stone")
	var stone := stone_mat()
	var segs := int(clamp(height / 1.4, 2.0, 5.0))
	var y := 0.0
	for i in segs:
		var h := height / segs
		var r := 0.85 - 0.08 * i + randf_range(-0.05, 0.05)
		var drum := cyl(r, r + 0.06, h, stone, 12)
		drum.position = Vector3(randf_range(-0.06, 0.06), y + h * 0.5, randf_range(-0.06, 0.06))
		drum.rotation.y = randf() * TAU
		body.add_child(drum)
		y += h
	if not broken:
		var cap := box(Vector3(2.1, 0.35, 2.1), stone)
		cap.position = Vector3(0, y + 0.17, 0)
		body.add_child(cap)
		y += 0.35
	else:
		body.rotation.z = randf_range(-0.06, 0.06)
		body.rotation.x = randf_range(-0.06, 0.06)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.95
	shape.height = y
	col.shape = shape
	col.position = Vector3(0, y * 0.5, 0)
	body.add_child(col)
	return body


static func create_slab() -> StaticBody3D:
	# slab.glb is a 2 x 0.3 x 2 m cracked slab, bottom at y=0.
	var glb := _inst_glb("res://assets/models/slab.glb")
	if glb != null:
		var body := StaticBody3D.new()
		body.name = "Slab"
		body.add_to_group("stone")
		glb.rotation.y = randf() * TAU
		body.add_child(glb)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0, 0.4, 2.0)
		col.shape = shape
		col.position = Vector3(0, 0.15, 0)
		body.add_child(col)
		return body
	return _create_slab_procedural()


static func _create_slab_procedural() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Slab"
	body.add_to_group("stone")
	var m := box(Vector3(randf_range(1.6, 2.6), 0.28, randf_range(1.2, 2.0)), stone_mat())
	m.rotation.y = randf() * TAU
	body.add_child(m)
	body.rotation.y = randf() * TAU
	body.rotation.x = randf_range(-0.08, 0.08)
	body.rotation.z = randf_range(-0.08, 0.08)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 0.5, 1.8)
	col.shape = shape
	body.add_child(col)
	return body


static func create_wall(length: float, height: float) -> StaticBody3D:
	# wall.glb is one 4 x 3 x 0.6 m ruined segment, bottom at y=0:
	# tile segments along the length and scale to the target height.
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.add_to_group("stone")
	if ResourceLoader.exists("res://assets/models/wall.glb"):
		var ps := load("res://assets/models/wall.glb") as PackedScene
		if ps != null and ps.can_instantiate():
			var n := maxi(1, int(round(length / 4.0)))
			var sy := height / 3.0
			for i in n:
				var m := ps.instantiate() as Node3D
				m.position = Vector3(-length * 0.5 + 2.0 + i * 4.0, 0, randf_range(-0.06, 0.06))
				m.scale = Vector3(1.0, sy, 1.0)
				body.add_child(m)
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(length, height, 0.9)
			col.shape = shape
			col.position = Vector3(0, height * 0.5, 0)
			body.add_child(col)
			return body
	return _create_wall_procedural(length, height)


static func _create_wall_procedural(length: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.add_to_group("stone")
	var stone := stone_mat()
	var segs := int(length / 4.0)
	for i in segs:
		var h := height + randf_range(-0.7, 0.3)
		var seg := box(Vector3(4.0, h, 1.6), stone)
		seg.position = Vector3(-length * 0.5 + 2.0 + i * 4.0, h * 0.5, randf_range(-0.15, 0.15))
		body.add_child(seg)
		# crenellation
		if randf() < 0.7:
			var merlon := box(Vector3(1.2, 0.6, 1.6), stone)
			merlon.position = Vector3(seg.position.x, h + 0.3, seg.position.z)
			body.add_child(merlon)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, height, 1.6)
	col.shape = shape
	col.position = Vector3(0, height * 0.5, 0)
	body.add_child(col)
	return body
