extends Node
## Deterministic, browser-stepped, exactly-1,000-frame visual QA director.
##
## On Web, the game advances exactly one rendered simulation step only after the
## browser acknowledges that it captured the previous frame. Telemetry is
## exposed through window.__MF_QA and the browser writes __MF_QA_ACK. This removes
## timing drift and guarantees a one-to-one image/frame mapping.

const TOTAL_FRAMES := 1000
const MAIN := preload("res://scenes/Main.tscn")

var game: Node
var frame := 0
var stage := "TITLE"
var _web := false
var _waiting_for_capture := false
var _step_armed := false
var _release_actions := {}
var _seen_roles := {}
var _seen_boss := false
var _seen_victory := false
var _seen_restart := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	process_physics_priority = 1000
	_web = OS.has_feature("web")
	_spawn_game()
	Boot.touch_active = true
	if _web:
		JavaScriptBridge.eval("window.__MF_QA_ACK=-1;window.__MF_QA=null;", true)
		get_tree().paused = true
		_apply_timeline(0)
		_publish()
		_waiting_for_capture = true
	else:
		print("[VisualQA] HEADLESS START frames=%d" % TOTAL_FRAMES)


func _spawn_game() -> void:
	game = MAIN.instantiate()
	game.name = "ProductionGame"
	add_child(game)
	game.player.set_meta("qa_invulnerable", true)


func _process(_delta: float) -> void:
	if _web:
		_process_browser_step()
	else:
		_process_automatic_step()


func _process_browser_step() -> void:
	if frame >= TOTAL_FRAMES - 1 and _waiting_for_capture:
		return
	if _waiting_for_capture:
		var value: Variant = JavaScriptBridge.eval("Number(window.__MF_QA_ACK ?? -1)", true)
		var ack := int(value) if value != null else -1
		if ack < frame:
			return
		_waiting_for_capture = false
		_step_armed = true
		get_tree().paused = false
		return
	if _step_armed:
		# This callback runs after lower-priority production nodes, so exactly one
		# process/render step has elapsed since the browser's acknowledgment.
		get_tree().paused = true
		_step_armed = false
		frame += 1
		_apply_timeline(frame)
		_publish()
		_waiting_for_capture = true


func _process_automatic_step() -> void:
	frame += 1
	_apply_timeline(frame)
	if frame >= TOTAL_FRAMES - 1:
		_finalize()
		get_tree().quit(0 if _seen_boss and _seen_victory and _seen_restart else 1)


func _apply_timeline(current: int) -> void:
	_release_due_actions(current)
	stage = _stage_for(current)

	match current:
		10:
			game.hud.show_settings(true)
		30:
			game.hud._close_settings()
		40:
			game.start_run()
		55:
			Input.action_press("move_forward")
		92:
			Input.action_release("move_forward")
		100:
			_force_encounter(1)
		116:
			_present_nearest(2.2)
		130, 165, 200:
			_tap("attack_light", current)
		240:
			_tap("attack_heavy", current)
		278:
			_tap("dodge", current)
		310:
			_present_nearest(7.0)
		315:
			Input.action_press("aim")
		332:
			_tap("attack_light", current)
		380:
			_tap("recall", current)
		415:
			Input.action_release("aim")
		430:
			_kill_encounter()
		452:
			_choose_if_boon(0)
		470:
			_force_encounter(2)
		482:
			_present_formation()
		495, 530:
			_tap("attack_light", current)
		550:
			_kill_encounter()
		565:
			_force_encounter(3)
		578:
			_present_formation()
		615:
			_tap("dodge", current)
		635:
			_kill_encounter()
		653:
			_choose_if_boon(1)
		670:
			_force_encounter(4)
		685:
			_present_formation()
		700:
			_tap("attack_heavy", current)
		735:
			_kill_encounter()
		750:
			_force_encounter(5)
		764:
			_present_formation()
		780, 805:
			_tap("attack_light", current)
		818:
			_kill_encounter()
		833:
			_choose_if_boon(2)
		842:
			_force_encounter(6)
		858:
			_present_boss()
		875:
			_damage_boss_to_phase_two()
		905:
			_tap("dodge", current)
		930:
			_kill_encounter()
		956:
			_seen_victory = game.session_state == game.SessionState.VICTORY
		970:
			_restart_without_reloading_harness()

	_record_roles()


func _stage_for(current: int) -> String:
	if current < 40:
		return "TITLE_AND_SETTINGS"
	if current < 100:
		return "INTRO_AND_LOCOMOTION"
	if current < 310:
		return "COMBO_HEAVY_DODGE"
	if current < 430:
		return "AIM_THROW_EMBED_RECALL"
	if current < 565:
		return "WARRIOR_ROGUE"
	if current < 670:
		return "MAGE_PROJECTILE"
	if current < 750:
		return "HORDE"
	if current < 842:
		return "ELITE_GAUNTLET"
	if current < 930:
		return "BONE_JARL_BOSS"
	if current < 970:
		return "VICTORY_RESULTS"
	return "RESTARTED_TITLE"


func _force_encounter(number: int) -> void:
	if game == null or not is_instance_valid(game):
		return
	if game.session_state == game.SessionState.BOON:
		game.choose_boon((number - 1) % 3)
	_kill_existing_silently()
	game._start_encounter(number)


func _kill_existing_silently() -> void:
	game._spawn_queue.clear()
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr and not (node as Draugr).is_dead():
			(node as Draugr).take_hit(9999.0, Vector3.FORWARD, true)


func _kill_encounter() -> void:
	if game == null:
		return
	game._spawn_queue.clear()
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr and not (node as Draugr).is_dead():
			(node as Draugr).take_hit(9999.0, Vector3.FORWARD, true)


func _choose_if_boon(index: int) -> void:
	if game.session_state == game.SessionState.BOON:
		game.choose_boon(index)


func _present_nearest(distance: float) -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		return
	var enemy := enemies[0] as Draugr
	enemy.global_position = game.player.global_position + Vector3(0, 0, -distance)
	enemy.state = Draugr.State.PURSUE
	enemy.set_physics_process(true)


func _present_formation() -> void:
	var index := 0
	for node in get_tree().get_nodes_in_group("enemy"):
		if not node is Draugr:
			continue
		var enemy := node as Draugr
		var angle := -0.82 + index * 0.43
		var radius := 4.6 + float(index % 2) * 1.2
		enemy.global_position = game.player.global_position + Vector3(sin(angle) * radius, 0, -cos(angle) * radius)
		enemy.state = Draugr.State.PURSUE
		enemy.set_physics_process(true)
		index += 1


func _present_boss() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr and (node as Draugr).is_boss:
			var boss := node as Draugr
			boss.global_position = game.player.global_position + Vector3(0, 0, -5.7)
			boss.state = Draugr.State.PURSUE
			boss.set_physics_process(true)
			_seen_boss = true
			return


func _damage_boss_to_phase_two() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr and (node as Draugr).is_boss:
			var boss := node as Draugr
			boss.take_hit(boss.max_health * 0.56, Vector3.FORWARD, true)
			return


func _tap(action: String, current: int) -> void:
	Boot.press_action(action)
	_release_actions[action] = current + 2


func _release_due_actions(current: int) -> void:
	for action in _release_actions.keys():
		if int(_release_actions[action]) <= current:
			Boot.release_action(action)
			_release_actions.erase(action)


func _record_roles() -> void:
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Draugr:
			_seen_roles[(node as Draugr).archetype_name()] = true


func _restart_without_reloading_harness() -> void:
	get_tree().paused = false
	if game != null and is_instance_valid(game):
		remove_child(game)
		game.queue_free()
	_spawn_game()
	Boot.touch_active = true
	_seen_restart = game.session_state == game.SessionState.TITLE
	if _web:
		get_tree().paused = true


func _telemetry() -> Dictionary:
	var player_state := -1
	var axe_state := -1
	var encounter := 0
	var session := -1
	var hostiles := 0
	var player_pos := Vector3.ZERO
	if game != null and is_instance_valid(game):
		encounter = game.wave
		session = game.session_state
		hostiles = get_tree().get_nodes_in_group("enemy").size()
		if game.player != null and is_instance_valid(game.player):
			player_state = game.player.state
			player_pos = game.player.global_position
			if game.player.axe != null and is_instance_valid(game.player.axe):
				axe_state = game.player.axe.state
	return {
		"frame": frame,
		"stage": stage,
		"encounter": encounter,
		"session": session,
		"hostiles": hostiles,
		"player_state": player_state,
		"axe_state": axe_state,
		"player_x": snappedf(player_pos.x, 0.001),
		"player_y": snappedf(player_pos.y, 0.001),
		"player_z": snappedf(player_pos.z, 0.001),
		"seen_boss": _seen_boss,
		"seen_victory": _seen_victory,
		"seen_restart": _seen_restart,
		"done": frame >= TOTAL_FRAMES - 1,
	}


func _publish() -> void:
	var payload := _telemetry()
	JavaScriptBridge.eval("window.__MF_QA=%s;" % JSON.stringify(payload), true)
	if frame % 100 == 0 or frame == TOTAL_FRAMES - 1:
		print("[VisualQA] frame=%04d stage=%s encounter=%d hostiles=%d" % [
			frame, stage, payload["encounter"], payload["hostiles"]])


func _finalize() -> void:
	print("[VisualQA] COMPLETE frames=%d boss=%s victory=%s restart=%s roles=%s" % [
		TOTAL_FRAMES, _seen_boss, _seen_victory, _seen_restart,
		", ".join(_seen_roles.keys())])
