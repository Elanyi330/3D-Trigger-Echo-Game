# Headless probe: inspect Soldier_Echo skeleton (bones, rest poses, Hand positions).
#   godot --headless --path . -s tools/probe_skeleton.gd
extends SceneTree

func _initialize() -> void:
	var char: Node3D = load("res://Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb").instantiate()
	get_root().add_child(char)
	var skel: Skeleton3D = _find_skeleton(char)
	if skel == null:
		print("PROBE: NO Skeleton3D found!")
		quit()
		return
	print("PROBE: skeleton bones = %d" % skel.get_bone_count())
	for i in skel.get_bone_count():
		var nm := skel.get_bone_name(i)
		var rest: Transform3D = skel.get_bone_rest(i)
		print("  bone[%d] %s  rest_origin=%s" % [i, nm, _fmt(rest.origin)])
	# Hand_R / Hand_L global rest position (via global pose)
	for bn in ["Hand_R", "Hand_L", "Head", "Root"]:
		var idx := skel.find_bone(bn)
		if idx >= 0:
			var gp: Transform3D = skel.get_bone_global_rest(idx)
			print("  GLOBAL REST %s -> %s" % [bn, _fmt(gp.origin)])
	# bone local axes (rest basis) for arm chain — to compute weapon/arm pose rotations
	for bn in ["Shoulder_R", "UpperArm_R", "Forearm_R", "Hand_R", "Hand_L"]:
		var idx := skel.find_bone(bn)
		if idx >= 0:
			var gb: Basis = skel.get_bone_global_rest(idx).basis
			print("  AXES %s  X=%s Y=%s Z=%s" % [bn, _fmt(gb.x), _fmt(gb.y), _fmt(gb.z)])
	quit()

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func _fmt(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]
