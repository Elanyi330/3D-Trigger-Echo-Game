# Headless dump: map_layout_v3.gd all_solids() → JSON（stdout）。任务 9 B 扫描管线。
#   godot --headless --path . -s tools/dump_v3_solids.gd > /tmp/v3_solids.json
# 输出：单个 JSON 数组，每项 {"name","kind","cx","cy","cz","sx","sy","sz"}（扁平化，
# 避免 Vector3 不可 JSON 序列化）。供 tools/scan_gaps_v3.py 读取。
extends SceneTree

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")


func _initialize() -> void:
	var out := []
	for e0 in V3.all_solids():
		var e: Dictionary = e0
		var c: Vector3 = e["center"]
		var s: Vector3 = e["size"]
		out.append({
			"name": e["name"],
			"kind": e["kind"],
			"cx": c.x, "cy": c.y, "cz": c.z,
			"sx": s.x, "sy": s.y, "sz": s.z,
		})
	print(JSON.stringify(out))
	quit(0)
