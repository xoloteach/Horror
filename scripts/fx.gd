class_name Fx
extends RefCounted
## One-shot particle burst factory.
##
## Uses GPUParticles3D (supported by the Compatibility renderer, so it survives
## the WebGL export) with small amounts and short lifetimes.
##
## PERFORMANCE NOTE: every heavy GPU-side resource (process material, gradient
## texture, quad mesh, billboard material) is built once and cached statically.
## A naive implementation allocates a fresh ParticleProcessMaterial + Gradient +
## GradientTexture1D per hit, which means new GPU uploads on every single sword
## blow -- a reliable source of hitching in a WebGL build. Instead the emitter
## NODE is rotated so its local +Y aligns with the surface normal, letting one
## shared material serve every direction. Per-hit variation comes from `amount`,
## which is a node property and therefore free.

enum Kind { BLOOD, SPARKS, DUST, RUNE }

static var _proc := {}
static var _mesh := {}


static func _billboard(color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = (BaseMaterial3D.BLEND_MODE_ADD if additive
			else BaseMaterial3D.BLEND_MODE_MIX)
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.disable_receive_shadows = true
	return m


static func _ramp(a: Color, b: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _quad(size: float, mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	return q


## Builds and caches the shared resources for one effect kind.
static func _ensure(kind: Kind) -> void:
	if _proc.has(kind):
		return
	var p := ParticleProcessMaterial.new()
	# +Y local: the emitter node is oriented so this points along the normal
	p.direction = Vector3.UP

	match kind:
		Kind.BLOOD:
			p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.10
			p.spread = 52.0
			p.initial_velocity_min = 2.4
			p.initial_velocity_max = 7.5
			p.gravity = Vector3(0, -13.0, 0)
			p.damping_min = 1.0
			p.damping_max = 3.5
			p.scale_min = 0.05
			p.scale_max = 0.17
			p.angular_velocity_min = -220.0
			p.angular_velocity_max = 220.0
			p.color_ramp = _ramp(Color(0.62, 0.05, 0.04, 1.0),
					Color(0.20, 0.02, 0.02, 0.0))
			_mesh[kind] = _quad(0.14,
					_billboard(Color(0.6, 0.05, 0.04), false))

		Kind.SPARKS:
			p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
			p.spread = 68.0
			p.initial_velocity_min = 5.0
			p.initial_velocity_max = 13.0
			p.gravity = Vector3(0, -17.0, 0)
			p.damping_min = 2.0
			p.damping_max = 6.0
			p.scale_min = 0.020
			p.scale_max = 0.055
			p.color_ramp = _ramp(Color(1.0, 0.92, 0.62, 1.0),
					Color(1.0, 0.32, 0.05, 0.0))
			_mesh[kind] = _quad(0.05,
					_billboard(Color(1.0, 0.8, 0.45), true))

		Kind.DUST:
			p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.16
			p.spread = 85.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 2.4
			p.gravity = Vector3(0, -1.6, 0)
			p.damping_min = 1.5
			p.damping_max = 3.0
			p.scale_min = 0.18
			p.scale_max = 0.52
			p.color_ramp = _ramp(Color(0.58, 0.56, 0.52, 0.55),
					Color(0.45, 0.44, 0.42, 0.0))
			_mesh[kind] = _quad(0.40,
					_billboard(Color(0.55, 0.53, 0.50), false))

		Kind.RUNE:
			p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.22
			p.spread = 180.0
			p.initial_velocity_min = 1.2
			p.initial_velocity_max = 4.2
			p.gravity = Vector3(0, -2.0, 0)
			p.damping_min = 3.0
			p.damping_max = 7.0
			p.scale_min = 0.03
			p.scale_max = 0.11
			p.color_ramp = _ramp(Color(0.72, 0.95, 1.0, 1.0),
					Color(0.20, 0.55, 0.95, 0.0))
			_mesh[kind] = _quad(0.08,
					_billboard(Color(0.7, 0.93, 1.0), true))

	_proc[kind] = p


## Orthonormal basis whose +Y axis lies along `n`.
static func _align_y(n: Vector3) -> Basis:
	var y := n.normalized()
	if y.length_squared() < 0.5:
		y = Vector3.UP
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _burst(parent: Node, pos: Vector3, normal: Vector3, kind: Kind,
		amount: int, lifetime: float) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	_ensure(kind)
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.45
	p.fixed_fps = 30
	p.local_coords = false
	p.draw_pass_1 = _mesh[kind]
	p.process_material = _proc[kind]
	p.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	parent.add_child(p)
	p.global_transform = Transform3D(_align_y(normal), pos)
	p.emitting = true

	var t := Timer.new()
	t.wait_time = lifetime * 1.9 + 0.2
	t.one_shot = true
	t.autostart = true
	p.add_child(t)
	t.timeout.connect(func(): if is_instance_valid(p): p.queue_free())


static func blood(parent: Node, pos: Vector3, normal: Vector3,
		scale_mult: float = 1.0) -> void:
	_burst(parent, pos, normal, Kind.BLOOD, int(26.0 * scale_mult), 0.85)


static func sparks(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_burst(parent, pos, normal, Kind.SPARKS, 22, 0.45)


static func dust(parent: Node, pos: Vector3, normal: Vector3) -> void:
	_burst(parent, pos, normal, Kind.DUST, 14, 1.15)


static func rune_flash(parent: Node, pos: Vector3) -> void:
	_burst(parent, pos, Vector3.UP, Kind.RUNE, 20, 0.55)
