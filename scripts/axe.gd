# LeviathanAxe: throw / embed / Bezier-recall state machine.
# States: EQUIPPED(0), AIRBORNE_THROW(1), EMBEDDED_WORLD(2),
#         EMBEDDED_ENEMY(3), RECALLING(4).
# The axe is a plain Node3D moved kinematically (no RigidBody) for determinism.
class_name LeviathanAxe
extends Node3D

enum State { EQUIPPED, AIRBORNE_THROW, EMBEDDED_WORLD, EMBEDDED_ENEMY, RECALLING }

const THROW_SPEED := 30.0
const THROW_DAMAGE := 42.0
const RECALL_DAMAGE := 25.0
const RECALL_HIT_RADIUS := 1.35

var state: int = State.EQUIPPED
var player: Node3D = null
var hand_socket: Node3D = null
var host_enemy: Node = null  # enemy node when EMBEDDED_ENEMY

var visual: Node3D

var _vel := Vector3.ZERO
var _spin := 0.0
var _spin_speed := 0.0
var _life := 0.0

# recall bezier
var _rt := 0.0
var _rdur := 0.6
var _rp0 := Vector3.ZERO
var _rp1 := Vector3.ZERO
var _recall_cd: Dictionary = {}


func _ready() -> void:
	add_to_group("axe")
	visual = MeshFactory.create_axe()
	add_child(visual)


func is_equipped() -> bool:
	return state == State.EQUIPPED


func attach_to_hand() -> void:
	if hand_socket == null:
		return
	if get_parent() != null:
		get_parent().remove_child(self)
	hand_socket.add_child(self)
	# carried: handle forward, blade edge down
	transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), Vector3.ZERO)
	state = State.EQUIPPED
	host_enemy = null


func _attach_to_world(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if get_parent() != null:
		get_parent().remove_child(self)
	scene.add_child(self)
	global_position = at


func throw_from(origin: Vector3, dir: Vector3) -> void:
	if state != State.EQUIPPED:
		return
	_attach_to_world(origin)
	_vel = dir.normalized() * THROW_SPEED
	_spin_speed = 24.0
	_spin = 0.0
	_life = 0.0
	host_enemy = null
	state = State.AIRBORNE_THROW
	AudioManager.play_3d("recall_whistle", origin)


func _physics_process(delta: float) -> void:
	match state:
		State.AIRBORNE_THROW:
			_fly_step(delta)
		State.RECALLING:
			_recall_step(delta)


func _fly_step(delta: float) -> void:
	_spin += _spin_speed * delta
	_life += delta
	var from := global_position
	var to := from + _vel * delta

	# world collision along the segment
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if player != null:
		q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)

	var enemy := _enemy_on_segment(from, to)
	if enemy != null:
		global_position = to
		_embed_enemy(enemy)
	elif not hit.is_empty():
		_embed_world(hit)
	else:
		global_position = to
		_orient_flight()

	if state == State.AIRBORNE_THROW and _life > 2.2:
		start_recall()
		return
	# safety: never tunnel below the arena floor
	if state == State.AIRBORNE_THROW and global_position.y < 0.06:
		_embed_world({
			"position": Vector3(global_position.x, 0.06, global_position.z),
			"normal": Vector3.UP,
			"collider": null,
		})


func _enemy_on_segment(from: Vector3, to: Vector3) -> Node:
	var seg := to - from
	var seg_len2 := seg.length_squared()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.get("alive"):
			continue
		var chest: Vector3 = e.chest_position()
		var t := 0.0
		if seg_len2 > 0.0001:
			t = clampf((chest - from).dot(seg) / seg_len2, 0.0, 1.0)
		if from.lerp(to, t).distance_to(chest) < 1.1:
			return e
	return null


func _orient_flight() -> void:
	var dir := _vel.normalized()
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var b := Basis.looking_at(dir, up)
	b = b.rotated(b.x.normalized(), _spin)
	global_transform = Transform3D(b, global_position)


func _embed_world(hit: Dictionary) -> void:
	state = State.EMBEDDED_WORLD
	host_enemy = null
	var n: Vector3 = hit["normal"]
	var pos: Vector3 = hit["position"]
	global_position = pos - n * 0.14  # sink the blade slightly in
	var b: Basis
	if absf(n.y) > 0.93:
		b = Basis.from_euler(Vector3(-PI * 0.5, 0.0, randf() * TAU))
	else:
		b = Basis.looking_at(-n, Vector3.UP)
	global_transform = Transform3D(b, global_position)
	FX.spawn_sparks(global_position, n)
	FX.spawn_dust(global_position, n)
	var col: Object = hit.get("collider")
	var snd := "stone_impact"
	if col is Node and (col as Node).is_in_group("wood"):
		snd = "wood_impact"
	elif col is Node and (col as Node).is_in_group("earth"):
		snd = "embed_thunk"
	AudioManager.play_3d(snd, global_position)
	Game.add_trauma(0.38)


func _embed_enemy(e: Node) -> void:
	state = State.EMBEDDED_ENEMY
	host_enemy = e
	var gt := global_transform
	if get_parent() != null:
		get_parent().remove_child(self)
	var socket := e.get_node_or_null("ChestSocket")
	if socket != null:
		socket.add_child(self)
	else:
		e.add_child(self)
	global_transform = gt
	e.take_damage(THROW_DAMAGE, global_position, true)
	FX.spawn_blood(e.chest_position())
	AudioManager.play_3d("flesh_slice", global_position)
	AudioManager.play_3d("blood_impact", global_position, -2.0)
	Game.add_trauma(0.3)


func start_recall() -> void:
	if state == State.EQUIPPED or state == State.RECALLING:
		return
	if state == State.EMBEDDED_ENEMY and is_instance_valid(host_enemy):
		var gt := global_transform
		var tree := get_tree()
		if get_parent() != null:
			get_parent().remove_child(self)
		tree.current_scene.add_child(self)
		global_transform = gt
	host_enemy = null
	if hand_socket == null:
		return
	_rp0 = global_position
	var hand_pos := hand_socket.global_position
	var dist := _rp0.distance_to(hand_pos)
	_rdur = clampf(dist / 24.0, 0.35, 0.95)
	_rp1 = (_rp0 + hand_pos) * 0.5 + Vector3(0.0, 2.4 + dist * 0.12, 0.0)
	_rt = 0.0
	_recall_cd.clear()
	_spin_speed = 30.0
	state = State.RECALLING
	AudioManager.play_3d("recall_whistle", _rp0, -4.0)


func _recall_step(delta: float) -> void:
	_rt += delta / _rdur
	_spin += _spin_speed * delta
	var t := clampf(_rt, 0.0, 1.0)
	var p2: Vector3 = hand_socket.global_position if hand_socket != null else _rp0
	var pos := _bez(_rp0, _rp1, p2, t)
	var dir := pos - global_position
	global_position = pos
	if dir.length() > 0.001:
		var b := Basis.looking_at(dir.normalized(), Vector3.UP)
		b = b.rotated(b.x.normalized(), _spin)
		global_transform = Transform3D(b, pos)
	# damage every enemy intersecting the return path (per-enemy cooldown)
	var now := Time.get_ticks_msec() / 1000.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.get("alive"):
			continue
		var id := e.get_instance_id()
		if now - float(_recall_cd.get(id, -10.0)) < 0.4:
			continue
		if pos.distance_to(e.chest_position()) < RECALL_HIT_RADIUS:
			_recall_cd[id] = now
			e.take_damage(RECALL_DAMAGE, pos, false)
			FX.spawn_blood(e.chest_position())
			AudioManager.play_3d("flesh_slice", pos)
			Game.add_trauma(0.12)
	if _rt >= 1.0:
		_catch()


func _bez(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * (u * u) + b * (2.0 * u * t) + c * (t * t)


func _catch() -> void:
	attach_to_hand()
	AudioManager.play_2d("catch_metal")
	Game.hit_stop(0.08, 0.05)
	Game.add_trauma(0.22)


# Called by the host enemy when it dies with the axe embedded.
func on_host_died() -> void:
	if state != State.EMBEDDED_ENEMY:
		return
	host_enemy = null
	var gt := global_transform
	var tree := get_tree()
	if get_parent() != null:
		get_parent().remove_child(self)
	tree.current_scene.add_child(self)
	global_transform = gt
	# drop to the ground where the body fell
	global_position = Vector3(global_position.x, 0.2, global_position.z)
	state = State.EMBEDDED_WORLD
