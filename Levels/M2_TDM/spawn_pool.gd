# Levels/M2_TDM/spawn_pool.gd
# TDM 营地点数池（2026-08-13）：每营 10 个随机刷新点，角色只在
# "当前无其他角色占用"的点位出现——保证所有角色随机刷新不会挤在一起（用户拍板需求）。
# 用法：SpawnPool.setup(points) → acquire(owner)（随机空点，幂等）→ release(owner)。
# 无场景依赖（纯数据），GUT 直测。
class_name SpawnPool
extends RefCounted

var _points: Array = []
var _free: Array = []        # 空点索引表
var _owner_point := {}       # owner -> 点索引
var _rng := RandomNumberGenerator.new()


func setup(points: Array) -> void:
	_points = points.duplicate()
	_free.clear()
	_owner_point.clear()
	for i in _points.size():
		_free.append(i)


## 为 owner 分配一个随机空点（幂等：已占点则返回原有点）。
## 空池防御：warning + 返回 points[0]（不占位——5 角色/10 点场景不会触发；
## 宁可回退点也不破坏"不重叠"占用表）。
func acquire(owner: Object) -> Vector3:
	if _owner_point.has(owner):
		return _points[int(_owner_point[owner])]
	if _free.is_empty():
		push_warning("SpawnPool.acquire(): 无空点（%d 角色/%d 点），防御回退 points[0]" % [_owner_point.size(), _points.size()])
		return _points[0]
	var fi := _rng.randi_range(0, _free.size() - 1)
	var pi: int = int(_free[fi])
	_free.remove_at(fi)
	_owner_point[owner] = pi
	return _points[pi]


## 释放 owner 占用的点（未知 owner 无操作）
func release(owner: Object) -> void:
	if not _owner_point.has(owner):
		return
	_free.append(int(_owner_point[owner]))
	_owner_point.erase(owner)


## 全部释放（重开清场用）
func release_all() -> void:
	_free.clear()
	_owner_point.clear()
	for i in _points.size():
		_free.append(i)


func free_count() -> int:
	return _free.size()


func occupied_count() -> int:
	return _owner_point.size()
