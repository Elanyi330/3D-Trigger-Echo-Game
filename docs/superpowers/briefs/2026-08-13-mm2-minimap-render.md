# Task Brief: MM2 — Minimap 渲染组件 + L_M2 装配

> 项目：Trigger Echo（Godot 4.7.1 + GDScript + GUT）
> 工作目录：`/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets，直接在此目录工作）
> 父计划：`docs/superpowers/plans/2026-08-13-m2-minimap.md`（本 brief 为该计划 MM2 的完整规格）
> 前置：MM1 完成——`Assets/Minimap/MinimapCore.gd` 已存在（class_name MinimapCore，`project(player_pos, player_forward, solids, entities)` → `segments`/`markers`）。**不要改动 MM1 的文件。**

## 目标

1. `Assets/Minimap/Minimap.gd`：Control 渲染胶水——`_draw` 消费核心输出（蓝图线框 + 敌红/友绿圆点 + 玩家中心箭头 + 圆底/描边），`_process` 每帧投影。圆形裁剪已在核心内完成，本层零几何逻辑。
2. `Levels/M2_TDM/L_M2.gd`：HUD 层装配小地图 + 敌人枚举提供者。

## TDD 步骤

### RED 1：新文件 `test/unit/test_minimap.gd`（逐字）

```gdscript
# test/unit/test_minimap.gd
# M2 小地图渲染胶水测试：装配/投影烟测/标志传递
extends GutTest


func test_minimap_setup_and_projection_smoke() -> void:
	var m := Minimap.new()
	add_child_autofree(m)
	var player := Node3D.new()
	add_child_autofree(player)
	var solids: Array = [{"name": "TestWall", "kind": "wall", "center": Vector3(0, 1, -4), "size": Vector3(4, 2, 1)}]
	var ents: Array = []
	m.setup(solids, player, func() -> Array: return ents)
	await wait_physics_frames(1)
	assert_gt(m._core.segments.size(), 0, "投影产出 ≥1 段")
	assert_eq(m._core.markers.size(), 0, "无实体标志")
	ents.append({"pos": Vector3(0, 0, -4), "is_enemy": true})
	await wait_physics_frames(1)
	assert_eq(m._core.markers.size(), 1, "敌人标志出现")
	assert_true(m._core.markers[0]["is_enemy"], "is_enemy 传递")
	assert_eq(m.mouse_filter, Control.MOUSE_FILTER_IGNORE, "不拦截鼠标（HUD）")
```

### GREEN 1：新文件 `Assets/Minimap/Minimap.gd`（逐字）

```gdscript
# Assets/Minimap/Minimap.gd
# M2 小地图渲染胶水（左上角圆形雷达，旋转式：上=玩家朝向）：
#   _draw 消费 MinimapCore 输出——蓝图线框 + 敌红/友绿圆点 + 玩家中心箭头 + 圆底/描边。
#   圆形裁剪在核心内完成（线段-圆求交），本层零几何逻辑。
class_name Minimap
extends Control

@export var world_radius_m: float = 12.0  # 覆盖半径（用户拍板 12m）
@export var map_radius_px: float = 90.0  # 地图半径（像素）
@export var bg_color := Color(0.05, 0.08, 0.06, 0.5)
@export var ring_color := Color(0.8, 0.9, 0.8, 0.9)
@export var line_color := Color(0.75, 0.9, 0.8, 0.7)
@export var friendly_color := Color(0.2, 0.9, 0.4)
@export var enemy_color := Color(0.95, 0.25, 0.2)

var _core := MinimapCore.new()
var _solids: Array = []
var _player: Node3D = null
var _entity_provider: Callable  # () -> Array[{pos: Vector3, is_enemy: bool}]


func setup(solids: Array, player: Node3D, entity_provider: Callable) -> void:
	_solids = solids
	_player = player
	_entity_provider = entity_provider
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 16.0
	size = Vector2(map_radius_px * 2.0 + 8.0, map_radius_px * 2.0 + 8.0)  # 圆心留 4px 描边余量


func _process(_delta: float) -> void:
	if _player == null:
		return
	_core.radius_m = world_radius_m
	_core.radius_px = map_radius_px
	var entities: Array = []
	if _entity_provider.is_valid():
		entities = _entity_provider.call()
	_core.project(_player.global_position, -_player.global_transform.basis.z, _solids, entities)
	queue_redraw()


func _draw() -> void:
	var c := Vector2(map_radius_px + 4.0, map_radius_px + 4.0)  # 圆心（含描边余量）
	draw_circle(c, map_radius_px, bg_color)
	for s in _core.segments:
		draw_line(c + s["a"], c + s["b"], line_color, 1.0)
	draw_arc(c, map_radius_px, 0.0, TAU, 64, ring_color, 2.0)
	_draw_player(c)
	for m in _core.markers:
		var col: Color = enemy_color if m["is_enemy"] else friendly_color
		draw_circle(c + m["pos"], 3.0, col)


func _draw_player(c: Vector2) -> void:
	# 玩家中心箭头（恒指上方——旋转式地图，箭头不动地图转）
	var p := PackedVector2Array([
		c + Vector2(0, -5), c + Vector2(4, 4), c + Vector2(-4, 4),
	])
	draw_colored_polygon(p, friendly_color)
```

### GREEN 2：`Levels/M2_TDM/L_M2.gd` 装配

1. 在 `# ---- HUD（弹药/准星/命中标记/波次，移植自 L_Main.gd）----` 注释块下方（成员变量区，`var _hitmarker: Label` 等行之后）追加：

```gdscript
var _minimap: Minimap  # M2 小地图（左上角圆形雷达）
```

2. 在 `_setup_hud` 函数中、HUD CanvasLayer 的 `layer` 变量作用域内（波次 Label 创建之后）追加：

```gdscript
	# 小地图（M2 左上角圆形雷达）：数据驱动蓝图投影 + 12m 内敌我标志
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	layer.add_child(minimap)
	minimap.setup(LAYOUT.all_solids(), _player, _enemy_entities)
```

3. HUD 段（`# ---- HUD ----` 注释下方、`_setup_hud` 函数之前或之后皆可）追加成员函数：

```gdscript
func _enemy_entities() -> Array:
	# 小地图实体提供者：L_M2 直接子节点中的 Enemy（≤5 个，每帧枚举零成本）。
	# M3 队友出现后在此追加 is_enemy=false 条目（同一接口）。
	var out: Array = []
	for c in get_children():
		if c is Enemy:
			out.append({"pos": c.global_position, "is_enemy": true})
	return out
```

注意：`LAYOUT` 是 L_M2.gd 中对 map_layout_v3 的引用名（`LAYOUT.all_solids()` 已在跳跃记录器等处使用，同名引用照用）；`_player` 是既有成员（`_manager.setup(slots, _player)` 同源）。

### VERIFY

`cd /Users/elanyi/Projects/Trigger-Echo && godot --headless --path . -s addons/gut/gut_cmdln.gd`
预期：**299 全绿**（290 + 8 MM1 + 1 MM2）。另跑 `godot --headless --path . Levels/M2_TDM/L_M2.tscn --quit-after 60` 确认场景无脚本错误（小地图装配运行 60 帧）。

常见坑：
- `Minimap.setup` 的 Callable 参数：lambda `func() -> Array: return ents` 捕获 `ents` 数组（引用语义，append 后可见——与 lambda 按值捕获原始值的陷阱不同，Array 是引用）。
- `set_anchors_preset(Control.PRESET_TOP_LEFT)` 后再设 offset——anchor 预设会重置 offsets，顺序为先 preset 后 offset（简报顺序已正确）。
- `_enemy_entities` 遍历 `get_children()` 中 `c is Enemy`——Enemy 是 class_name（StaticBody3D），`is` 检查有效。
- L_M2 的 `layer` 是 `_setup_hud` 内的局部变量——Minimap 创建必须在该函数作用域内（简报已指定位置）。

## 报告格式

- DONE / DONE_WITH_CONCERNS / BLOCKED
- RED 证据 + 改动行号 + 全量统计行 + 场景冒烟结果 + 规格偏差说明（如有）
