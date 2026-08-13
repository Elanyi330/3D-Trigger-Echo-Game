# tools/export_jump_edges.gd
# T4 工具1（2026-08-13）：把 jump_edges.gd 的三个静态接口导出为 JSON，
# 供 tools/build_jump_dataset.py（人类语料校准 + 数据集构建）消费。
# 运行：godot --headless --path . -s tools/export_jump_edges.gd
# 输出：/tmp/jump_edges.json
#   {
#     "current_map_hash": JumpRecordCore.map_hash(LAYOUT.all_solids(), MOVEMENT_REV),
#     "faces":  [...jump_edges.faces()...],
#     "groups": [...jump_edges.face_edge_groups()...],   # zone center/size Vector2 → {x,z}
#     "links":  [...jump_edges.link_face_edges()...]
#   }
# Vector2(xz) 一律拆成 {"x","z"}（Godot JSON 不支持 Vector2；y 分量是 z 平面坐标，
# 字段名用 "z" 更清晰）。浮点 snappedf 到 0.001 位（与布局哈希 %.3f 口径一致），
# 消除 1 ULP 尾数噪声。只读消费 jump_edges.gd，不修改任何既有文件。
extends SceneTree

const JumpEdgesScript := preload("res://Levels/M2_TDM/jump_edges.gd")
const LayoutScript := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const RecordCoreScript := preload("res://Levels/M2_TDM/jump_record_core.gd")
const MovementScript := preload("res://Player/MovementController.gd")


static func _v2_dict(v: Vector2) -> Dictionary:
	return {"x": snappedf(v.x, 0.001), "z": snappedf(v.y, 0.001)}


static func _zone_dict(z: Dictionary) -> Dictionary:
	return {"center": _v2_dict(z["center"]), "size": _v2_dict(z["size"])}


static func _face_dict(f: Dictionary) -> Dictionary:
	return {
		"name": f["name"],
		"top_y": snappedf(float(f["top_y"]), 0.001),
		"center": _v2_dict(f["center"]),
		"size": _v2_dict(f["size"]),
	}


static func _group_dict(g: Dictionary) -> Dictionary:
	return {
		"from_face": g["from_face"],
		"to_face": g["to_face"],
		"delta_h": snappedf(float(g["delta_h"]), 0.001),
		"dist": snappedf(float(g["dist"]), 0.001),
		"link_names": g["link_names"],
		"takeoff_zone": _zone_dict(g["takeoff_zone"]),
		"landing_zone": _zone_dict(g["landing_zone"]),
	}


static func _link_dict(l: Dictionary) -> Dictionary:
	return {
		"link": l["link"],
		"from_face": l["from_face"],
		"to_face": l["to_face"],
		"delta_h": snappedf(float(l["delta_h"]), 0.001),
		"dist": snappedf(float(l["dist"]), 0.001),
	}


func _init() -> void:
	var out := {
		"current_map_hash": RecordCoreScript.map_hash(
				LayoutScript.all_solids(), MovementScript.MOVEMENT_REV),
		"faces": JumpEdgesScript.faces().map(_face_dict),
		"groups": JumpEdgesScript.face_edge_groups().map(_group_dict),
		"links": JumpEdgesScript.link_face_edges().map(_link_dict),
	}
	var f := FileAccess.open("/tmp/jump_edges.json", FileAccess.WRITE)
	if f == null:
		push_error("无法打开 /tmp/jump_edges.json 写入")
		quit(1)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("导出完成: faces=%d groups=%d links=%d" % [
		out["faces"].size(), out["groups"].size(), out["links"].size()])
	print("current_map_hash=%s" % out["current_map_hash"])
	quit(0)
