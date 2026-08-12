# test/unit/test_jump_record_core.gd
# 任务 13：JumpRecordCore 跳跃记录纯逻辑核心（TDD RED 先行）。
# 用户铁律（2026-08-11）：记录测试者跳上建筑的操作供未来 AI 学习；
# 地图每改动一次必须重置全部记录——以布局哈希为键自动作废老图数据。
# 本文件测纯逻辑核心：确定性序列化 / 布局 SHA-256 / episode 分类 / manifest。
# 全 static 无场景依赖；文件 IO 与场景胶水是任务 15 职责，本任务不涉及。
extends GutTest

const V3 := preload("res://Levels/M2_TDM/map_layout_v3.gd")


# ---- 夹具：4 个假实体（name 唯一，name/kind/center/size 齐全） ----
func _fixture_solids() -> Array:
	return [
		{"name": "AlphaBox", "kind": "box",
			"center": Vector3(1.0, 2.5, -3.25), "size": Vector3(4.0, 0.5, 2.125)},
		{"name": "BetaRamp", "kind": "ramp",
			"center": Vector3(-0.75, 0.0, 10.0), "size": Vector3(1.5, 3.0, 6.0)},
		{"name": "GammaWall", "kind": "wall",
			"center": Vector3(0.0, 1.5, 0.0), "size": Vector3(0.2, 3.0, 12.5)},
		{"name": "DeltaTower", "kind": "tower",
			"center": Vector3(18.5, 2.75, -21.5), "size": Vector3(4.0, 5.5, 4.0)},
	]


# 同一实体集合、不同数组顺序（验证序列化与输入顺序无关）
func _fixture_shuffled() -> Array:
	return [
		{"name": "GammaWall", "kind": "wall",
			"center": Vector3(0.0, 1.5, 0.0), "size": Vector3(0.2, 3.0, 12.5)},
		{"name": "AlphaBox", "kind": "box",
			"center": Vector3(1.0, 2.5, -3.25), "size": Vector3(4.0, 0.5, 2.125)},
		{"name": "DeltaTower", "kind": "tower",
			"center": Vector3(18.5, 2.75, -21.5), "size": Vector3(4.0, 5.5, 4.0)},
		{"name": "BetaRamp", "kind": "ramp",
			"center": Vector3(-0.75, 0.0, 10.0), "size": Vector3(1.5, 3.0, 6.0)},
	]


# 复制实体并覆盖单键（不污染原夹具）
func _copy_with(solid: Dictionary, key: String, value: Variant) -> Dictionary:
	var d := solid.duplicate(true)
	d[key] = value
	return d


# ================= 1. 确定性序列化 =================
func test_serialize_deterministic() -> void:
	var a := JumpRecordCore.serialize_solids(_fixture_solids())
	var b := JumpRecordCore.serialize_solids(_fixture_shuffled())
	assert_eq(a, b, "同实体集正序/乱序输入 → 序列化结果完全相同")
	var lines := a.split("\n")
	assert_eq(lines.size(), 4, "4 实体 → 4 行（\\n 连接）")
	# 字典序：AlphaBox < BetaRamp < DeltaTower < GammaWall
	assert_eq(lines[0], "AlphaBox|box|1.000,2.500,-3.250|4.000,0.500,2.125",
			"已知实体行字符串精确值（name|kind|center|size，3 位小数）")
	assert_eq(lines[3].get_slice("|", 0), "GammaWall", "末行 name = 字典序最后")


# ================= 2. 哈希形状 =================
func test_hash_shape() -> void:
	var re := RegEx.new()
	re.compile("^[0-9a-f]{64}$")
	var h1 := JumpRecordCore.map_hash(_fixture_solids())
	var h2 := JumpRecordCore.map_hash(_fixture_solids())
	assert_not_null(re.search(h1), "map_hash 返回 64 字符小写十六进制")
	assert_eq(h1, h2, "同输入两次调用相等")


# ================= 3. 哈希敏感性（四组独立断言） =================
func test_hash_sensitivity() -> void:
	var base := JumpRecordCore.map_hash(_fixture_solids())
	# (a) 改任一 center 分量 0.001
	var s0 := _fixture_solids()
	s0[0] = _copy_with(s0[0], "center", Vector3(1.0, 2.501, -3.25))
	assert_ne(JumpRecordCore.map_hash(s0), base, "center 分量改 0.001 → 哈希变")
	# (b) 改 size 0.1
	var s1 := _fixture_solids()
	s1[1] = _copy_with(s1[1], "size", Vector3(1.5, 3.1, 6.0))
	assert_ne(JumpRecordCore.map_hash(s1), base, "size 改 0.1 → 哈希变")
	# (c) 增一个实体
	var s2 := _fixture_solids()
	s2.append({"name": "EpsilonNew", "kind": "box",
			"center": Vector3(0.0, 0.0, 0.0), "size": Vector3(1.0, 1.0, 1.0)})
	assert_ne(JumpRecordCore.map_hash(s2), base, "增一个实体 → 哈希变")
	# (d) 删一个实体
	var s3 := _fixture_solids()
	s3.remove_at(2)
	assert_ne(JumpRecordCore.map_hash(s3), base, "删一个实体 → 哈希变")


# ================= 4. episode 分类 =================
func test_classify_episode() -> void:
	assert_eq(JumpRecordCore.classify_episode(0.0, 0.6, "Ground", "Altar"), "climb",
			"净升高 0.6 ≥ 0.5 → climb")
	assert_eq(JumpRecordCore.classify_episode(0.0, 0.5, "Ground", "Altar"), "climb",
			"净升高恰 0.5 边界（≥）→ climb")
	assert_eq(JumpRecordCore.classify_episode(0.0, 0.4, "Ground", "Ground"), "fail",
			"净升高 0.4 < 0.5 且起落同名面 → fail")
	assert_eq(JumpRecordCore.classify_episode(0.0, 0.4, "Ground", "Altar"), "traverse",
			"净升高 0.4 异面名 → traverse")
	assert_eq(JumpRecordCore.classify_episode(1.2, 1.2, "Altar", "Altar"), "fail",
			"净升高 0.0 同面名 → fail")
	assert_eq(JumpRecordCore.classify_episode(3.0, 2.7, "Altar", "Ground"), "traverse",
			"跳下 -0.3 异面名 → traverse")


# ================= 5. manifest 字典 =================
func test_manifest_dict() -> void:
	var m := JumpRecordCore.manifest_dict("abc123", "EchoAltar", 7)
	assert_true(m.has_all(["map_hash", "map_name", "created_at", "episode_count"]),
			"四键齐全")
	assert_eq(m.keys().size(), 4, "恰四键")
	assert_eq(m["map_hash"], "abc123", "map_hash 透传")
	assert_eq(m["map_name"], "EchoAltar", "map_name 透传")
	assert_eq(m["episode_count"], 7, "episode_count 透传")
	assert_gt(m["created_at"], 0, "created_at 为 unix 秒 > 0")


# ================= 6. 真实布局序列化 =================
func test_serialize_real_layout() -> void:
	var solids: Array = V3.all_solids()
	var text := JumpRecordCore.serialize_solids(solids)
	var lines := text.split("\n")
	assert_eq(lines.size(), 189, "真实布局 189 实体 → 189 行")
	var first_name: String = lines[0].get_slice("|", 0)
	var last_name: String = lines[lines.size() - 1].get_slice("|", 0)
	assert_true(first_name <= last_name,
			"行首按字典序：首行 name ≤ 末行 name（%s ≤ %s）" % [first_name, last_name])
	var ordered := true
	for i in range(lines.size() - 1):
		if lines[i].get_slice("|", 0) > lines[i + 1].get_slice("|", 0):
			ordered = false
			break
	assert_true(ordered, "全部行 name 字典序非降")
	assert_eq(JumpRecordCore.map_hash(solids), JumpRecordCore.map_hash(V3.all_solids()),
			"真实布局两次调用 → 哈希稳定")


# ================= 7. 移动机制修订失效键（X1） =================
# 数据污染铁律补全：移动语义变更（step-up/空中控制）不改布局哈希，但跳跃操作
# 数据已不同——movement_rev 参与哈希，机制修订即自动作废旧录像。
func test_hash_movement_rev() -> void:
	var solids := _fixture_solids()
	var h_empty := JumpRecordCore.map_hash(solids)
	var h_r1 := JumpRecordCore.map_hash(solids, "move-r1")
	var h_r2 := JumpRecordCore.map_hash(solids, "move-r2:step0.62,air-rest3.0/run0.76")
	assert_ne(h_r1, h_r2, "同 solids 不同 rev → 哈希不同")
	assert_ne(h_empty, h_r1, "空 rev 与非空 rev → 哈希不同")
	assert_eq(JumpRecordCore.map_hash(solids, "move-r1"), h_r1, "同 solids 同 rev → 哈希相同")
	assert_eq(JumpRecordCore.map_hash(solids, ""), h_empty,
			"空串 rev 保持旧行为（与无参调用哈希一致）")
