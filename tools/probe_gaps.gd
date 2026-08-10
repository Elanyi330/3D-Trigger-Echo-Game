# tools/probe_gaps.gd（重写：纯几何计算，无需物理模拟）
# 问题3 量化：从 map_layout 数据表直接计算各 z 行的自由通道宽度（组件 AABB 投影）。
# 用法: godot --headless --path . -s res://tools/probe_gaps.gd
extends SceneTree

const LAYOUT := preload("res://Levels/M2_TDM/map_layout.gd")

const SCAN_Z := [-27.0, -20.0, -14.0, -10.0, -4.0, 0.0, 4.0, 10.0, 14.0, 20.0, 27.0]
const X_MIN := -29.0
const X_MAX := 29.0


func _initialize() -> void:
	for z in SCAN_Z:
		# 收集该 z 行所有阻挡的 x 区间（组件 AABB 在 z 方向覆盖该行）
		var blocked := []
		for e in LAYOUT.all_solids():
			var d: Dictionary = e
			var c: Vector3 = d["center"]
			var s: Vector3 = d["size"]
			if abs(z - c.z) <= s.z * 0.5:
				blocked.append([c.x - s.x * 0.5, c.x + s.x * 0.5])
		# 合并阻挡区间
		blocked.sort()
		var merged := []
		for iv in blocked:
			if merged.is_empty() or iv[0] > merged[-1][1]:
				merged.append([iv[0], iv[1]])
			else:
				merged[-1][1] = maxf(merged[-1][1], iv[1])
		# 求自由段（补集）
		var free := []
		var cur := X_MIN
		for iv in merged:
			if iv[0] > cur + 0.05:
				free.append([cur, minf(iv[0], X_MAX)])
			cur = maxf(cur, iv[1])
		if cur < X_MAX - 0.05:
			free.append([cur, X_MAX])
		# 输出
		for seg in free:
			var w: float = seg[1] - seg[0]
			var tag := ""
			if w < 3.0:
				tag = "  ⚠️ <3.0m（玩家 r0.5 双人并排会卡）"
			print("GAP z=%6.1f 通道 [%6.1f, %6.1f] 宽=%4.1f%s" % [z, seg[0], seg[1], w, tag])
	print("PROBE_GAPS_DONE")
	quit()
