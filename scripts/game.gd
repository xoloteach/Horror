# Game autoload: hit-stop (time-scale) and camera-trauma routing.
extends Node

var _hs_token: int = 0
var camera_rig: Node = null  # registered by main.gd


func register_camera(rig: Node) -> void:
	camera_rig = rig


func add_trauma(amount: float) -> void:
	if camera_rig != null and camera_rig.has_method("add_trauma"):
		camera_rig.add_trauma(amount)


func hit_stop(duration: float = 0.08, scale: float = 0.05) -> void:
	_hs_token += 1
	var token := _hs_token
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	# Only restore if no newer hit-stop superseded this one.
	if token == _hs_token:
		Engine.time_scale = 1.0
