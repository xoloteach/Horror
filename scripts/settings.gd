extends Node
## Persistent audio and accessibility settings.

signal changed

const PATH := "user://midgard_fury.cfg"

var master_volume := 0.86
var music_volume := 0.72
var sfx_volume := 0.90
var shake_scale := 0.82
var hit_stop_enabled := true
var flash_scale := 0.80


func _ready() -> void:
	_load()
	apply()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	master_volume = float(config.get_value("audio", "master", master_volume))
	music_volume = float(config.get_value("audio", "music", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx", sfx_volume))
	shake_scale = float(config.get_value("accessibility", "shake", shake_scale))
	hit_stop_enabled = bool(config.get_value("accessibility", "hit_stop", hit_stop_enabled))
	flash_scale = float(config.get_value("accessibility", "flash", flash_scale))


func save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("accessibility", "shake", shake_scale)
	config.set_value("accessibility", "hit_stop", hit_stop_enabled)
	config.set_value("accessibility", "flash", flash_scale)
	config.save(PATH)


func apply() -> void:
	_set_bus("Master", master_volume)
	_set_bus("Music", music_volume)
	_set_bus("Sfx", sfx_volume)
	_set_bus("Voice", sfx_volume)
	_set_bus("UI", sfx_volume)
	changed.emit()


func _set_bus(name: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(name)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.001, 1.0)))


func set_master(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply()
	save()


func set_music(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply()
	save()


func set_sfx(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply()
	save()


func set_shake(value: float) -> void:
	shake_scale = clampf(value, 0.0, 1.0)
	save()
	changed.emit()


func set_hit_stop(enabled: bool) -> void:
	hit_stop_enabled = enabled
	save()
	changed.emit()


func set_flash(value: float) -> void:
	flash_scale = clampf(value, 0.0, 1.0)
	save()
	changed.emit()
