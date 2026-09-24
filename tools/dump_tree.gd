# Dev tool: dump the imported node tree of each GLB so the swap is exact.
# Run: godot --headless --path . -s tools/dump_tree.gd
extends SceneTree


func _init() -> void:
	for f in ["res://assets/models/player.glb", "res://assets/models/draugr.glb",
			"res://assets/models/axe.glb", "res://assets/models/pillar.glb"]:
		var ps: PackedScene = load(f)
		if ps == null:
			print("FAILED TO LOAD: ", f)
			continue
		var inst := ps.instantiate()
		print("===", f)
		_dump(inst, 0)
		inst.queue_free()
	quit()


func _dump(n: Node, d: int) -> void:
	var extra := ""
	if n is Skeleton3D:
		var s := n as Skeleton3D
		extra = " [bones=%d: " % s.get_bone_count()
		for i in mini(s.get_bone_count(), 20):
			extra += s.get_bone_name(i) + ","
		extra += "]"
	elif n is MeshInstance3D:
		extra = " [mesh]"
	elif n is BoneAttachment3D:
		extra = " [bone=" + (n as BoneAttachment3D).bone_name + "]"
	print("  ".repeat(d) + "- " + n.name + " (" + n.get_class() + ")" + extra)
	for c in n.get_children():
		_dump(c, d + 1)
