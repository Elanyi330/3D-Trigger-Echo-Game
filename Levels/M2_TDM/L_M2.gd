# Levels/M2_TDM/L_M2.gd
# M2 TDM 小图主场景控制器：灰盒地图 + 玩家（MovementController）+ 武器系统 +
# TDM 框架（计分/复活/胜负/重开）+ 友军×4 + 敌营补位 + 小地图。
# TDM 需求（2026-08-13）：无限复活、先到 50 杀或 8 分钟击杀多者胜、复活延迟 3s（用户 2026-08-11 拍板）；
# 出生点（用户 2026-08-13 拍板）：玩家+4 友军北营 10 点随机、5 敌南营 10 点随机，
# 角色只在无其他角色占用的点位出现（SpawnPool 防重叠）。
extends Node3D

const WEAPON_RES := [
	preload("res://Weapons/weapon_ak47.tres"),
	preload("res://Weapons/weapon_glock18.tres"),
	preload("res://Weapons/weapon_knife.tres"),
	preload("res://Weapons/weapon_m67.tres"),
]
const WEAPON_MODELS := [
	preload("res://Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb"),
	preload("res://Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb"),
	preload("res://Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb"),
	preload("res://Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb"),
]
const GREYBOX := preload("res://Levels/M2_TDM/map_greybox.gd")
const LAYOUT := preload("res://Levels/M2_TDM/map_layout_v3.gd")
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const FRIENDLY_TINT := Color(0.3, 0.65, 0.35)  # 友方绿（与玩家本色一致）

@export var range_mode := true  # 测试模式：枪械备弹无限（弹匣有限正常换弹）+ 手雷无限（投完切回主武器但可再切回投）

var _player: CharacterBody3D
var _head: Node3D
var _manager: WeaponManager
var _view: WeaponView
var _recorder: JumpRecorder
var _spawn_serial := 0   # 敌人名序号（同面一敌一名会撞名——Godot 撞名会重置为 @Class@id）

# ---- TDM 框架（2026-08-13）----
var _match: TdmMatch
var _life: PlayerLife
var _north_pool: SpawnPool   # 北营点池（玩家 + 4 友军共用，防重叠）
var _respawner: TdmRespawner  # 南营敌补位器

# ---- HUD ----
var _ammo_label: Label
var _weapon_label: Label
var _hitmarker: Label
var _minimap: Minimap
var _score_label: Label
var _hp_label: Label
var _death_overlay: ColorRect
var _death_label: Label
var _death_remaining: float = 0.0
var _result_panel: Panel
var _result_label: Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# 灰盒地图（纯色主题配色——2026-08-13 纹理升级已回退，配色用户拍板「可用」）
	var gb: Node3D = GREYBOX.new()
	gb.name = "Greybox"
	add_child(gb)
	gb.build()
	# 玩家（Player.tscn：MovementController + Head + Crouch）
	_player = load("res://Player/Player.tscn").instantiate()
	_player.name = "Player"
	add_child(_player)
	_player.global_position = LAYOUT.player_spawn()
	_head = _player.get_node("Head")
	_setup_weapons()
	_setup_hud()
	# TDM 框架：北营点池（玩家+友军）→ 比赛状态机 → 敌营补位 → 玩家生命
	_setup_tdm()
	# 跳跃记录（任务 15）：记录跳建筑操作供 AI 学习；地图哈希不符自动清空旧记录。
	# 必须在 Player 入树之后 add_child——Godot 4.7 _physics_process 按树序执行，
	# recorder 排玩家之后才能在 move_and_slide 之后读当帧状态。
	_recorder = JumpRecorder.new()
	_recorder.name = "JumpRecorder"
	add_child(_recorder)
	_recorder.setup(_player, LAYOUT.all_solids(), "回声祭坛v3")


# ---- TDM 框架装配 ----
func _setup_tdm() -> void:
	# 北营点池：玩家 + 4 友军共用（角色只在无其他角色占用的点位出现——用户拍板需求）
	_north_pool = SpawnPool.new()
	_north_pool.setup(LAYOUT.camp_spawn_points(1))
	# 友军×4（与玩家同色；M1.5 静态桩无 AI——M3 接队友行为）
	for i in 4:
		var f: Enemy = Enemy.new()
		f.name = "Friendly%d" % i
		f.tint = FRIENDLY_TINT
		f.is_enemy = false
		add_child(f)
		f.global_position = _north_pool.acquire(f)
		f.rotation.y = PI + randf_range(-PI / 6.0, PI / 6.0)  # 朝广场方向 ±30°
	# 玩家占北营一个随机空点
	_player.global_position = _north_pool.acquire(_player)
	# 比赛状态机（50 杀 / 8 分钟）
	_match = TdmMatch.new()
	_match.name = "TdmMatch"
	add_child(_match)
	_match.setup()
	_match.score_changed.connect(_on_score_changed)
	_match.time_changed.connect(_on_time_changed)
	_match.match_ended.connect(_on_match_ended)
	# 敌营补位器（南营 10 点 5 敌，死 3s 空点补位）
	_respawner = TdmRespawner.new()
	_respawner.name = "TdmRespawner"
	add_child(_respawner)
	_respawner.setup(LAYOUT.camp_spawn_points(-1), _spawn_enemy, 3.0)
	_respawner.enemy_died.connect(func(_e: Node) -> void: _match.add_friendly_kill())
	# 玩家生命（挂在玩家下，复活回调取北营空点）
	_life = PlayerLife.new()
	_life.name = "PlayerLife"
	_player.add_child(_life)
	_life.setup(_player, _on_player_death, _on_player_respawn_point, _on_player_reset)
	_life.health_changed.connect(_on_health_changed)
	_life.died.connect(_on_player_died)
	_life.respawned.connect(_on_player_respawned)
	# 开局
	_respawner.start()
	_match.start()


func _on_player_death() -> void:
	_north_pool.release(_player)  # 释放玩家点位，复活从空点随机取


func _on_player_respawn_point() -> Vector3:
	return _north_pool.acquire(_player)


## 复活满血满弹：各槽 refill + 退出 ADS（PlayerLife 已回满血/恢复输入）
func _on_player_reset() -> void:
	_manager.set_aim(false)
	for i in 4:
		var core := _manager.get_core(i)
		if core:
			core.refill()


## spawn_fn 闭包：实例化敌方并 add_child（位置/点位由 TdmRespawner 分配定位）。
## 朝向：南营朝广场中心 (0,0,0) 即 +Z 方向 ±30°（Godot -Z 前向惯例：yaw = atan2(-dir.x, -dir.z)）。
func _spawn_enemy() -> Node:
	var e := Enemy.new()
	e.name = "Enemy%d" % _spawn_serial
	_spawn_serial += 1
	add_child(e)
	e.rotation.y = PI + randf_range(-PI / 6.0, PI / 6.0)
	return e


# ---- 武器装配（移植自 L_Main.gd，同款：逻辑挂 Player 下，表现挂 Head 下）----
func _setup_weapons() -> void:
	_manager = WeaponManager.new()
	_manager.name = "WeaponManager"
	var models: Array[PackedScene] = []
	for m in WEAPON_MODELS:
		models.append(m)
	_manager.view_models = models
	_player.add_child(_manager)
	var slots: Array[WeaponResource] = []
	for r in WEAPON_RES:
		slots.append(r)
	_manager.setup(slots, _player)
	_manager.set_head(_head)
	if range_mode:
		# 测试模式（L_Main 同款）：枪械备弹无限（弹匣有限正常换弹）；手雷无限（投完自动切回主武器，可再切回投）
		for i in slots.size():
			var core := _manager.get_core(i)
			if core == null:
				continue
			var res := _manager.get_resource(i)
			if res.fire_mode == WeaponResource.FireMode.THROWABLE:
				core.infinite_ammo = true  # 手雷无限（投出后 refund 回 1 枚）
			elif res.fire_mode != WeaponResource.FireMode.MELEE:
				core.infinite_reserve = true  # 枪械备弹无限、弹匣有限
	# 开火即刷新弹药 HUD（WeaponManager 不在逐发时发 ammo 信号——L_Main 同款修复）
	for i in slots.size():
		var c := _manager.get_core(i)
		if c:
			c.shot_fired.connect(func(_a: int) -> void: _refresh_hud())
	_view = WeaponView.new()
	_view.name = "WeaponView"
	_head.add_child(_view)
	_view.setup(_manager, _player)


# ---- HUD（准星/命中/弹药/计分板/血条/死亡/结算/小地图）----
func _setup_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var vp := get_viewport().get_visible_rect().size
	# 准星（居中）
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 36)
	cross.add_theme_color_override("font_color", Color(0.2, 1, 0.35))
	cross.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cross.add_theme_constant_override("outline_size", 8)
	layer.add_child(cross)
	cross.position = vp * 0.5 + Vector2(-11, -26)
	# 命中标记（准星右下，闪现）
	_hitmarker = Label.new()
	_hitmarker.text = "✕"
	_hitmarker.add_theme_color_override("font_color", Color(1, 0.25, 0.15))
	_hitmarker.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hitmarker.add_theme_constant_override("outline_size", 8)
	_hitmarker.add_theme_font_size_override("font_size", 40)
	layer.add_child(_hitmarker)
	_hitmarker.position = vp * 0.5 + Vector2(14, -28)
	_hitmarker.modulate.a = 0.0
	# 计分板（顶部居中）：我方 X : X 敌方 + 倒计时
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 32)
	_score_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_score_label.add_theme_constant_override("outline_size", 8)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_score_label)
	_score_label.position = Vector2(0, 16)
	_score_label.size = Vector2(vp.x, 48)
	# 弹药背板（右下）
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	panel.position = Vector2(vp.x - 300, vp.y - 110)
	panel.size = Vector2(270, 80)
	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	_ammo_label.add_theme_font_size_override("font_size", 46)
	_ammo_label.add_theme_color_override("font_color", Color(1, 1, 1))
	layer.add_child(_ammo_label)
	_ammo_label.position = Vector2(vp.x - 300 + 18, vp.y - 110 + 14)
	# 武器名（左下）
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 28)
	_weapon_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_weapon_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_weapon_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_weapon_label)
	_weapon_label.position = Vector2(30, vp.y - 70)
	# 玩家血条（左下，武器名下方）
	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 24)
	_hp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hp_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_hp_label)
	_hp_label.position = Vector2(30, vp.y - 108)
	# 死亡黑幕 + 倒计时（隐藏）
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0.85)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_death_overlay)
	_death_label = Label.new()
	_death_label.add_theme_font_size_override("font_size", 52)
	_death_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_death_label)
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.visible = false
	_death_label.visible = false
	# 结算面板（隐藏）
	_result_panel = Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0, 0, 0, 0.75)
	rsb.set_corner_radius_all(16)
	_result_panel.add_theme_stylebox_override("panel", rsb)
	layer.add_child(_result_panel)
	_result_panel.position = vp * 0.5 - Vector2(260, 110)
	_result_panel.size = Vector2(520, 220)
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 44)
	_result_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.size = Vector2(520, 220)
	_result_panel.add_child(_result_label)
	_result_panel.visible = false
	# 小地图（M2 左上角圆形雷达）：数据驱动蓝图投影 + 12m 内敌我标志
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	layer.add_child(minimap)
	minimap.setup(LAYOUT.all_solids(), _player, _enemy_entities)
	_minimap = minimap
	# 弹药/切枪信号刷新
	_manager.weapon_ammo_updated.connect(_on_ammo_updated)
	_manager.weapon_switched.connect(_on_weapon_switched)
	_manager.enemy_hit.connect(_on_enemy_hit)
	_refresh_hud()


func _enemy_entities() -> Array:
	# 小地图实体提供者：L_M2 直接子节点中的 Enemy 与友军（≤9 个，每帧枚举零成本）。
	var out: Array = []
	for c in get_children():
		if c is Enemy:
			out.append({"pos": c.global_position, "is_enemy": c.is_enemy})
	return out


func _on_ammo_updated(_slot: int, _mag: int, _reserve: int) -> void:
	_refresh_hud()


func _on_weapon_switched(_slot: int) -> void:
	_refresh_hud()


func _on_enemy_hit() -> void:
	_hitmarker.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_hitmarker, "modulate:a", 0.0, 0.25)


func _refresh_hud() -> void:
	if _manager == null or _ammo_label == null:
		return
	var slot := _manager.get_current_slot()
	var core := _manager.get_core(slot)
	var res := _manager.get_resource(slot)
	if core == null or res == null:
		return
	var ammo := core.get_ammo()
	if res.fire_mode == WeaponResource.FireMode.MELEE:
		_ammo_label.text = "—"
	else:
		_ammo_label.text = "%d / %d" % [int(ammo.x), int(ammo.y)]
	_weapon_label.text = res.weapon_name


# ---- TDM 信号 → HUD ----
func _on_score_changed(friendly: int, enemy: int) -> void:
	_update_score_label(friendly, enemy)


func _on_time_changed(seconds_left: int) -> void:
	_update_score_label(_match.friendly_score, _match.enemy_score, seconds_left)


func _update_score_label(friendly: int, enemy: int, seconds_left: int = -1) -> void:
	var t: int = seconds_left
	if t < 0:
		t = _match.time_left() if _match else 480
	_score_label.text = "我方 %d : %d 敌方   %d:%02d" % [friendly, enemy, int(t / 60.0), t % 60]


func _on_health_changed(hp: float) -> void:
	_hp_label.text = "HP %d" % int(ceil(hp))
	_hp_label.add_theme_color_override("font_color",
		Color(0.3, 1, 0.4) if hp > 40.0 else Color(1, 0.35, 0.3))


func _on_player_died() -> void:
	_death_remaining = _life.RESPAWN_DELAY
	_death_overlay.visible = true
	_death_label.visible = true
	_update_death_label()


func _on_player_respawned() -> void:
	_death_overlay.visible = false
	_death_label.visible = false


func _update_death_label() -> void:
	_death_label.text = "你阵亡了\n%d 秒后复活" % int(ceil(_death_remaining))


func _on_match_ended(winner: int) -> void:
	# 结算冻结：玩家冻结（R 重开时恢复）；面板显示比分与重开提示
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var verdict: String
	match winner:
		TdmMatch.Winner.FRIENDLY:
			verdict = "胜利！"
		TdmMatch.Winner.ENEMY:
			verdict = "失败"
		_:
			verdict = "平局"
	_result_label.text = "%s\n我方 %d : %d 敌方\n\n按 R 重新开始" % [verdict, _match.friendly_score, _match.enemy_score]
	_result_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _restart_match() -> void:
	_result_panel.visible = false
	_match.reset()
	_life.respawn_now()  # 满血满弹 + 取点 + 恢复输入（存活/死亡/倒计时中均安全）
	_respawner.start()   # 清场南营敌 + 重新刷 5 敌
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	# 死亡倒计时刷新（死亡黑幕可见时）
	if _death_overlay.visible:
		_death_remaining -= delta
		_update_death_label()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()


# ---- 输入路由（L_Main 同款：fire 由 WeaponManager 物理帧轮询，这里路由 reload/aim/切枪/测试键）----
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"reload"):
		_manager.start_reload()
	elif event.is_action_pressed(&"aim"):
		_manager.set_aim(true)
	elif event.is_action_released(&"aim"):
		_manager.set_aim(false)
	elif event.is_action_pressed(&"weapon_1"):
		_manager.switch_to(0)
	elif event.is_action_pressed(&"weapon_2"):
		_manager.switch_to(1)
	elif event.is_action_pressed(&"weapon_3"):
		_manager.switch_to(2)
	elif event.is_action_pressed(&"weapon_4"):
		_manager.switch_to(3)
	elif event.is_action_pressed(&"next_weapon"):
		_manager.next_weapon()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			# K 自杀测试键（临时，正式游戏去除）：验证死亡/复活/结算全流程——敌人 M3 前不会攻击玩家
			_life.take_damage(999.0)
		elif event.keycode == KEY_R:
			# R 重开（结算后可用）
			if _match.state == TdmMatch.State.RESULT:
				_restart_match()
