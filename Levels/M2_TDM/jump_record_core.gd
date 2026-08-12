## 跳跃记录纯逻辑核心（任务 13）——确定性序列化 / 布局哈希 / episode 分类 / manifest。
##
## 用户铁律（2026-08-11）：记录测试者跳上建筑的操作供未来 AI 学习；
## 地图每改动一次必须重置全部记录——以布局哈希为键自动作废老图数据。
## 全 static、无场景依赖、可单测；文件 IO 与场景胶水是任务 15 职责。
class_name JumpRecordCore


## 确定性序列化：按 name 字典序排序；每行 "name|kind|cx,cy,cz|sx,sy,sz"
## （浮点 3 位小数）；行以 \n 连接。与输入数组顺序无关。
static func serialize_solids(solids: Array) -> String:
	var lines := PackedStringArray()
	for solid in solids:
		lines.append(_serialize_line(solid))
	var sorted := Array(lines)
	# 主键 name 字典序；同名（布局保证唯一，此处兜底）按整行定全序，
	# 保证排序结果与输入顺序、排序稳定性均无关。
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var na: String = a.get_slice("|", 0)
		var nb: String = b.get_slice("|", 0)
		if na != nb:
			return na < nb
		return a < b)
	return "\n".join(sorted)


## SHA-256 十六进制（64 字符小写）——对 serialize_solids 结果取哈希，
## 作为布局指纹键：地图每改动一次此值即变，老图记录自动作废。
## movement_rev（X1）：移动机制修订标识——非空时序列化末尾追加一行
## "rev|<movement_rev>" 再哈希；移动语义变更（布局不变）也触发老录像作废。
## 空串保持旧行为（哈希与无参调用一致，兼容既有测试）。
static func map_hash(solids: Array, movement_rev: String = "") -> String:
	var text := serialize_solids(solids)
	if not movement_rev.is_empty():
		text += "\nrev|" + movement_rev
	return text.sha256_text()


## episode 分类：净升高 ≥0.5 → "climb"；起落同名面 → "fail"；其余 → "traverse"。
static func classify_episode(start_floor_y: float, end_floor_y: float,
		start_name: String, end_name: String) -> String:
	if end_floor_y - start_floor_y >= 0.5:
		return "climb"
	if start_name == end_name:
		return "fail"
	return "traverse"


## manifest 字典：{"map_hash": String, "map_name": String,
## "created_at": int(unix 秒), "episode_count": int}。
static func manifest_dict(map_hash_str: String, map_name: String,
		episode_count: int) -> Dictionary:
	return {
		"map_hash": map_hash_str,
		"map_name": map_name,
		"created_at": int(Time.get_unix_time_from_system()),
		"episode_count": episode_count,
	}


# ---- 内部 ----

## 单实体行："name|kind|cx,cy,cz|sx,sy,sz"（浮点 %.3f 三位小数，格式与区域无关）。
static func _serialize_line(solid: Dictionary) -> String:
	var c: Vector3 = solid["center"]
	var s: Vector3 = solid["size"]
	return "%s|%s|%s|%s" % [
		solid["name"], solid["kind"],
		"%.3f,%.3f,%.3f" % [c.x, c.y, c.z],
		"%.3f,%.3f,%.3f" % [s.x, s.y, s.z],
	]
