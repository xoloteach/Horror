class_name LeviathanAxe
extends Node3D
## The Leviathan Axe: throw, embed, and Bezier recall.
##
## State machine
##   EQUIPPED        parented to the player's hand socket
##   AIRBORNE_THROW  kinematic flight along the aim ray, tumbling about its own
##                   thickness axis, segment-raycast each tick for the hit
##   EMBEDDED_WORLD  aligned to the surface normal, blade buried EMBED_DEPTH deep
##   EMBEDDED_ENEMY  reparented onto the draugr so it rides the stagger animation
##   RECALLING       cubic Bezier back to the (moving) hand, cleaving on the way
##
## Model axes, established by the Blender->glTF conversion:
##   +Y = haft (head at +Y, pommel at -Y)
##   -Z = cutting edge / travel direction
##   +X = blade thickness -> the natural tumble axis

enum State { EQUIPPED, AIRBORNE_THROW, EMBEDDED_WORLD, EMBEDDED_ENEMY, RECALLING }

signal state_changed(new_state: State)
signal caught

# --- geometry, measured from axe.glb
const BLADE_REACH := 0.356   # origin -> cutting edge along -Z
const EMBED_DEPTH := 0.11    # how deep the bit buries itself

# --- throw tuning
const THROW_SPEED := 31.0
const THROW_SPIN := 27.0      # rad/s about local X
const GRAVITY := 11.0
const GRAVITY_DELAY := 0.34   # flat-and-fast first, then it starts to drop
const MAX_FLIGHT := 3.2
const THROW_DAMAGE := 42.0

# --- recall tuning
const RECALL_SPEED := 26.0
const RECALL_MIN_TIME := 0.30
const RECALL_MAX_TIME := 0.78
const RECALL_SPIN := 38.0
const RECALL_DAMAGE := 26.0
const RECALL_HIT_RADIUS := 0.62
const ARC_RATIO := 0.30       # elevated midpoint as a fraction of gap distance
const ARC_MIN := 0.85
const ARC_MAX := 3.40

# Grip pose in the hand socket (Basis.from_euler is not a constant expression,
# so these stay as a raw euler/offset pair).
#
# The yaw term matters visually: with zero yaw the bit points straight along the
# player's forward axis, which is directly away from an over-the-shoulder camera,
# so the axe renders edge-on as a thin sliver. Yawing it ~60 degrees presents the
# flat of the blade to the camera and the silhouette reads immediately.
const HOLD_ROT := Vector3(-0.18, -1.05, 0.13)
const HOLD_POS := Vector3(0.0, 0.09, 0.0)

const MASK_WORLD := 1
const MASK_ENEMY := 4

var state: State = State.EQUIPPED

var _player: Node3D
var _hand: Node3D
var _world_root: Node3D

var _vel := Vector3.ZERO
var _travel := Vector3.FORWARD
var _spin := 0.0
var _flight_time := 0.0

# recall bookkeeping
var _p0 := Vector3.ZERO
var _recall_t := 0.0
var _recall_dur := 0.5
var _recall_hit: Array = []
var _last_pos := Vector3.ZERO

var _runes: Array[MeshInstance3D] = []
var _rune_mats: Array[StandardMaterial3D] = []
var _rune_tween: Tween


func setup(player: Node3D, hand: Node3D, world_root: Node3D) -> void:
	_player = player
	_hand = hand
	_world_root = world_root
	var model: Node3D = load("res://assets/models/axe.glb").instantiate()
	add_child(model)
	_collect_runes(model)
	_attach_to_hand()


func _collect_runes(n: Node) -> void:
	if n is MeshInstance3D and String(n.name).contains("Rune"):
		var mi := n as MeshInstance3D
		# Duplicate the rune material ONCE here. Doing it inside _pulse_rune
		# would allocate a fresh material on every recall and leak GPU state.
		var src := mi.get_active_material(0)
		if src != null:
			var dup := src.duplicate()
			mi.material_override = dup
			if dup is StandardMaterial3D:
				_rune_mats.append(dup)
		_runes.append(mi)
	for c in n.get_children():
		_collect_runes(c)


# ---------------------------------------------------------------- state helpers

func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func can_throw() -> bool:
	return state == State.EQUIPPED


func can_recall() -> bool:
	return state in [State.AIRBORNE_THROW, State.EMBEDDED_WORLD,
			State.EMBEDDED_ENEMY]


func is_held() -> bool:
	return state == State.EQUIPPED


func _attach_to_hand() -> void:
	if get_parent() != _hand:
		if get_parent():
			reparent(_hand, false)
		else:
			_hand.add_child(self)
	transform = Transform3D(Basis.from_euler(HOLD_ROT), HOLD_POS)
	_set_state(State.EQUIPPED)


# ------------------------------------------------------------------------ throw

## `target` is the world point under the crosshair, so the throw converges on
## what the player is actually looking at rather than on raw camera forward.
func throw(from: Vector3, target: Vector3) -> void:
	if not can_throw():
		return
	reparent(_world_root, true)
	global_position = from
	_travel = (target - from)
	if _travel.length_squared() < 0.01:
		_travel = -_hand.global_transform.basis.z
	_travel = _travel.normalized()
	_vel = _travel * THROW_SPEED
	_spin = 0.0
	_flight_time = 0.0
	_last_pos = global_position
	global_transform = Transform3D(_flight_basis(_travel, 0.0), global_position)
	_set_state(State.AIRBORNE_THROW)
	Sfx.play_3d("throw_release", from, 1.0)
	Juice.add_trauma(0.09, _travel)


# ----------------------------------------------------------------------- recall

func recall() -> void:
	if not can_recall():
		return
	if get_parent() != _world_root:
		reparent(_world_root, true)
	_p0 = global_position
	_recall_t = 0.0
	_recall_hit.clear()
	var gap := _p0.distance_to(_hand_point())
	_recall_dur = clampf(gap / RECALL_SPEED, RECALL_MIN_TIME, RECALL_MAX_TIME)
	_set_state(State.RECALLING)
	Sfx.play_3d("recall_whistle", _p0, -1.0)
	_pulse_runes()


func _hand_point() -> Vector3:
	if is_instance_valid(_hand):
		return _hand.global_position
	return _player.global_position + Vector3.UP


## Cubic Bezier control points, rebuilt every frame because P3 (the hand) moves.
## P1 pulls backward out of the surface first -- the axe wrenches free instead of
## teleporting sideways -- then both midpoints are lifted so the return arcs over
## the arena rather than sliding along the floor.
func _bezier_points() -> Array:
	var p3 := _hand_point()
	var gap := _p0.distance_to(p3)
	var dir := (p3 - _p0)
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	var arc := clampf(gap * ARC_RATIO, ARC_MIN, ARC_MAX)
	var p1 := _p0 - dir * gap * 0.12 + Vector3.UP * arc
	var p2 := p3 - dir * gap * 0.30 + Vector3.UP * arc * 0.62
	return [_p0, p1, p2, p3]


static func _bezier(p: Array, t: float) -> Vector3:
	var u := 1.0 - t
	return (p[0] as Vector3) * (u * u * u) \
		+ (p[1] as Vector3) * (3.0 * u * u * t) \
		+ (p[2] as Vector3) * (3.0 * u * t * t) \
		+ (p[3] as Vector3) * (t * t * t)


# -------------------------------------------------------------------- per-frame

func _physics_process(delta: float) -> void:
	match state:
		State.AIRBORNE_THROW:
			_tick_flight(delta)
		State.RECALLING:
			_tick_recall(delta)
		_:
			pass


func _tick_flight(delta: float) -> void:
	_flight_time += delta
	if _flight_time > GRAVITY_DELAY:
		_vel.y -= GRAVITY * delta
	_travel = _vel.normalized()

	var from := global_position
	var to := from + _vel * delta
	# lead the cast by the blade reach so the cutting edge is what connects
	var probe := to + _travel * BLADE_REACH

	var hit := _cast(from, probe)
	if not hit.is_empty():
		_resolve_hit(hit)
		return

	global_position = to
	_spin += THROW_SPIN * delta
	global_transform = Transform3D(_flight_basis(_travel, _spin), to)

	if _flight_time > MAX_FLIGHT:
		_embed_in_air()


func _tick_recall(delta: float) -> void:
	_recall_t = minf(1.0, _recall_t + delta / _recall_dur)
	# accelerate into the catch: slow wrench-free, hard whip home
	var te: float = pow(_recall_t, 1.5)
	var pts := _bezier_points()
	var pos := _bezier(pts, te)

	_sweep_damage(_last_pos, pos)

	var tangent := pos - _last_pos
	if tangent.length_squared() > 0.000001:
		_travel = tangent.normalized()
	_last_pos = pos
	global_position = pos
	_spin += RECALL_SPIN * delta
	global_transform = Transform3D(_flight_basis(_travel, _spin), pos)

	if _recall_t >= 1.0:
		_catch()


## Damage anything the axe passes through on the way home.
func _sweep_damage(a: Vector3, b: Vector3) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e in _recall_hit or not is_instance_valid(e):
			continue
		if not e.has_method("take_hit"):
			continue
		var c: Vector3 = e.global_position + Vector3.UP * 0.9
		if _seg_dist(a, b, c) > RECALL_HIT_RADIUS:
			continue
		_recall_hit.append(e)
		var n := (c - a).normalized()
		e.take_hit(RECALL_DAMAGE, n, false)
		Fx.blood(_world_root, c, -n, 0.9)
		Sfx.play_3d("flesh", c, 0.0)
		Juice.impact(0.24, n, 0.10, 0.05)


static func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func _catch() -> void:
	_attach_to_hand()
	Sfx.play_2d("catch_metal", 1.5)
	Fx.rune_flash(_world_root, _hand_point())
	# short, sharp freeze so the catch lands with weight
	Juice.impact(0.30, -_travel, 0.14, 0.085)
	caught.emit()


# ------------------------------------------------------------------- collisions

func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK_WORLD | MASK_ENEMY
	q.collide_with_areas = false
	if is_instance_valid(_player) and _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _resolve_hit(hit: Dictionary) -> void:
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider = hit["collider"]

	if collider != null and collider.has_method("take_hit"):
		_embed_in_enemy(collider, point, normal)
	else:
		_embed_in_world(point, normal, collider)


func _embed_in_world(point: Vector3, normal: Vector3, collider) -> void:
	var b := _embed_basis(normal, _travel)
	# a little organic variation so repeated throws never look stamped
	b = b.rotated(b.z, randf_range(-0.20, 0.20))
	b = b.rotated(b.x, randf_range(-0.16, 0.06))
	global_transform = Transform3D(
		b, point + normal * (BLADE_REACH - EMBED_DEPTH))
	_set_state(State.EMBEDDED_WORLD)

	var wood := collider != null and String(collider.name).to_lower().contains("wood")
	Sfx.play_3d("embed_wood" if wood else "embed_stone", point, 2.0)
	Fx.sparks(_world_root, point, normal)
	Fx.dust(_world_root, point, normal)
	Juice.impact(0.34, -normal, 0.08, 0.055)


func _embed_in_enemy(enemy, point: Vector3, normal: Vector3) -> void:
	enemy.take_hit(THROW_DAMAGE, -normal, true)

	var anchor: Node3D = enemy
	if enemy.has_method("embed_anchor"):
		var a = enemy.embed_anchor()
		if a != null:
			anchor = a
	var b := _embed_basis(normal, _travel)
	b = b.rotated(b.z, randf_range(-0.16, 0.16))
	global_transform = Transform3D(
		b, point + normal * (BLADE_REACH - EMBED_DEPTH * 1.6))
	if is_instance_valid(anchor):
		reparent(anchor, true)
	_set_state(State.EMBEDDED_ENEMY)

	Sfx.play_3d("flesh", point, 2.0)
	Fx.blood(_world_root, point, normal, 1.35)
	# the meatiest impact in the game gets the full freeze
	Juice.impact(0.55, -normal, 0.05, 0.085)


## Nothing hit within range: stop where it is so the axe is never lost.
func _embed_in_air() -> void:
	var b := _embed_basis(Vector3.UP, _travel)
	global_transform = Transform3D(b, global_position)
	_set_state(State.EMBEDDED_WORLD)


# ------------------------------------------------------------------------ bases

## Flight orientation: local X becomes the horizontal spin axis, -Z leads along
## travel, then the tumble is applied about local X.
static func _flight_basis(travel: Vector3, spin: float) -> Basis:
	var t := travel.normalized()
	var x := t.cross(Vector3.UP)
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := -t
	var y := z.cross(x).normalized()
	return Basis(x, y, z) * Basis.from_euler(Vector3(spin, 0.0, 0.0))


## Embedded orientation: +Z along the surface normal (so -Z, the bit, points into
## the surface) with the haft lying in the surface plane, preferring upright.
static func _embed_basis(n: Vector3, travel: Vector3) -> Basis:
	var z := n.normalized()
	var y := Vector3.UP - z * Vector3.UP.dot(z)
	if y.length_squared() < 0.02:
		y = -(travel - z * travel.dot(z))
	if y.length_squared() < 0.02:
		y = Vector3.FORWARD
	y = y.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)


## Flare the runes when the recall is summoned. Reuses the materials duplicated
## in _collect_runes and reuses a single tween, so repeated recalls allocate
## nothing.
func _pulse_runes() -> void:
	if _rune_mats.is_empty():
		return
	if _rune_tween != null and _rune_tween.is_valid():
		_rune_tween.kill()
	_rune_tween = create_tween()
	_rune_tween.set_parallel(true)
	for m in _rune_mats:
		_rune_tween.tween_property(m, "emission_energy_multiplier", 13.0, 0.10)
	_rune_tween.chain()
	for m in _rune_mats:
		_rune_tween.tween_property(m, "emission_energy_multiplier", 7.0, 0.38)
