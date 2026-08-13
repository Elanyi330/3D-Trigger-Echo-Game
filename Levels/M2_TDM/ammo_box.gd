# Levels/M2_TDM/ammo_box.gd
# 弹药箱（2026-08-13 用户需求）：10 处固定刷新点；玩家靠近自动拾取——
# 弹药量回归上限（弹匣不自动补充）+ 补充一枚新手雷；拾取后 30s 自动重新刷新。
# 距离判定拾取（无物理依赖，纯逻辑可测）；视觉 = MC 风金色小箱 + "AMMO" 标签。
# 目标注入：M2 仅玩家拾取（M3 可扩展拾取者列表——敌人拾取接入点）。
class_name AmmoBox
extends Node3D

signal picked_up

const RESPAWN_TIME := 30.0  # 拾取后重新刷新时间（用户拍板）
const PICK_RADIUS := 1.4    # 拾取半径（米，水平距离）

var _target: Node3D = null      # 拾取者（L_M2 注入玩家；距离判定需要 global_position）
var _active := true
var _timer := 0.0
var _respawn_time: float = RESPAWN_TIME
var _visual: MeshInstance3D
var _label: Label3D


func setup(target: Node3D, respawn_time: float = RESPAWN_TIME) -> void:
	_target = target
	_respawn_time = respawn_time


func _ready() -> void:
	# 视觉：MC 风金色小箱（0.7×0.55×0.7）+ 微自发光 + AMMO 标签
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.55, 0.7)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.68, 0.3)
	mat.roughness = 0.55
	mat.metallic = 0.35
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.18, 0.05)
	body.material_override = mat
	body.position = Vector3(0, 0.275, 0)
	add_child(body)
	_visual = body
	_label = Label3D.new()
	_label.text = "AMMO"
	_label.position = Vector3(0, 0.95, 0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 36
	_label.outline_size = 8
	_label.modulate = Color(0.95, 0.85, 0.5)
	add_child(_label)


func _process(delta: float) -> void:
	if _active:
		if _target != null and is_instance_valid(_target):
			var d := _target.global_position.distance_to(global_position)
			if d <= PICK_RADIUS:
				_pick()
	else:
		_timer -= delta
		if _timer <= 0.0:
			_respawn()


func _pick() -> void:
	_active = false
	_timer = _respawn_time
	_visual.visible = false
	_label.visible = false
	picked_up.emit()


func _respawn() -> void:
	_active = true
	_visual.visible = true
	_label.visible = true


## 强制刷新（重开新一局用：全部箱子恢复激活）
func force_respawn() -> void:
	_active = true
	_timer = 0.0
	_visual.visible = true
	_label.visible = true


func is_active() -> bool:
	return _active
