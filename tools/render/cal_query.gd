extends SceneTree

# Axis calibration query: load calibration.glb, report where the named
# empties (authored in Blender) land in Godot space. Confirms Blender->Godot map.
func _init() -> void:
	var path := "res://Assets/Models/calibration.glb"
	var ps: PackedScene = load(path)
	if ps == null:
		print("FAIL: could not load ", path)
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	for child in inst.get_children():
		print("child: ", child.name, " type=", child.get_class(), " pos=", (child as Node3D).position if child is Node3D else "n/a")
	for nm in ["CAL_TIP", "CAL_UP", "CAL_RIGHT"]:
		var n := inst.find_child(nm, true, false)
		if n and n is Node3D:
			print(nm, " -> Godot pos ", (n as Node3D).position)
		else:
			print(nm, " NOT FOUND")
	quit()
