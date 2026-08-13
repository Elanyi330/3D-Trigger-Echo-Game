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
