class_name CameraRig
extends Node3D
## Over-the-shoulder camera with a free-look and a tight aim mode.
##
## Node chain built in _ready():
##   CameraRig   (yaw)
##    +- Pitch   (pitch)
##        +- Shoulder  (lateral/vertical offset -> the "over the shoulder" framing)
##            +- SpringArm3D  (pulls in when geometry would clip the view)
##                +- Camera3D (carries only shake, so shake never fights the rig)

const SENS := 0.0022
const JOY_LOOK_SPEED := 2.35
const PITCH_MIN := deg_to_rad(-62.0)
const PITCH_MAX := deg_to_rad(38.0)

## free-look framing
const FREE_LEN := 5.25
const FREE_OFFSET := Vector3(0.62, 0.30, 0.0)
const FREE_FOV := 68.0

## Aim stays close enough to feel intimate without letting the production hero
## block half the target as the old 1.85m boom did.
const AIM_LEN := 3.10
const AIM_OFFSET := Vector3(0.94, 0.19, 0.0)
const AIM_FOV := 51.0

const BLEND_SPEED := 9.5

var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var aim_blend := 0.0
var enabled := true

var pitch_node: Node3D
var shoulder: Node3D
var arm: SpringArm3D
var boom: Node3D      # positioned BY the spring arm; never written to directly
var camera: Camera3D

var _want_aim := false
var _shoulder_side := 1.0
var _fov_kick := 0.0


func _ready() -> void:
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	add_child(pitch_node)

	shoulder = Node3D.new()
	shoulder.name = "Shoulder"
	pitch_node.add_child(shoulder)

	arm = SpringArm3D.new()
	arm.name = "Arm"
	arm.spring_length = FREE_LEN
	arm.margin = 0.36
	arm.collision_mask = 1  # world geometry only
	shoulder.add_child(arm)

	# SpringArm3D repositions ALL of its direct children every frame. If the
	# camera were a direct child, writing shake into camera.position would fight
	# the arm and collapse the boom to zero length (camera ends up inside the
	# player's head). The boom absorbs the arm's placement; shake goes on the
	# camera one level deeper, where nothing else writes to it.
	boom = Node3D.new()
	boom.name = "Boom"
	arm.add_child(boom)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FREE_FOV
	camera.near = 0.08
	camera.far = 260.0
	boom.add_child(camera)
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and \
			Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clampf(pitch - event.relative.y * SENS, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("shoulder_swap"):
		_shoulder_side *= -1.0


func set_aiming(v: bool) -> void:
	_want_aim = v


func add_fov_kick(amount: float) -> void:
	_fov_kick = minf(6.0, _fov_kick + amount)


func _process(delta: float) -> void:
	# drain touch look-drag accumulated since the last frame
	if enabled:
		var tl := Boot.consume_look()
		if tl.length_squared() > 0.0:
			yaw -= tl.x * SENS
			pitch = clampf(pitch - tl.y * SENS, PITCH_MIN, PITCH_MAX)

	# Gamepad right stick uses time-based angular speed rather than pixel sensitivity.
	if enabled:
		var joy_look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if joy_look.length_squared() > 0.01:
			yaw -= joy_look.x * JOY_LOOK_SPEED * delta
			pitch = clampf(pitch - joy_look.y * JOY_LOOK_SPEED * delta,
					PITCH_MIN, PITCH_MAX)

	var target := 1.0 if _want_aim else 0.0
	aim_blend = move_toward(aim_blend, target, BLEND_SPEED * delta)
	# smoothstep the blend so the transition eases at both ends
	var t: float = aim_blend * aim_blend * (3.0 - 2.0 * aim_blend)

	rotation.y = yaw
	pitch_node.rotation.x = pitch
	var offset := FREE_OFFSET.lerp(AIM_OFFSET, t)
	offset.x *= _shoulder_side
	shoulder.position = offset
	arm.spring_length = lerpf(FREE_LEN, AIM_LEN, t)
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 15.0)
	camera.fov = lerpf(FREE_FOV, AIM_FOV, t) + _fov_kick

	var s: Array = Juice.shake_sample(1.0)
	camera.position = s[0] as Vector3
	camera.rotation.z = s[1] as float


## World-space ray the axe throw is aimed along.
func aim_origin() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


## Point under the crosshair: first world hit, else a far point along the ray.
func aim_point(max_dist: float, exclude: Array[RID]) -> Vector3:
	var from := aim_origin()
	var to := from + aim_direction() * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 4  # world + enemies
	q.exclude = exclude
	q.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit["position"]


func flat_forward() -> Vector3:
	var f := -global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()


func flat_right() -> Vector3:
	var r := global_transform.basis.x
	r.y = 0.0
	if r.length_squared() < 0.0001:
		return Vector3.RIGHT
	return r.normalized()
