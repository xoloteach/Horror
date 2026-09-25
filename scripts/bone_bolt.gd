class_name BoneBolt
extends Node3D
## Lightweight ranged projectile used by skeleton mages and the boss.

var target: Node3D
var damage := 12.0
var speed := 11.0
var velocity := Vector3.FORWARD
var lifetime := 5.0
var source_rid := RID()
var tint := Color(0.55, 0.22, 1.0)


func setup(p_target: Node3D, origin: Vector3, p_damage: float,
		p_speed: float, p_source_rid: RID, p_tint := Color(0.55, 0.22, 1.0)) -> void:
	target = p_target
	global_position = origin
	damage = p_damage
	speed = p_speed
	source_rid = p_source_rid
	tint = p_tint
	var destination := target.global_position + Vector3.UP if is_instance_valid(target) \
			else origin + Vector3.FORWARD
	velocity = (destination - origin).normalized() * speed
	_build_visual()


func _build_visual() -> void:
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.13
	sphere.height = 0.26
	sphere.radial_segments = 12
	sphere.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 5.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = material
	orb.mesh = sphere
	add_child(orb)

	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.2
	light.omni_range = 3.2
	light.shadow_enabled = false
	add_child(light)

	var particles := GPUParticles3D.new()
	particles.amount = 18
	particles.lifetime = 0.35
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.08
	process.direction = Vector3.ZERO
	process.spread = 180.0
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.25
	process.gravity = Vector3.ZERO
	process.scale_min = 0.03
	process.scale_max = 0.09
	var gradient := Gradient.new()
	gradient.set_color(0, Color(tint, 0.85))
	gradient.set_color(1, Color(tint, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var particle_material := StandardMaterial3D.new()
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	particle_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particle_material.vertex_color_use_as_albedo = true
	particle_material.albedo_texture = load("res://assets/production/vfx/magic_03.png")
	quad.material = particle_material
	particles.draw_pass_1 = quad
	add_child(particles)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if is_instance_valid(target):
		var desired := (target.global_position + Vector3.UP - global_position).normalized() * speed
		velocity = velocity.lerp(desired, minf(1.0, delta * 1.7)).normalized() * speed
	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 2
	if source_rid.is_valid():
		query.exclude = [source_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var normal: Vector3 = hit["normal"]
		if collider != null and collider.has_method("take_hit"):
			var direction := (to - from).normalized()
			collider.take_hit(damage, direction)
			Fx.rune_flash(get_parent(), hit["position"])
		else:
			Fx.sparks(get_parent(), hit["position"], normal)
		queue_free()
		return
	global_position = to
	rotate_object_local(Vector3.FORWARD, delta * 8.0)
