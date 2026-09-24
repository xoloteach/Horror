extends SceneTree

func _init() -> void:
	for f in ["res://assets/models/player.glb", "res://assets/models/draugr.glb"]:
		var inst: Node3D = (load(f) as PackedScene).instantiate()
		var skel := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("===", f, " skel pos=", skel.position, " rot=", skel.rotation)
		for bname in ["UpperArm.R", "Chest", "Thigh.R", "Head", "Chest_2", "Head_2"]:
			var idx := skel.find_bone(bname)
			if idx == -1:
				continue
			var rest: Transform3D = skel.get_bone_global_rest(idx)
			var bx := rest.basis.x.normalized()
			var by := rest.basis.y.normalized()
			var bz := rest.basis.z.normalized()
			print("  ", bname, " origin=", rest.origin, " | X=", bx, " Y=", by, " Z=", bz)
		inst.queue_free()
	quit()
