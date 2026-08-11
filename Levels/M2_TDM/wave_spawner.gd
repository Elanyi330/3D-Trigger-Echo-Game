# Levels/M2_TDM/wave_spawner.gd
# 波次刷怪器（任务 12）：地图可踏足建筑表面（standable_surfaces() 数据驱动）
# 每波随机刷 WAVE_SIZE 个敌人，全灭后 RESPAWN_DELAY 秒再刷下一波，循环。
#
# 依赖注入：WaveSpawner 不依赖 Enemy 类——敌人由 spawn_fn 闭包创建
# （L_M2 负责实例化 Enemy、add_child 与朝向），本类只关心返回实例的 `died` 信号。
#
# 撒点算法：面洗牌 → 每面每波 ≤ MAX_PER_SURFACE → 面内 center±(size/2−SPAWN_MARGIN)
# 随机采样 → 拒绝采样（该面的 exclusions 矩形 + 与本波已刷敌水平距离 < MIN_SPACING）
# → 单敌单面重试上限 MAX_SAMPLES 次，失败换下一面；全部失败兜底：优先用 setup 时
# 每面预计算的合法兜底点 _fallback[面名]（仅对 exclusions 拒绝采样），无预计算点
# 才退回面中心（最终兜底）。波次组合多样性由面洗牌保证。
class_name WaveSpawner
extends Node

signal wave_started(wave_n: int)
signal enemies_left(count: int)
signal wave_cleared(wave_n: int)

const WAVE_SIZE := 5          # 每波敌人数
const RESPAWN_DELAY := 1.5    # 全灭→下一波延迟（秒）
const MAX_PER_SURFACE := 2    # 同一刷怪面每波上限
const MIN_SPACING := 2.0      # 敌间最小水平距离（米）
const SPAWN_MARGIN := 0.5     # 面内撒点边距（米）
const MAX_SAMPLES := 50       # 单敌单面拒绝采样重试上限

var _surfaces: Array = []
var _spawn_fn: Callable
var _exclusions: Dictionary = {}
var _fallback: Dictionary = {}   # 面名 → setup 预计算的合法兜底点（终审 M2 修复）
var _respawn_delay: float = RESPAWN_DELAY
var _current_wave := 0
var _alive := 0


## surfaces: standable_surfaces() 格式数组 {"name","center"(y=top_y),"size","top_y"}
## spawn_fn: Callable(surface: Dictionary, pos: Vector3) -> Node（返回敌人实例，调用方负责 add_child）
## exclusions: Dictionary[String -> Array]，面 name → 排除矩形列表
##             {"x_min","x_max","z_min","z_max"}（世界坐标 XZ 投影，撒点拒绝区）
## respawn_delay: 全灭→下一波延迟（可注入短延迟便于测试）
func setup(surfaces: Array, spawn_fn: Callable, exclusions: Dictionary = {},
		respawn_delay: float = RESPAWN_DELAY) -> void:
	_surfaces = surfaces
	_spawn_fn = spawn_fn
	_exclusions = exclusions
	_respawn_delay = respawn_delay
	_precompute_fallbacks()


## 每面预计算一个合法兜底点：面内 center±(size/2−SPAWN_MARGIN) 拒绝采样（仅对
## exclusions，MAX_SAMPLES 次尝试），成功存 _fallback[面名]，失败不存（波次兜底
## 退回面中心最终保底）。终审 M2 修复：旧兜底直取面中心——如 Altar 中心落在
## Pedestal 排除区内，兜底点会落入禁区。
func _precompute_fallbacks() -> void:
	_fallback = {}
	for s0 in _surfaces:
		var s: Dictionary = s0
		var nm: String = str(s["name"])
		var rects: Array = []
		if _exclusions.has(nm):
			rects = _exclusions[nm]
		var c: Vector3 = s["center"]
		var sz: Vector3 = s["size"]
		var half_x: float = maxf(sz.x * 0.5 - SPAWN_MARGIN, 0.0)
		var half_z: float = maxf(sz.z * 0.5 - SPAWN_MARGIN, 0.0)
		for _attempt in range(MAX_SAMPLES):
			var x: float = c.x + randf_range(-half_x, half_x)
			var z: float = c.z + randf_range(-half_z, half_z)
			if _in_any_rect(x, z, rects):
				continue
			_fallback[nm] = Vector3(x, float(s["top_y"]), z)
			break


## 刷第 1 波并启动循环
func start() -> void:
	if _surfaces.is_empty() or not _spawn_fn.is_valid():
		push_warning("WaveSpawner.start(): 未 setup（空面清单或无效 spawn_fn），跳过")
		return
	_current_wave = 1
	_spawn_wave()


func current_wave() -> int:
	return _current_wave


func alive_count() -> int:
	return _alive


# ---- 内部 ----

func _spawn_wave() -> void:
	wave_started.emit(_current_wave)
	var order: Array = _surfaces.duplicate()
	order.shuffle()
	var points: Array = []   # 本波已刷敌世界坐标（水平距离判定用）
	var counts := {}         # 面 name → 本波已刷数
	for _i in range(WAVE_SIZE):
		var surf: Dictionary = {}
		var pos := Vector3(NAN, NAN, NAN)
		# 按洗牌序逐面尝试（每面 ≤ MAX_PER_SURFACE，拒绝采样上限 MAX_SAMPLES）
		for s0 in order:
			var s: Dictionary = s0
			var nm: String = str(s["name"])
			if int(counts.get(nm, 0)) >= MAX_PER_SURFACE:
				continue
			var p: Vector3 = _find_spawn_point(s, points)
			if not is_nan(p.x):
				surf = s
				pos = p
				break
		if surf.is_empty():
			# 兜底：任意尚有余量的合法面——优先用 setup 预计算的合法兜底点
			# （已对 exclusions 拒绝采样）；无预计算点才退回面中心（最终保底，
			# 此时整面被排除区覆盖，中心亦属禁区，接受降级）
			for s0 in order:
				var s2: Dictionary = s0
				var nm2: String = str(s2["name"])
				if int(counts.get(nm2, 0)) >= MAX_PER_SURFACE:
					continue
				surf = s2
				if _fallback.has(nm2):
					pos = _fallback[nm2]
				else:
					var c: Vector3 = s2["center"]
					pos = Vector3(c.x, float(s2["top_y"]), c.z)
				break
		if surf.is_empty():
			continue  # 面总容量不足 WAVE_SIZE（14 面场景下不会发生）
		var nm3: String = str(surf["name"])
		counts[nm3] = int(counts.get(nm3, 0)) + 1
		points.append(pos)
		var enemy: Node = _spawn_fn.call(surf, pos)
		if enemy == null:
			continue
		_alive += 1
		_connect_died(enemy)
	enemies_left.emit(_alive)


## 面内拒绝采样：center±(size/2−SPAWN_MARGIN) 随机点，拒绝 exclusions 矩形内
## 与距已刷敌水平距离 < MIN_SPACING 的点；MAX_SAMPLES 次失败返回 (NAN,NAN,NAN)。
func _find_spawn_point(surf: Dictionary, existing: Array) -> Vector3:
	var c: Vector3 = surf["center"]
	var sz: Vector3 = surf["size"]
	var half_x: float = maxf(sz.x * 0.5 - SPAWN_MARGIN, 0.0)
	var half_z: float = maxf(sz.z * 0.5 - SPAWN_MARGIN, 0.0)
	var rects: Array = []
	if _exclusions.has(str(surf["name"])):
		rects = _exclusions[str(surf["name"])]
	for _attempt in range(MAX_SAMPLES):
		var x: float = c.x + randf_range(-half_x, half_x)
		var z: float = c.z + randf_range(-half_z, half_z)
		if _in_any_rect(x, z, rects):
			continue
		if _too_close(x, z, existing):
			continue
		return Vector3(x, float(surf["top_y"]), z)
	return Vector3(NAN, NAN, NAN)


func _in_any_rect(x: float, z: float, rects: Array) -> bool:
	for r0 in rects:
		var r: Dictionary = r0
		if x >= float(r["x_min"]) and x <= float(r["x_max"]) \
				and z >= float(r["z_min"]) and z <= float(r["z_max"]):
			return true
	return false


func _too_close(x: float, z: float, existing: Array) -> bool:
	for p0 in existing:
		var p: Vector3 = p0
		if Vector2(x - p.x, z - p.z).length() < MIN_SPACING:
			return true
	return false


## died 一次性处理：alive−1 → emit enemies_left → 自动断开（CONNECT_ONE_SHOT，
## Enemy 死亡后自行倒地淡出并 queue_free，断开即无悬空引用）→ 全灭则进下一波。
func _connect_died(enemy: Node) -> void:
	var handler: Callable
	handler = func() -> void:
		_alive -= 1
		enemies_left.emit(_alive)
		if _alive <= 0:
			wave_cleared.emit(_current_wave)
			_respawn_soon()
	enemy.died.connect(handler, CONNECT_ONE_SHOT)


func _respawn_soon() -> void:
	await get_tree().create_timer(_respawn_delay).timeout
	if not is_inside_tree():
		return  # 测试 autofree/场景退出后不再刷波
	_current_wave += 1
	_spawn_wave()
