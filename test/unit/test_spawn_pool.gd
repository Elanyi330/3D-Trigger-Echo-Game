# test/unit/test_spawn_pool.gd
# TDM 营地点数池（2026-08-13，TDD RED 先行）：
# 需求：每营 10 个随机刷新点，角色只在"当前无其他角色占用"的点位出现，
#       保证所有角色随机刷新时不会挤在一起。
# 断言：
#   1. 5 次 acquire 不重复（5 角色 10 点恒不重叠）
#   2. acquire 幂等——同一 owner 重复 acquire 返回原有点
#   3. release 后该点可被再次 acquire；release 未知 owner 无操作
#   4. 全占满后再 acquire → 防御回退（warning 路径，返回 points[0] 且不破坏占用）
extends GutTest

const POOL := preload("res://Levels/M2_TDM/spawn_pool.gd")


func test_acquire_no_overlap() -> void:
	var pool = POOL.new()
	var pts := []
	for x in range(10):
		pts.append(Vector3(x, 0, 0))
	pool.setup(pts)
	var got := {}
	for i in range(5):
		var o := Node.new()
		o.name = "owner%d" % i
		var p: Vector3 = pool.acquire(o)
		assert_false(got.has(p), "5 次 acquire 点不得重复")
		got[p] = true
	assert_eq(pool.occupied_count(), 5, "占用数 = 5")
	assert_eq(pool.free_count(), 5, "空点 = 5")


func test_acquire_idempotent() -> void:
	var pool = POOL.new()
	pool.setup([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var o := Node.new()
	var p1: Vector3 = pool.acquire(o)
	var p2: Vector3 = pool.acquire(o)
	assert_eq(p1, p2, "同一 owner 重复 acquire 返回原有点")
	assert_eq(pool.occupied_count(), 1, "幂等不重复占点")


func test_release_then_reacquire() -> void:
	var pool = POOL.new()
	pool.setup([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var o1 := Node.new()
	var o2 := Node.new()
	var p1: Vector3 = pool.acquire(o1)  # o1 占的点随机（(1,0,0) 或 (2,0,0)）
	pool.acquire(o2)
	pool.release(o1)
	assert_eq(pool.free_count(), 1, "释放后空点 +1")
	var o3 := Node.new()
	var p: Vector3 = pool.acquire(o3)
	assert_eq(p, p1, "新 owner 拿到释放的点（即 o1 原占点）")
	assert_eq(pool.occupied_count(), 2, "占用数恢复 2")


func test_release_unknown_owner_noop() -> void:
	var pool = POOL.new()
	pool.setup([Vector3(1, 0, 0)])
	pool.acquire(Node.new())
	pool.release(Node.new())
	assert_eq(pool.free_count(), 0, "release 未知 owner 无操作")
	assert_eq(pool.occupied_count(), 1, "占用不变")


func test_acquire_when_full_defensive() -> void:
	var pool = POOL.new()
	pool.setup([Vector3(1, 0, 0)])
	pool.acquire(Node.new())
	var p: Vector3 = pool.acquire(Node.new())
	assert_eq(p, Vector3(1, 0, 0), "空池回退 points[0]（防御路径）")
	assert_eq(pool.occupied_count(), 1, "回退不破坏占用表")
