extends SceneTree
const CharRig = preload("res://scripts/rig.gd")

func _init() -> void:
	# 1) skeleton pose override: do children follow?
	var inst: Node3D = (load("res://assets/models/player.glb") as PackedScene).instantiate()
	var rig := CharRig.from_node(inst)
	print("is_skeleton: ", rig.is_skeleton())
	var skel := inst.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hand_i := skel.find_bone("Hand.R")
	var fore_i := skel.find_bone("ForeArm.R")
	var hand_before: Vector3 = skel.get_bone_global_pose(hand_i).origin
	var fore_before: Vector3 = skel.get_bone_global_pose(fore_i).origin
	rig.set_arm("R", -1.0)
	var hand_after: Vector3 = skel.get_bone_global_pose(hand_i).origin
	var fore_after: Vector3 = skel.get_bone_global_pose(fore_i).origin
	print("hand moved: ", hand_before.distance_to(hand_after) > 0.05, " (", hand_before, " -> ", hand_after, ")")
	print("forearm followed: ", fore_before.distance_to(fore_after) > 0.05, " (", fore_before, " -> ", fore_after, ")")
	var hs := rig.hand_socket()
	print("hand_socket: ", hs.name, " class=", hs.get_class())
	var cs := rig.chest_attachment()
	print("chest_attachment: ", cs.name if cs != null else "null")
	# 2) axe adapter: blade should face -Z after inner rotation.y=PI/2
	var axe: Node3D = (load("res://assets/models/axe.glb") as PackedScene).instantiate()
	var inner := Node3D.new()
	inner.rotation.y = PI * 0.5
	inner.add_child(axe)
	var root := Node3D.new()
	root.add_child(inner)
	var emit := root.find_child("Socket_Emit", true, false) as Node3D
	print("Socket_Emit local-in-root: ", root.global_transform.affine_inverse() * (emit as Node3D).global_position if emit else "MISSING")
	inst.queue_free()
	quit()
