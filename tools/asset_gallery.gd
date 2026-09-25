extends Node3D
## Deterministic ingest preview for the six candidate production actors.
## Saves a rendered contact strip and prints the animation/skeleton contract.

const FILES := [
	"Barbarian.glb", "Knight.glb", "Skeleton_Warrior.glb",
	"Skeleton_Mage.glb", "Skeleton_Rogue.glb", "Skeleton_Minion.glb",
]

var _frames := 0


func _ready() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("101622")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("92a8ca")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46, -34, 0)
	key.light_color = Color("ffd7af")
	key.light_energy = 1.35
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 145, 0)
	rim.light_color = Color("71aaff")
	rim.light_energy = 0.8
	add_child(rim)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(19, 5)
	floor.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("27313c")
	fm.metallic = 0.15
	fm.roughness = 0.65
	floor.material_override = fm
	add_child(floor)

	for i in FILES.size():
		var path: String = "res://assets/production/actors/" + FILES[i]
		var packed: PackedScene = load(path)
		var actor: Node3D = packed.instantiate()
		actor.name = FILES[i].get_basename()
		actor.position = Vector3((i - 2.5) * 2.35, 0, 0)
		actor.rotation.y = PI
		add_child(actor)
		_audit_actor(actor, path)
		var ap := _find_animation_player(actor)
		if ap != null:
			var wanted: String = "Idle_Combat" if FILES[i].begins_with("Skeleton") else "2H_Melee_Idle"
			if not ap.has_animation(wanted):
				wanted = "Idle"
			if ap.has_animation(wanted):
				ap.play(wanted)

	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.05, 11.8)
	camera.look_at_from_position(camera.position, Vector3(0, 1.15, 0))
	camera.fov = 49.0
	camera.current = true
	add_child(camera)

	var ui := CanvasLayer.new()
	add_child(ui)
	var title := Label.new()
	title.text = "PRODUCTION ACTOR INGEST  •  KAYKIT CC0  •  RIG_MEDIUM"
	title.position = Vector2(38, 26)
	title.add_theme_font_override("font", load("res://assets/production/fonts/Cinzel-Variable.ttf"))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("dbe9ff"))
	ui.add_child(title)
	for i in FILES.size():
		var label := Label.new()
		label.text = FILES[i].get_basename().replace("_", " ")
		label.position = Vector2(60 + i * 203, 655)
		label.size = Vector2(190, 40)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", load("res://assets/production/fonts/AlegreyaSans-Regular.ttf"))
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("c3cede"))
		ui.add_child(label)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 90:
		if OS.has_feature("web"):
			print("[AssetGallery] READY")
			return
		var texture := get_viewport().get_texture()
		if texture == null:
			push_warning("Asset gallery has no render texture on the headless display driver")
			get_tree().quit()
			return
		var image := texture.get_image()
		var path := "res://artifacts/actor_gallery.png"
		var err := image.save_png(path)
		print("GALLERY_SAVE path=%s size=%dx%d err=%s" % [path, image.get_width(), image.get_height(), error_string(err)])
	elif _frames == 92 and not OS.has_feature("web"):
		get_tree().quit()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _audit_actor(actor: Node3D, path: String) -> void:
	var ap := _find_animation_player(actor)
	var sk := _find_skeleton(actor)
	var animations: PackedStringArray = ap.get_animation_list() if ap != null else PackedStringArray()
	print("ACTOR_CONTRACT file=%s anims=%d bones=%d root=%s" % [
		path, animations.size(), sk.get_bone_count() if sk != null else 0, actor.name])
	if sk != null:
		var names := PackedStringArray()
		for i in sk.get_bone_count():
			names.append(sk.get_bone_name(i))
		print("  BONES " + ",".join(names))
	var key_animations := PackedStringArray()
	for animation_name in animations:
		if "Idle" in animation_name or "Attack" in animation_name \
				or "Running" in animation_name or "Dodge" in animation_name \
				or "Throw" in animation_name or "Hit" in animation_name \
				or "Death" in animation_name:
			key_animations.append(animation_name)
	print("  KEY_ANIMS " + ",".join(key_animations))
