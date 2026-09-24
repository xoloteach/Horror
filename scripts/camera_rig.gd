# CameraRig: third-person orbit camera. Free look normally; hold RMB (aim)
# lerps to a tight over-the-shoulder framing with crosshair. Trauma-based
# shake decays over time.
class_name CameraRig
extends Node3D

const FREE_DIST := 4.8
const AIM_DIST := 2.1
const SHOULDER_X := 0.85

var yaw: float = 0.0
var pitch: float = -0.22
var trauma: float = 0.0
var aiming: bool = false
var target: Node3D = null

var _aim_blend: float = 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var camera: Camera3D


func _ready() -> void:
	_yaw_node = Node3D.new()
	_yaw_node.name = "Yaw"
	add_child(_yaw_node)
	_pitch_node = Node3D.new()
	_pitch_node.name = "Pitch"
	_yaw_node.add_child(_pitch_node)
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 68.0
	camera.far = 220.0
	_pitch_node.add_child(camera)
	camera.position = Vector3(0, 0, FREE_DIST)
	camera.current = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		var sens := 0.0022 * (0.55 if aiming else 1.0)
		yaw -= mm.relative.x * sens
		pitch = clampf(pitch - mm.relative.y * sens, -1.15, 0.55)


func _process(delta: float) -> void:
	if target != null:
		var goal := target.global_position + Vector3(0, 1.55, 0)
		global_position = global_position.lerp(goal, 1.0 - exp(-10.0 * delta))
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, delta * 5.0)
	_yaw_node.rotation.y = yaw
	_pitch_node.rotation.x = pitch
	var dist := lerpf(FREE_DIST, AIM_DIST, _aim_blend)
	camera.position = Vector3(SHOULDER_X * _aim_blend, 0.28 * _aim_blend, dist)
	# Trauma shake: rotational + positional noise scaled by trauma^2.
	trauma = maxf(0.0, trauma - delta * 1.5)
	var s := trauma * trauma
	if s > 0.0001:
		camera.rotation.z = s * 0.14 * (randf() * 2.0 - 1.0)
		camera.h_offset = s * 0.55 * (randf() * 2.0 - 1.0)
		camera.v_offset = s * 0.55 * (randf() * 2.0 - 1.0)
	else:
		camera.rotation.z = 0.0
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func aim_origin() -> Vector3:
	return camera.project_ray_origin(camera.get_viewport().get_visible_rect().size * 0.5)


func aim_dir() -> Vector3:
	return camera.project_ray_normal(camera.get_viewport().get_visible_rect().size * 0.5)


func forward_flat() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3(0, 0, -1)
