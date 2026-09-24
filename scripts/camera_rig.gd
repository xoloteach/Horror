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
const PITCH_MIN := deg_to_rad(-62.0)
const PITCH_MAX := deg_to_rad(38.0)

## free-look framing
const FREE_LEN := 4.30
const FREE_OFFSET := Vector3(0.45, 0.30, 0.0)
const FREE_FOV := 74.0

## tight aim framing: closer, further over the shoulder, narrower FOV
const AIM_LEN := 1.85
const AIM_OFFSET := Vector3(0.78, 0.22, 0.0)
const AIM_FOV := 55.0

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
	arm.margin = 0.30
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


func set_aiming(v: bool) -> void:
	_want_aim = v


func _process(delta: float) -> void:
	# drain touch look-drag accumulated since the last frame
	if enabled:
		var tl := Boot.consume_look()
		if tl.length_squared() > 0.0:
			yaw -= tl.x * SENS
			pitch = clampf(pitch - tl.y * SENS, PITCH_MIN, PITCH_MAX)

	var target := 1.0 if _want_aim else 0.0
	aim_blend = move_toward(aim_blend, target, BLEND_SPEED * delta)
	# smoothstep the blend so the transition eases at both ends
	var t: float = aim_blend * aim_blend * (3.0 - 2.0 * aim_blend)

	rotation.y = yaw
	pitch_node.rotation.x = pitch
	shoulder.position = FREE_OFFSET.lerp(AIM_OFFSET, t)
	arm.spring_length = lerpf(FREE_LEN, AIM_LEN, t)
	camera.fov = lerpf(FREE_FOV, AIM_FOV, t)

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
