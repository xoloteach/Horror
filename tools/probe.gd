extends Node3D
## Diagnostic probe: dumps camera/player framing and a visibility audit of the
## player model, then reports wave progression. Used to chase down rendering and
## gameplay-loop issues that a pass/fail test would not surface.
##
## Run: godot --headless --rendering-driver opengl3 res://scenes/Probe.tscn

var arena: Arena
var player: Player
var _f := 0


func _ready() -> void:
	arena = Arena.new()
	add_child(arena)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)


func _physics_process(_d: float) -> void:
	_f += 1
	if _f == 60:
		_dump()
	elif _f == 61:
		get_tree().quit(0)


func _count(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		out.append({
			"name": String(mi.name),
			"visible": mi.visible,
			"vis_in_tree": mi.is_visible_in_tree(),
			"layers": mi.layers,
			"aabb_size": mi.get_aabb().size,
			"gpos": mi.global_position,
		})
	for c in n.get_children():
		_count(c, out)


func _dump() -> void:
	var cam := player.rig.camera
	print("\n=== FRAMING PROBE ===")
	print("player.global_position = %s" % player.global_position)
	print("rig.global_position    = %s" % player.rig.global_position)
	print("camera.global_position = %s" % cam.global_position)
	print("camera forward (-Z)    = %s" % (-cam.global_transform.basis.z))
	print("camera fov=%.1f near=%.3f  arm.spring_length=%.2f" % [
		cam.fov, cam.near, player.rig.arm.spring_length])
	print("dist(camera, player)   = %.3f" % cam.global_position.distance_to(
			player.global_position))
	print("model.global_position  = %s  scale=%s" % [
		player.model.global_position, player.model.scale])

	var meshes: Array = []
	_count(player.model, meshes)
	print("\nplayer model mesh count = %d" % meshes.size())
	var hidden := 0
	var zero := 0
	for m in meshes:
		if not m["vis_in_tree"]:
			hidden += 1
		if (m["aabb_size"] as Vector3).length() < 0.0001:
			zero += 1
	print("  not visible in tree: %d" % hidden)
	print("  zero-size aabb:      %d" % zero)
	for m in meshes.slice(0, 6):
		print("  %-14s vis=%s aabb=%s gpos=%s" % [
			m["name"], str(m["vis_in_tree"]),
			str((m["aabb_size"] as Vector3).round()), str(m["gpos"])])

	# is the player inside the camera frustum?
	var vp_cam := get_viewport().get_camera_3d()
	print("\nviewport camera = %s (is player's? %s)" % [
		str(vp_cam), str(vp_cam == cam)])
	var chest: Node3D = player.model.find_child("Chest", true, false)
	if chest != null:
		var sp := cam.unproject_position(chest.global_position)
		print("chest world=%s -> screen=%s  behind=%s" % [
			chest.global_position, sp,
			str(cam.is_position_behind(chest.global_position))])

	_axe_silhouette(cam)
	print("=====================\n")


## How much of the axe the camera can actually see.
##
## `edge_on` is |dot(blade direction, camera forward)|: near 1.0 means the bit
## points straight toward or away from the camera and the axe renders as a thin
## sliver; lower values mean the blade is presented broadside. `screen_area` is
## the projected footprint of the axe's bounds in pixels.
func _axe_silhouette(cam: Camera3D) -> void:
	var axe := player.axe
	if axe == null:
		print("\naxe: MISSING")
		return
	var blade := -axe.global_transform.basis.z.normalized()
	var fwd := -cam.global_transform.basis.z.normalized()
	var edge_on: float = absf(blade.dot(fwd))

	# gather world-space corners of every axe mesh
	var pts: Array[Vector3] = []
	var stack: Array[Node] = [axe]
	var mesh_n := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			mesh_n += 1
			var mi := n as MeshInstance3D
			var ab := mi.get_aabb()
			for i in 8:
				pts.append(mi.global_transform * ab.get_endpoint(i))
		for c in n.get_children():
			stack.append(c)

	var min_s := Vector2(1e9, 1e9)
	var max_s := Vector2(-1e9, -1e9)
	var visible_pts := 0
	for p in pts:
		if cam.is_position_behind(p):
			continue
		visible_pts += 1
		var s := cam.unproject_position(p)
		min_s = min_s.min(s)
		max_s = max_s.max(s)
	var area := 0.0
	if visible_pts > 0:
		area = absf(max_s.x - min_s.x) * absf(max_s.y - min_s.y)

	print("\naxe state=%d parent=%s meshes=%d" % [
		axe.state, str(axe.get_parent().name), mesh_n])
	print("  blade-vs-camera |dot| = %.3f  (1.0 = edge-on sliver)" % edge_on)
	print("  projected bounds = %s px  area=%.0f px^2" % [
		str((max_s - min_s).round()), area])
	print("  world pos = %s" % axe.global_position)
