# CharRig: unified animation interface over the real GLB skeletons
# (Skeleton3D driven by global pose overrides + BoneAttachment3D sockets)
# and the procedural placeholder rigs (plain Node3D pivots).
# All rotations are absolute X-axis swings in character space (faces -Z),
# matching the placeholder rig's pivot convention exactly.
class_name CharRig
extends RefCounted

var root: Node3D

var _skel: Skeleton3D = null
var _bone := {}   # logical name -> skeleton bone idx
var _node := {}   # placeholder mode: logical name -> Node3D pivot
var _vals := {}   # logical name -> last set X angle (both modes)

# logical -> candidate bone names (player.glb renames Chest/Head to *_2)
const _BONE_NAMES := {
	"torso": ["Chest", "Chest_2"],
	"head": ["Head", "Head_2"],
	"arm_L": ["UpperArm.L"],
	"arm_R": ["UpperArm.R"],
	"leg_L": ["Thigh.L"],
	"leg_R": ["Thigh.R"],
}

# placeholder rig node paths, by logical name
const _PLACEHOLDER_PATHS := {
	"torso": "Hips/Torso",
	"head": "Hips/Torso/HeadPivot",
	"arm_L": "Hips/Torso/ArmL",
	"arm_R": "Hips/Torso/ArmR",
	"leg_L": "LegL",
	"leg_R": "LegR",
}


static func from_node(r: Node3D) -> CharRig:
	var c := CharRig.new()
	c.root = r
	var skels := r.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		c._skel = skels[0] as Skeleton3D
		for logical in _BONE_NAMES:
			for bname in _BONE_NAMES[logical]:
				var idx := c._skel.find_bone(bname)
				if idx != -1:
					c._bone[logical] = idx
					break
			c._vals[logical] = 0.0
	else:
		for logical in _PLACEHOLDER_PATHS:
			var n := r.get_node_or_null(_PLACEHOLDER_PATHS[logical]) as Node3D
			if n != null:
				c._node[logical] = n
				c._vals[logical] = n.rotation.x
	return c


func is_skeleton() -> bool:
	return _skel != null


func _pose(logical: String, x: float) -> void:
	_vals[logical] = x
	if _skel != null:
		if not _bone.has(logical):
			return
		var idx: int = _bone[logical]
		var rest: Transform3D = _skel.get_bone_global_rest(idx)
		# Rotate around the skeleton-space lateral axis at the bone's rest
		# origin; children (forearm/hand) follow the overridden parent pose.
		var t := Transform3D(Basis(Vector3.RIGHT, x) * rest.basis, rest.origin)
		_skel.set_bone_global_pose_override(idx, t, 1.0, true)
	elif _node.has(logical):
		(_node[logical] as Node3D).rotation.x = x


func _val(logical: String) -> float:
	return float(_vals.get(logical, 0.0))


func set_torso(x: float) -> void:
	_pose("torso", x)


func get_torso() -> float:
	return _val("torso")


func set_head(x: float) -> void:
	_pose("head", x)


func get_head() -> float:
	return _val("head")


func set_arm(side: String, x: float) -> void:
	_pose("arm_" + side, x)


func get_arm(side: String) -> float:
	return _val("arm_" + side)


func set_leg(side: String, x: float) -> void:
	_pose("leg_" + side, x)


func get_leg(side: String) -> float:
	return _val("leg_" + side)


func _attachment(bone_names: Array) -> BoneAttachment3D:
	if _skel == null:
		return null
	for a in root.find_children("*", "BoneAttachment3D", true, false):
		var ba := a as BoneAttachment3D
		if ba != null and bone_names.has(ba.bone_name):
			return ba
	return null


# Socket that tracks the right hand (axe grip). Null in placeholder mode
# (caller falls back to the Hips/Torso/ArmR/HandSocket node path).
func hand_attachment() -> BoneAttachment3D:
	return _attachment(["Hand.R"])


# Socket that tracks the chest (axe embed point). Null in placeholder mode.
func chest_attachment() -> BoneAttachment3D:
	return _attachment(["Chest", "Chest_2"])


# Public socket for the axe grip: bone attachment on real rigs,
# HandSocket node on the placeholder.
func hand_socket() -> Node3D:
	var ba := hand_attachment()
	if ba != null:
		return ba
	var n := root.get_node_or_null("Hips/Torso/ArmR/HandSocket") as Node3D
	return n if n != null else root
