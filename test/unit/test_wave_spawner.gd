# test/unit/test_wave_spawner.gd
# 任务 11（TDD RED）：WaveSpawner 波次刷新逻辑测试先行。
#
# 需求：地图可踏足建筑表面（standable_surfaces() 数据驱动）随机刷 5 个敌人，
# 全灭后 RESPAWN_DELAY 秒再刷下一波 5 个，循环。WaveSpawner 不依赖 Enemy 类——
# 敌人由 spawn_fn 闭包依赖注入创建（L_M2 负责实例化 Enemy 并 add_child）。
#
# RED 状态：WaveSpawner 尚不存在（T12 实现于 Levels/M2_TDM/wave_spawner.gd，
# class_name WaveSpawner extends Node）。本文件不直接引用 WaveSpawner 标识符
# （避免解析期编译错误），运行时按 class_name 全局类清单/计划路径查找脚本，
# 找不到 → 8 个用例全部以"类缺失"失败；找到后按行为断言。
#
# 接口契约（T12 按此实现；测试镜像其常量与签名）：
#   signal wave_started(wave_n: int) / enemies_left(count: int) / wave_cleared(wave_n: int)
#   const WAVE_SIZE := 5 / RESPAWN_DELAY := 1.5 / MAX_PER_SURFACE := 2
#   const MIN_SPACING := 2.0 / SPAWN_MARGIN := 0.5
#   func setup(surfaces: Array, spawn_fn: Callable, exclusions: Dictionary = {},
#              respawn_delay: float = RESPAWN_DELAY) -> void
#   func start() -> void; func current_wave() -> int; func alive_count() -> int
extends GutTest

# ---- 契约常量镜像（WaveSpawner 侧同名 const，T12 实现）----
const EXPECT_WAVE_SIZE := 5
const EXPECT_MAX_PER_SURFACE := 2
const EXPECT_MIN_SPACING := 2.0
const EXPECT_SPAWN_MARGIN := 0.5

# T12 实现路径（计划指定）；优先按 class_name 全局类查找，与路径解耦
const SPAWNER_PATH := "res://Levels/M2_TDM/wave_spawner.gd"


## 测试桩敌人：brief 约定（Node + died 信号 + take_damage→died + 记录生成位）
class StubEnemy extends Node:
	signal died
	var health := 100.0
	var spawn_pos: Vector3        # 记录 WaveSpawner 传入的生成位
	var surface_name: String = "" # 记录所属刷怪面（组合多样性断言用）
	var _fired := false

	func take_damage(d: float) -> void:
		health -= d
		if health <= 0.0 and not _fired:
			_fired = true
			died.emit()


# ---- 假刷怪面 ×3（standable_surfaces() schema：{"name","center"(y=top_y),"size","top_y"}）----
# 面 A 中心在原点 → 排除矩形世界坐标 == 面中心局部坐标（消歧义）；三面相距远 →
# 敌间最小距离断言不受跨面组合干扰。容量：每面 ≥2（≤MAX_PER_SURFACE）足够凑 5 敌。
var SURFACES: Array = [
	{"name": "A", "center": Vector3(0, 1.2, 0), "size": Vector3(8, 0.1, 8), "top_y": 1.2},
	{"name": "B", "center": Vector3(20, 2.5, 0), "size": Vector3(4, 0.1, 4), "top_y": 2.5},
	{"name": "C", "center": Vector3(-20, 0.6, 10), "size": Vector3(6, 0.1, 6), "top_y": 0.6},
]

var spawned: Array = []      # 全部波次生成的 StubEnemy（按生成顺序）
var wave_log: Array = []     # wave_started(wave_n) 记录
var left_log: Array = []     # enemies_left(count) 记录
var cleared_log: Array = []  # wave_cleared(wave_n) 记录


func before_each() -> void:
	spawned = []
	wave_log = []
	left_log = []
	cleared_log = []


## spawn_fn 注入闭包：实例化 StubEnemy（add_child_autofree）、记 spawn_pos、收集并返回
func _spawn_fn(surface: Dictionary, pos: Vector3) -> Node:
	var e := StubEnemy.new()
	e.spawn_pos = pos
	e.surface_name = str(surface["name"])
	add_child_autofree(e)
	spawned.append(e)
	return e


func _load_spawner_script() -> Script:
	# 优先 class_name 全局类（与实现路径解耦），其次计划指定路径
	for entry in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == "WaveSpawner":
			var res: Resource = load(str(entry["path"]))
			if res is Script:
				return res
	if ResourceLoader.exists(SPAWNER_PATH):
		var res2: Resource = load(SPAWNER_PATH)
		if res2 is Script:
			return res2
	return null


func _make_spawner() -> Node:
	var script := _load_spawner_script()
	if script == null:
		fail_test("RED：WaveSpawner 不存在——T12 将实现 Levels/M2_TDM/wave_spawner.gd（class_name WaveSpawner extends Node）")
		return null
	var s = script.new()
	add_child_autofree(s)
	return s


func _hook_spawner_signals(s: Node) -> void:
	s.wave_started.connect(func(n: int): wave_log.append(n))
	s.enemies_left.connect(func(c: int): left_log.append(c))
	s.wave_cleared.connect(func(n: int): cleared_log.append(n))


## 轮询等待条件成立（跨帧），超时返回 false
func _wait_until_bool(cond: Callable, timeout: float) -> bool:
	var waited := 0.0
	while not bool(cond.call()):
		if waited >= timeout:
			return false
		await wait_seconds(0.02)
		waited += 0.02
	return true


func _surface_by_name(n: String) -> Dictionary:
	for s in SURFACES:
		if s["name"] == n:
			return s
	return {}


func _kill_range(from: int, to: int) -> void:
	for i in range(from, to):
		spawned[i].take_damage(999.0)


# ---- 1. 波大小与撒点位置：恰 5 敌；y == 面 top_y；位置在面内（含 SPAWN_MARGIN 边距）----
func test_wave_size_and_positions() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn)
	s.start()
	var ok: bool = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE, 2.0)
	assert_true(ok, "start() 后 2s 内应刷出恰 5 个敌人")
	assert_eq(spawned.size(), EXPECT_WAVE_SIZE, "每波恰 WAVE_SIZE=5 敌")
	for stub in spawned:
		var surf := _surface_by_name(stub.surface_name)
		assert_false(surf.is_empty(), "敌人所属面 %s 应在假面清单内" % stub.surface_name)
		if surf.is_empty():
			continue
		assert_almost_eq(stub.spawn_pos.y, float(surf["top_y"]), 0.001,
				"敌人 y 应 == 所属面 top_y（面 %s）" % stub.surface_name)
		var c: Vector3 = surf["center"]
		var sz: Vector3 = surf["size"]
		var half_x: float = sz.x * 0.5 - EXPECT_SPAWN_MARGIN
		var half_z: float = sz.z * 0.5 - EXPECT_SPAWN_MARGIN
		assert_lte(absf(stub.spawn_pos.x - c.x), half_x + 0.001,
				"x 应在面内（|x−center.x| ≤ size.x/2−SPAWN_MARGIN）")
		assert_lte(absf(stub.spawn_pos.z - c.z), half_z + 0.001,
				"z 应在面内（|z−center.z| ≤ size.z/2−SPAWN_MARGIN）")


# ---- 2. 每面每波上限：杀完刷 10 波，任何一波内单面 ≤ MAX_PER_SURFACE ----
func test_max_per_surface() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn, {}, 0.1)
	s.start()
	var prev := 0
	for w in range(1, 11):
		var ok: bool = await _wait_until_bool(func(): return spawned.size() >= prev + EXPECT_WAVE_SIZE, 3.0)
		assert_true(ok, "第 %d 波应在限时内刷出" % w)
		if not ok:
			return
		var counts := {}
		for i in range(prev, prev + EXPECT_WAVE_SIZE):
			var nm: String = spawned[i].surface_name
			counts[nm] = int(counts.get(nm, 0)) + 1
		for k in counts:
			assert_lte(int(counts[k]), EXPECT_MAX_PER_SURFACE,
					"第 %d 波面 %s 敌数 %d ≤ MAX_PER_SURFACE=2" % [w, k, counts[k]])
		_kill_range(prev, prev + EXPECT_WAVE_SIZE)
		prev += EXPECT_WAVE_SIZE


# ---- 3. 敌间最小水平距离：同一波内两两 ≥ MIN_SPACING ----
func test_min_spacing() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn)
	s.start()
	var ok: bool = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE, 2.0)
	assert_true(ok, "前置：一波 5 敌刷出")
	if spawned.size() != EXPECT_WAVE_SIZE:
		return
	for i in range(EXPECT_WAVE_SIZE):
		for j in range(i + 1, EXPECT_WAVE_SIZE):
			var a: Vector3 = spawned[i].spawn_pos
			var b: Vector3 = spawned[j].spawn_pos
			var dist: float = Vector2(a.x - b.x, a.z - b.z).length()
			assert_gte(dist, EXPECT_MIN_SPACING - 0.001,
					"敌 %d 与敌 %d 水平距离 %.3f ≥ MIN_SPACING=2.0" % [i, j, dist])


# ---- 4. 排除区：面 A 中心 2×2 矩形拒采样；刷 5 波 25 敌无落点 ----
func test_exclusion_zones() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	var exclusions := {"A": [{"x_min": -1.0, "x_max": 1.0, "z_min": -1.0, "z_max": 1.0}]}
	s.setup(SURFACES, _spawn_fn, exclusions, 0.1)
	s.start()
	var prev := 0
	for w in range(1, 6):
		var ok: bool = await _wait_until_bool(func(): return spawned.size() >= prev + EXPECT_WAVE_SIZE, 3.0)
		assert_true(ok, "第 %d 波应在限时内刷出" % w)
		if not ok:
			return
		for i in range(prev, prev + EXPECT_WAVE_SIZE):
			var stub = spawned[i]
			if stub.surface_name != "A":
				continue
			var px: float = stub.spawn_pos.x
			var pz: float = stub.spawn_pos.z
			var inside: bool = px > -1.0 + 0.001 and px < 1.0 - 0.001 \
					and pz > -1.0 + 0.001 and pz < 1.0 - 0.001
			assert_false(inside, "第 %d 波敌人 (%.3f, %.3f) 不得落在面 A 排除矩形内" % [w, px, pz])
		_kill_range(prev, prev + EXPECT_WAVE_SIZE)
		prev += EXPECT_WAVE_SIZE


# ---- 5. 全灭→wave_cleared(1)→延迟→第 2 波 + wave_started(2) ----
func test_wave_clear_and_respawn() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn, {}, 0.1)  # 注入短延迟免真实等待 1.5s
	s.start()
	var ok: bool = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE, 2.0)
	assert_true(ok, "第 1 波 5 敌刷出")
	assert_eq(wave_log, [1], "start() 应发出 wave_started(1)")
	for e in spawned.duplicate():
		e.take_damage(999.0)
	assert_eq(spawned.size(), EXPECT_WAVE_SIZE, "延迟期内不得立即刷第 2 波（须等 respawn_delay）")
	ok = await _wait_until_bool(func(): return cleared_log.size() == 1, 2.0)
	assert_true(ok, "全灭后应发出 wave_cleared")
	assert_eq(cleared_log, [1], "wave_cleared(1)")
	ok = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE * 2, 2.0)
	assert_true(ok, "respawn_delay=0.1s 后第 2 波 5 新敌应刷出")
	assert_eq(wave_log, [1, 2], "第 2 波应发出 wave_started(2)")
	assert_eq(int(s.current_wave()), 2, "current_wave() == 2")


# ---- 6. enemies_left 递减：每杀 1 敌 5→4→…→0 ----
func test_enemies_left_decrement() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn, {}, 5.0)  # 大延迟防第 2 波干扰
	s.start()
	var ok: bool = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE, 2.0)
	assert_true(ok, "前置：一波 5 敌刷出")
	await wait_physics_frames(2)  # 冲刷可能的延迟发射（如波开始的 enemies_left(5)）
	for i in range(EXPECT_WAVE_SIZE):
		spawned[i].take_damage(999.0)
		await wait_physics_frames(2)
	assert_eq(left_log, [5, 4, 3, 2, 1, 0], "每杀 1 敌 enemies_left 递减 5→4→…→0")


# ---- 7. 组合多样性：连续 6 波的面名多重集至少出现 2 种 ----
func test_wave_combo_variety() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn, {}, 0.1)
	s.start()
	var combos: Array = []
	var prev := 0
	for w in range(1, 7):
		var ok: bool = await _wait_until_bool(func(): return spawned.size() >= prev + EXPECT_WAVE_SIZE, 3.0)
		assert_true(ok, "第 %d 波应在限时内刷出" % w)
		if not ok:
			return
		var counts := {}
		for i in range(prev, prev + EXPECT_WAVE_SIZE):
			var nm: String = spawned[i].surface_name
			counts[nm] = int(counts.get(nm, 0)) + 1
		combos.append(_combo_key(counts))
		_kill_range(prev, prev + EXPECT_WAVE_SIZE)
		prev += EXPECT_WAVE_SIZE
	var unique := {}
	for c in combos:
		unique[c] = true
	assert_gte(unique.size(), 2, "连续 6 波面名组合应至少出现 2 种（实际 %s）" % str(combos))


func _combo_key(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s×%d" % [k, counts[k]])
	return ",".join(parts)


# ---- 8. alive_count：start 后 ==5；杀 2 后 ==3 ----
func test_alive_count() -> void:
	var s := _make_spawner()
	if s == null:
		return
	_hook_spawner_signals(s)
	s.setup(SURFACES, _spawn_fn, {}, 5.0)  # 大延迟防第 2 波干扰
	s.start()
	var ok: bool = await _wait_until_bool(func(): return spawned.size() == EXPECT_WAVE_SIZE, 2.0)
	assert_true(ok, "前置：一波 5 敌刷出")
	await wait_physics_frames(2)
	assert_eq(int(s.alive_count()), EXPECT_WAVE_SIZE, "start 后 alive_count() == 5")
	spawned[0].take_damage(999.0)
	spawned[1].take_damage(999.0)
	await wait_physics_frames(2)
	assert_eq(int(s.alive_count()), 3, "杀 2 后 alive_count() == 3")
