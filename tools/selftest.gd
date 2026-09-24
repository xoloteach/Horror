extends Node3D
## Headless functional test for the axe pipeline.
##
## Boots a real arena + player, then drives the throw / embed / recall cycle
## programmatically and asserts on measurable outcomes: does the axe actually
## reach EMBEDDED_WORLD, is the bit buried to the intended depth rather than
## floating or sunk, does the recall Bezier genuinely arc above both endpoints,
## does hit-stop collapse and restore Engine.time_scale.
##
## Run: godot --headless --rendering-driver opengl3 res://scenes/SelfTest.tscn

var arena: Arena
var player: Player
var axe: LeviathanAxe
var draugr: Draugr

var _phase := 0
var _frames := 0
var _phase_frames := 0
var _results: Array = []

var _recall_pts: Array[Vector3] = []
var _recall_start := Vector3.ZERO
var _embed_pos := Vector3.ZERO
var _enemy_hp_before := 0.0
var _ts_seen_low := false


func _ready() -> void:
	arena = Arena.new()
	add_child(arena)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	axe = player.axe
	print("\n=== MIDGARD FURY :: headless self-test ===")


func _check(ok: bool, label: String, detail := "") -> void:
	_results.append([ok, label, detail])
	var tag := "PASS" if ok else "FAIL"
	var line := "  [%s] %s" % [tag, label]
	if detail != "":
		line += "   (%s)" % detail
	print(line)


func _next(p: int) -> void:
	_phase = p
	_phase_frames = 0


func _physics_process(delta: float) -> void:
	_frames += 1
	_phase_frames += 1
	if Engine.time_scale < 0.9:
		_ts_seen_low = true

	match _phase:
		0:  # settle on the floor
			if _phase_frames > 40:
				_check(player.is_on_floor(), "player rests on arena floor",
						"y=%.3f" % player.global_position.y)
				_check(axe != null and axe.state == LeviathanAxe.State.EQUIPPED,
						"axe starts EQUIPPED")
				_check(axe.get_parent() == player.hand,
						"axe is parented to the hand socket",
						str(axe.get_parent().name))
				_next(1)

		1:  # throw at the perimeter wall
			var from := player.hand.global_position
			axe.throw(from, Vector3(20.0, 2.2, 0.0))
			_check(axe.state == LeviathanAxe.State.AIRBORNE_THROW,
					"throw enters AIRBORNE_THROW")
			_next(2)

		2:  # wait for the bite
			if axe.state != LeviathanAxe.State.AIRBORNE_THROW:
				_embed_pos = axe.global_position
				_check(axe.state == LeviathanAxe.State.EMBEDDED_WORLD,
						"axe embeds in world geometry",
						"state=%d after %d frames" % [axe.state, _phase_frames])
				_verify_embed_depth()
				_next(3)
			elif _phase_frames > 300:
				_check(false, "axe embeds in world geometry", "still airborne")
				_next(5)

		3:  # recall, sampling the curve
			_recall_start = axe.global_position
			_recall_pts.clear()
			axe.recall()
			_check(axe.state == LeviathanAxe.State.RECALLING,
					"recall enters RECALLING")
			_next(4)

		4:
			_recall_pts.append(axe.global_position)
			if axe.state == LeviathanAxe.State.EQUIPPED:
				_verify_recall_curve()
				_check(axe.get_parent() == player.hand,
						"axe re-parents to the hand on catch")
				_next(5)
			elif _phase_frames > 200:
				_check(false, "recall completes", "stuck in state %d" % axe.state)
				_next(5)

		5:  # spawn a stationary draugr and bury the axe in it
			draugr = Draugr.new()
			add_child(draugr)
			draugr.global_position = Vector3(0, 0.2, -7.0)
			draugr.set_player(null)   # keep it still for a deterministic hit
			_next(6)

		6:
			if _phase_frames > 30:
				_enemy_hp_before = draugr.health
				axe.throw(player.hand.global_position,
						draugr.global_position + Vector3.UP * 1.05)
				_next(7)

		7:
			if axe.state != LeviathanAxe.State.AIRBORNE_THROW:
				_check(axe.state == LeviathanAxe.State.EMBEDDED_ENEMY,
						"axe embeds in the draugr",
						"state=%d" % axe.state)
				_check(draugr.health < _enemy_hp_before,
						"throw damages the draugr",
						"%.0f -> %.0f" % [_enemy_hp_before, draugr.health])
				_check(_is_descendant_of(axe, draugr),
						"axe re-parents onto the draugr body")
				_next(8)
			elif _phase_frames > 300:
				_check(false, "axe embeds in the draugr", "never connected")
				_next(9)

		8:  # recall out of the body
			if _phase_frames == 20:
				axe.recall()
			elif _phase_frames > 20 and axe.state == LeviathanAxe.State.EQUIPPED:
				_check(true, "recall retrieves the axe from a body")
				_next(9)
			elif _phase_frames > 220:
				_check(false, "recall retrieves the axe from a body",
						"state %d" % axe.state)
				_next(9)

		9:  # hit-stop behaviour
			Juice.hit_stop(0.05, 0.08)
			_next(10)

		10:
			if _phase_frames == 1:
				_check(is_equal_approx(Engine.time_scale, 0.05),
						"hit-stop collapses time_scale",
						"scale=%.3f" % Engine.time_scale)
			if _phase_frames > 40:
				_check(is_equal_approx(Engine.time_scale, 1.0),
						"hit-stop restores time_scale",
						"scale=%.3f" % Engine.time_scale)
				_next(11)

		11:
			_check(_ts_seen_low,
					"impacts triggered hit-stop during play")
			_summary()


func _verify_embed_depth() -> void:
	# cast along the axe's own blade axis; the surface should sit exactly
	# (BLADE_REACH - EMBED_DEPTH) ahead of the origin
	var origin := axe.global_position
	var dir := -axe.global_transform.basis.z.normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 3.0)
	q.collision_mask = 1   # world geometry only
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_check(false, "blade is seated in the surface", "no surface ahead of bit")
		return
	var d: float = origin.distance_to(hit["position"])
	var want: float = LeviathanAxe.BLADE_REACH - LeviathanAxe.EMBED_DEPTH
	_check(absf(d - want) < 0.06,
			"bit buried to the intended depth (no float, no clip)",
			"surface at %.3fm, expected %.3fm" % [d, want])

	var up_dot: float = axe.global_transform.basis.y.dot(Vector3.UP)
	_check(up_dot > 0.2,
			"haft hangs plausibly rather than upside down",
			"haft-up dot = %.2f" % up_dot)


func _verify_recall_curve() -> void:
	if _recall_pts.size() < 4:
		_check(false, "recall produced a sampled path",
				"%d samples" % _recall_pts.size())
		return
	var p_end: Vector3 = _recall_pts[_recall_pts.size() - 1]
	var max_y := -1e9
	for p in _recall_pts:
		max_y = maxf(max_y, p.y)
	var ends_max: float = maxf(_recall_start.y, p_end.y)
	_check(max_y > ends_max + 0.25,
			"recall arcs above both endpoints (elevated midpoint)",
			"peak %.2f vs endpoints %.2f" % [max_y, ends_max])

	# no teleports: every step should be a plausible single-frame distance
	var max_step := 0.0
	for i in range(1, _recall_pts.size()):
		max_step = maxf(max_step, _recall_pts[i].distance_to(_recall_pts[i - 1]))
	_check(max_step < 2.0, "recall path is continuous (no teleport)",
			"largest step %.3fm" % max_step)

	# the path should be meaningfully longer than a straight line = it curves
	var straight: float = _recall_start.distance_to(p_end)
	var travelled := 0.0
	for i in range(1, _recall_pts.size()):
		travelled += _recall_pts[i].distance_to(_recall_pts[i - 1])
	var ratio: float = travelled / maxf(straight, 0.001)
	_check(ratio > 1.04,
			"recall follows a curve, not a straight line",
			"path/chord = %.3f" % ratio)
	print("      recall: %d samples, %.2fm over %.2fm chord, peak y %.2f"
			% [_recall_pts.size(), travelled, straight, max_y])


func _is_descendant_of(node: Node, root: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false


func _summary() -> void:
	var pass_n := 0
	var fail: Array = []
	for r in _results:
		if r[0]:
			pass_n += 1
		else:
			fail.append(r[1])
	print("\n--- self-test summary ---")
	print("  %d/%d checks passed" % [pass_n, _results.size()])
	if fail.is_empty():
		print("  ALL CHECKS PASSED")
	else:
		print("  FAILED: %s" % ", ".join(fail))
	print("=========================\n")
	get_tree().quit(0 if fail.is_empty() else 1)
