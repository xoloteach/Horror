# FX autoload: one-shot GPUParticles3D bursts (WebGL-safe: small amounts,
# billboarded quads, unshaded materials). Freed automatically via `finished`.
extends Node

var _mats: Dictionary = {}


func _mat(color: Color) -> StandardMaterial3D:
	var k := color.to_html()
	if _mats.has(k):
		return _mats[k]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	_mats[k] = m
	return m


func burst(pos: Vector3, normal: Vector3, color: Color, count: int,
		speed: float, lifetime: float, quad_size: float, gravity_y: float = -9.8) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.92
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = normal
	pm.spread = 40.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity_y, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# fade out over life
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = _mat(color)
	p.draw_pass_1 = quad
	var scene := get_tree().current_scene
	if scene == null:
		p.queue_free()
		return
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.emitting = true


func spawn_blood(pos: Vector3) -> void:
	burst(pos, Vector3.UP, Color(0.55, 0.04, 0.05, 1.0), 20, 6.0, 0.55, 0.13)


func spawn_sparks(pos: Vector3, normal: Vector3) -> void:
	burst(pos, normal, Color(1.0, 0.75, 0.3, 1.0), 16, 9.0, 0.4, 0.07, -14.0)


func spawn_dust(pos: Vector3, normal: Vector3) -> void:
	burst(pos, normal, Color(0.75, 0.78, 0.85, 0.8), 14, 3.0, 0.8, 0.22, -1.5)


func spawn_snow_puff(pos: Vector3) -> void:
	burst(pos, Vector3.UP, Color(0.9, 0.93, 1.0, 0.9), 10, 2.5, 0.7, 0.16, -2.0)
