# test/unit/test_bot_blackboard.gd
# M3.2 T10（2026-08-17）：BotBlackboard 黑板测试（TDD，先 RED 后 GREEN）。
# 目标：极简键值存储（嵌套 Dictionary/Array/Vector3 写读一致）/
#   key_changed 信号（写入发、key 正确、同值重写仍发——无去重）/
#   has 语义 + clear 后全空 + clear 不发信号（订阅计数器不变）。
# RED 锚：生产类 BotBlackboard 尚不存在——本脚本引用该类即编译失败（错误信息 =
#   "Could not find type BotBlackboard" 类加载错误，即正确的 RED 失败原因）。
extends GutTest

var _changed_keys: Array = []  # key_changed 信号捕获


func _on_key_changed(key: String) -> void:
	_changed_keys.append(key)


func _make_board() -> BotBlackboard:
	var board := BotBlackboard.new()
	add_child_autofree(board)
	board.key_changed.connect(_on_key_changed)
	return board


# ── T10-1：嵌套 Dictionary/Array/Vector3 写读一致 + 缺键返回 default ──
func test_set_get_roundtrip() -> void:
	var board := _make_board()
	var nested := {
		"name": "echo",
		"stats": {"hp": 100.0, "armor": 2},
		"path": [Vector3(1, 2, 3), Vector3(4, 5, 6)],
		"pos": Vector3(7.5, -1.25, 0.0),
	}
	board.set_value("state", nested)
	var read: Dictionary = board.get_value("state")
	assert_eq(read["name"], "echo", "字符串写读一致")
	assert_eq(read["stats"]["hp"], 100.0, "嵌套 Dictionary 写读一致")
	assert_eq(read["path"][1], Vector3(4, 5, 6), "嵌套 Array 内 Vector3 写读一致")
	assert_eq(read["pos"], Vector3(7.5, -1.25, 0.0), "顶层 Vector3 写读一致")
	assert_eq(board.get_value("missing"), null, "缺键返回默认 null")
	assert_eq(board.get_value("missing", 42), 42, "缺键返回指定 default")


# ── T10-2：写入发 key_changed 且 key 正确；同值重写仍发（无去重）──
func test_key_changed_signal() -> void:
	_changed_keys.clear()  # 清基线：GUT 复用脚本实例，前序测试写入的信号会累积到本数组
	var board := _make_board()
	board.set_value("hostiles", [1, 2, 3])
	assert_eq(_changed_keys.size(), 1, "set_value 发一次 key_changed")
	assert_eq(_changed_keys[0], "hostiles", "信号携带正确 key")
	board.set_value("hostiles", [1, 2, 3])  # 同值重写
	assert_eq(_changed_keys.size(), 2, "同值重写仍发信号（无去重，订阅方自行幂等）")
	assert_eq(_changed_keys[1], "hostiles", "重写信号 key 不变")
	board.set_value("heard", "gunshot")
	assert_eq(_changed_keys.size(), 3, "异键写入继续发信号")
	assert_eq(_changed_keys[2], "heard", "新键信号 key 正确")


# ── T10-3：has 语义 + clear 后全空 + clear 不发信号（订阅计数器不变）──
func test_has_and_clear() -> void:
	var board := _make_board()
	assert_false(board.has("hostiles"), "未写入键 has=false")
	board.set_value("hostiles", ["a"])
	board.set_value("lkp", {"a": Vector3.ZERO})
	assert_true(board.has("hostiles"), "写入后 has=true")
	assert_true(board.has("lkp"), "多键 has 各自独立")
	_changed_keys.clear()  # 重置计数器：验证 clear 不再发信号
	board.clear()
	assert_false(board.has("hostiles"), "clear 后 has=false")
	assert_false(board.has("lkp"), "clear 后所有键移除")
	assert_eq(board.get_value("hostiles"), null, "clear 后读回默认 null")
	assert_eq(_changed_keys.size(), 0, "clear 不发信号（全量重建语义）")
