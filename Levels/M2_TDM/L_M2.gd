# Levels/M2_TDM/L_M2.gd
# M2 TDM 小图主场景控制器：灰盒地图 + 玩家（MovementController）+ 武器系统 +
# TDM 框架（计分/复活/胜负/重开）+ 友军×4 + 敌营补位 + 小地图。
# TDM 需求（2026-08-13）：无限复活、先到 50 杀或 8 分钟击杀多者胜、复活延迟 3s（用户 2026-08-11 拍板）；
# 出生点（用户 2026-08-13 拍板）：玩家+4 友军北营 10 点随机、5 敌南营 10 点随机，
# 角色只在无其他角色占用的点位出现（SpawnPool 防重叠）。
# 2026-08-13 用户六项实测反馈：①出生朝战场（不面墙）②阵营级禁友伤 ③出生保护 2s 白闪
# ④显示器式计分板（我方得分/对局时间/敌方得分）⑤结算 KD 昵称列表 + R 重开 ⑥头顶英文名取代血量。
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
var _stats: TdmStats
var _north_pool: SpawnPool   # 北营点池（玩家 + 4 友军共用，防重叠）
var _respawner: TdmRespawner  # 南营敌补位器
var _friendly_names: Array = []  # 4 友军名字（本局）
var _enemy_names: Array = []     # 5 敌名队列（死→名回队尾，补位敌取队首——身份恒 5/局）

# ---- HUD ----
var _ammo_label: Label
var _weapon_label: Label
var _hitmarker: Label
var _minimap: Minimap
var _score_f_val: Label   # 我方得分数字
var _score_t_val: Label   # 对局时间数字
var _score_e_val: Label   # 敌方得分数字
var _hp_label: Label
var _hp_bar_bg: ColorRect   # 血条背景（2026-08-13 血条化）
var _hp_bar_fill: ColorRect  # 血条填充
var _player_name_label: Label
var _death_overlay: ColorRect
var _death_label: Label
var _death_remaining: float = 0.0
var _protect_overlay: ColorRect  # 出生保护白屏脉冲
var _protect_label: Label        # 出生保护倒计时标签
var _protect_t := 0.0
var _result_panel: Panel
var _result_title: Label
var _result_f_col: Label
var _result_e_col: Label
var _result_hint: Label


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
	_recorder = JumpRecorder.new()
	_recorder.name = "JumpRecorder"
	add_child(_recorder)
	_recorder.setup(_player, LAYOUT.all_solids(), "回声祭坛v3")


# ---- TDM 框架装配 ----
func _setup_tdm() -> void:
	_stats = TdmStats.new()
	_north_pool = SpawnPool.new()
	_north_pool.setup(LAYOUT.camp_spawn_points(1))
	# 每局名字：玩家 + 4 友军 + 5 敌人（随机英文名，战绩清零）
	_new_match_names()
	# 友军×4（与玩家同色；M1.5 静态桩无 AI——M3 接队友行为）
	for i in 4:
		var f: Enemy = Enemy.new()
		f.name = "Friendly%d" % i
		f.tint = FRIENDLY_TINT
		f.is_enemy = false
		f.display_name = _friendly_names[i]
		f.spawn_protection = Enemy.SPAWN_PROTECTION  # 出生保护（生成方显式设置）
		add_child(f)
		f.global_position = _north_pool.acquire(f)
		f.rotation.y = randf_range(-PI / 6.0, PI / 6.0)  # 北营朝战场（-Z）±30°——2026-08-13 修面墙 bug
	# 玩家占北营一个随机空点（朝战场 -Z）
	_player.global_position = _north_pool.acquire(_player)
	_player.rotation.y = 0.0
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
	_respawner.enemy_died.connect(_on_enemy_died)
	# 玩家生命（挂在玩家下，复活回调取北营空点）
	_life = PlayerLife.new()
	_life.name = "PlayerLife"
	_player.add_child(_life)
	_life.setup(_player, _on_player_death, _on_player_respawn_point, _on_player_reset)
	_life.health_changed.connect(_on_health_changed)
	_life.died.connect(_on_player_died)
	_life.respawned.connect(_on_player_respawned)
	# 开局（玩家也有出生保护；初始化血条显示）
	_respawner.start()
	_match.start()
	_on_health_changed(_life.health)
	_begin_player_protection()


## 每局名字分配：玩家固定 "player"（2026-08-13 用户拍板：玩家不需要随机名）；
## 4 友军 + 5 敌人随机英文名不重复（敌名队列随死亡/补位循环）
func _new_match_names() -> void:
	_stats.new_match()
	_stats.player_name = "player"
	_stats.register("friendly", _stats.player_name)
	_friendly_names.clear()
	_enemy_names.clear()
	for _i in 4:
		var n: String = _stats.make_name()
		_friendly_names.append(n)
		_stats.register("friendly", n)
	for _i in 5:
		var n: String = _stats.make_name()
		_enemy_names.append(n)
		_stats.register("enemy", n)
	if _player_name_label:
		_player_name_label.text = _stats.player_name


func _on_player_death() -> void:
	_north_pool.release(_player)  # 释放玩家点位，复活从空点随机取


func _on_player_respawn_point() -> Vector3:
	return _north_pool.acquire(_player)


## 复活满血满弹：各槽 refill + 退出 ADS（PlayerLife 已回满血/恢复输入）
## 末尾刷新弹药 HUD——refill 不发 ammo 信号，不刷则显示上一局数值（2026-08-13 用户反馈修复）
func _on_player_reset() -> void:
	_manager.set_aim(false)
	for i in 4:
		var core := _manager.get_core(i)
		if core:
			core.refill()
	_refresh_hud()


## 玩家出生保护（开局/复活共用）：身体白闪 + 白屏脉冲 + HUD 标签
func _begin_player_protection() -> void:
	_protect_t = _life.SPAWN_PROTECTION
	_view.set_spawn_flash(_protect_t)
	_protect_overlay.visible = true
	_protect_label.visible = true


## spawn_fn 闭包：实例化敌方并 add_child（位置/点位由 TdmRespawner 分配定位），
## 名字从敌名队列取队首（死敌名字回队尾——同一"士兵"身份跨复活累计战绩）。
## 朝向：南营朝战场中心 (0,0,0) 即 +Z 方向 ±30°（Godot -Z 前向惯例：yaw=atan2(-dir.x,-dir.z)=PI）。
func _spawn_enemy() -> Node:
	var e := Enemy.new()
	e.name = "Enemy%d" % _spawn_serial
	_spawn_serial += 1
	if _enemy_names.is_empty():
		_enemy_names.append("Recruit")  # 防御（正常恒 5）
	e.display_name = _enemy_names.pop_front()
	e.spawn_protection = Enemy.SPAWN_PROTECTION  # 出生保护（生成方显式设置）
	add_child(e)
	e.rotation.y = PI + randf_range(-PI / 6.0, PI / 6.0)
	return e


func _on_enemy_died(e: Node) -> void:
	# 顺序铁律：先记 stats 再记 match——最后一杀触发 50 杀 end() 时，
	# match_ended 信号链会同步读 stats 构建结算面板（2026-08-13 用户反馈"最后一杀没记录"根因）。
	if e is Enemy:
		_stats.add_death(e.display_name)
		_enemy_names.push_back(e.display_name)  # 名字回队尾（补位敌继承身份）
	_stats.add_kill(_stats.player_name)  # M2 仅玩家击杀（M3 队友击杀归因接入点）
	_match.add_friendly_kill()


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


# ---- HUD（准星/命中/弹药/计分板/血条/名字/保护/死亡/结算/小地图）----
# UI 字体（2026-08-13 用户反馈"敌"字显示失败——根因实测：SystemFont "PingFang SC" 在本机
# 解析到不含"敌"字的残缺字体（敌=false 我=true）；改为 FontFile 直接加载系统冬青黑体简体，
# 字形实测齐全（纯离线——系统字体本机加载，不随包分发）。
var _ui_font: Font


func _load_ui_font() -> Font:
	var paths := [
		"/System/Library/Fonts/Hiragino Sans GB.ttc",
		"/System/Library/Fonts/STHeiti Light.ttc",
	]
	for p in paths:
		if FileAccess.file_exists(p):
			var f := FontFile.new()
			if f.load_dynamic_font(p) == OK:
				return f
	# 兜底：SystemFont 按名（PingFang 置末位——本机实测其缺"敌"字）
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Hiragino Sans GB", "Heiti SC", "STHeiti", "PingFang SC"])
	return sf


func _setup_hud() -> void:
	_ui_font = _load_ui_font()
	# 全局默认：本场景全部 Label 走 _hud_label/手工设置字体（下方逐个 add_theme_font_override）
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var vp := get_viewport().get_visible_rect().size
	# 准星（居中）
	var cross := _hud_label(layer, vp * 0.5 + Vector2(-11, -26), "+", 36, Color(0.2, 1, 0.35))
	cross.add_theme_constant_override("outline_size", 8)
	# 命中标记（准星右下，闪现）
	_hitmarker = _hud_label(layer, vp * 0.5 + Vector2(14, -28), "✕", 40, Color(1, 0.25, 0.15))
	_hitmarker.add_theme_constant_override("outline_size", 8)
	_hitmarker.modulate.a = 0.0
	# ---- 计分板（顶部居中，显示器风格——2026-08-13 用户设计；2026-08-13 反馈整体放大）----
	# 深色面板 + 亮边框；内部三段小显示器："我方得分：XX ｜ 对局时间：XX:XX ｜ 敌方得分：XX"
	var board_w := 800.0
	var board_x := vp.x * 0.5 - board_w * 0.5
	var board := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.04, 0.07, 0.1, 0.9)
	bsb.border_color = Color(0.35, 0.55, 0.75)
	bsb.set_border_width_all(3)
	bsb.set_corner_radius_all(12)
	board.add_theme_stylebox_override("panel", bsb)
	layer.add_child(board)
	board.position = Vector2(board_x, 12)
	board.size = Vector2(board_w, 92)
	# 三段内显示器小框（含标题小字 + 数值大字）
	var seg_w := (board_w - 28) / 3.0
	for seg in 3:
		var inner := Panel.new()
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.07, 0.11, 0.16, 0.95)
		isb.border_color = Color(0.22, 0.32, 0.42)
		isb.set_border_width_all(1)
		isb.set_corner_radius_all(6)
		inner.add_theme_stylebox_override("panel", isb)
		layer.add_child(inner)
		inner.position = Vector2(board_x + 10 + seg * seg_w, 18)
		inner.size = Vector2(seg_w - 6, 78)
	var seg_titles := ["我方得分", "对局时间", "敌方得分"]
	for seg in 3:
		var lx: float = board_x + 20 + seg * seg_w
		_hud_label(layer, Vector2(lx, 21), seg_titles[seg], 17, Color(0.65, 0.75, 0.85))
	_score_f_val = _hud_label(layer, Vector2(board_x + 20, 46), "0", 36, Color(0.35, 1, 0.5))
	_score_t_val = _hud_label(layer, Vector2(board_x + 20 + seg_w, 46), "8:00", 36, Color(1, 0.95, 0.75))
	_score_e_val = _hud_label(layer, Vector2(board_x + 20 + seg_w * 2, 46), "0", 36, Color(1, 0.45, 0.4))
	# 段间分隔符 "｜"
	for seg in [1, 2]:
		_hud_label(layer, Vector2(board_x + seg * seg_w - 10, 32), "｜", 40, Color(0.35, 0.55, 0.75))
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
	# 武器名（左下，2026-08-13 放大）
	_weapon_label = _hud_label(layer, Vector2(30, vp.y - 70), "", 34, Color(1, 0.85, 0.4))
	# 玩家名字（左下，2026-08-13 放大；固定 "player"——用户拍板）
	_player_name_label = _hud_label(layer, Vector2(30, vp.y - 106), "", 30, Color(1, 1, 1))
	# 玩家血条（左下，2026-08-13 用户要求：文本 → 血条）
	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.color = Color(0.1, 0.12, 0.14, 0.9)
	layer.add_child(_hp_bar_bg)
	_hp_bar_bg.position = Vector2(30, vp.y - 138)
	_hp_bar_bg.size = Vector2(240, 22)
	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.color = Color(0.3, 1, 0.4)
	layer.add_child(_hp_bar_fill)
	_hp_bar_fill.position = Vector2(32, vp.y - 136)
	_hp_bar_fill.size = Vector2(236, 18)
	_hp_label = _hud_label(layer, Vector2(282, vp.y - 140), "", 28, Color(0.3, 1, 0.4))
	# 出生保护白屏脉冲 + 标签（隐藏）
	_protect_overlay = ColorRect.new()
	_protect_overlay.color = Color(1, 1, 1, 0.22)
	_protect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_protect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_protect_overlay)
	_protect_overlay.visible = false
	_protect_label = _hud_label(layer, Vector2(30, vp.y - 172), "出生保护", 20, Color(0.7, 0.9, 1))
	_protect_label.visible = false
	# 死亡黑幕 + 倒计时（隐藏）
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0, 0, 0, 0.85)
	_death_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_death_overlay)
	_death_label = Label.new()
	_death_label.add_theme_font_size_override("font_size", 52)
	_death_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25))
	_death_label.add_theme_font_override("font", _ui_font)
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(_death_label)
	_death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_overlay.visible = false
	_death_label.visible = false
	# 结算面板（隐藏）：胜负标题 + 两列昵称 KD 花名册 + 重开提示
	_result_panel = Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	rsb.border_color = Color(0.45, 0.6, 0.8)
	rsb.set_border_width_all(3)
	rsb.set_corner_radius_all(16)
	_result_panel.add_theme_stylebox_override("panel", rsb)
	layer.add_child(_result_panel)
	_result_panel.position = vp * 0.5 - Vector2(330, 240)
	_result_panel.size = Vector2(660, 480)
	_result_title = Label.new()
	_result_title.add_theme_font_size_override("font_size", 44)
	_result_title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_result_title.add_theme_font_override("font", _ui_font)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_title)
	_result_title.position = Vector2(0, 18)
	_result_title.size = Vector2(660, 56)
	_result_f_col = Label.new()
	_result_f_col.add_theme_font_size_override("font_size", 20)
	_result_f_col.add_theme_color_override("font_color", Color(0.45, 1, 0.6))
	_result_f_col.add_theme_font_override("font", _ui_font)
	_result_panel.add_child(_result_f_col)
	_result_f_col.position = Vector2(40, 90)
	_result_f_col.size = Vector2(280, 300)
	_result_e_col = Label.new()
	_result_e_col.add_theme_font_size_override("font_size", 20)
	_result_e_col.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	_result_e_col.add_theme_font_override("font", _ui_font)
	_result_panel.add_child(_result_e_col)
	_result_e_col.position = Vector2(350, 90)
	_result_e_col.size = Vector2(280, 300)
	_result_hint = Label.new()
	_result_hint.add_theme_font_size_override("font_size", 24)
	_result_hint.add_theme_color_override("font_color", Color(0.8, 0.9, 1))
	_result_hint.add_theme_font_override("font", _ui_font)
	_result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_hint)
	_result_hint.position = Vector2(0, 400)
	_result_hint.size = Vector2(660, 60)
	_result_hint.text = "按 R 重新开始"
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


## HUD 通用标签工厂（黑描边 + 系统苹方字体）
func _hud_label(layer: CanvasLayer, pos: Vector2, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	if _ui_font:
		l.add_theme_font_override("font", _ui_font)
	layer.add_child(l)
	l.position = pos
	return l


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
	_score_f_val.text = "%d" % friendly
	_score_e_val.text = "%d" % enemy


func _on_time_changed(seconds_left: int) -> void:
	_score_t_val.text = "%d:%02d" % [int(seconds_left / 60.0), seconds_left % 60]


func _on_health_changed(hp: float) -> void:
	# 血条填充 + 数值（2026-08-13 血条化；重开 respawn_now 会发 health_changed → 自动刷新）
	var frac := clampf(hp / 100.0, 0.0, 1.0)
	_hp_bar_fill.size = Vector2(236.0 * frac, 18.0)
	var col := Color(0.3, 1, 0.4) if hp > 40.0 else Color(1, 0.35, 0.3)
	_hp_bar_fill.color = col
	_hp_label.text = "%d" % int(ceil(hp))
	_hp_label.add_theme_color_override("font_color", col)


func _on_player_died() -> void:
	_death_remaining = _life.RESPAWN_DELAY
	_death_overlay.visible = true
	_death_label.visible = true
	_update_death_label()
	_match.add_enemy_kill()  # 玩家死亡 → 敌方总分 +1（M3 归因到具体敌人）
	_stats.add_death(_stats.player_name)


func _on_player_respawned() -> void:
	_death_overlay.visible = false
	_death_label.visible = false
	_player.rotation.y = 0.0  # 复活朝战场（北营 → -Z）
	_begin_player_protection()


func _update_death_label() -> void:
	_death_label.text = "你阵亡了\n%d 秒后复活" % int(ceil(_death_remaining))


func _on_match_ended(winner: int) -> void:
	# 结算冻结：玩家冻结（R 重开时恢复）；面板显示比分与昵称 KD 花名册
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	var verdict: String
	match winner:
		TdmMatch.Winner.FRIENDLY:
			verdict = "胜利！"
		TdmMatch.Winner.ENEMY:
			verdict = "失败"
		_:
			verdict = "平局"
	_result_title.text = "%s  我方 %d : %d 敌方" % [verdict, _match.friendly_score, _match.enemy_score]
	_result_f_col.text = _roster_text("friendly")
	_result_e_col.text = _roster_text("enemy")
	_result_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## 花名册列文本："姓名  击杀/死亡  KD比"（2026-08-13 用户拍板：结算用昵称；D=0 → MVP）
func _roster_text(team: String) -> String:
	var title := "我方" if team == "friendly" else "敌方"
	var txt := "%s\n" % title
	for r in _stats.roster(team):
		txt += "%s  %d/%d  %s\n" % [r["name"], r["kills"], r["deaths"], r["kd"]]
	return txt


func _restart_match() -> void:
	_result_panel.visible = false
	_match.reset()
	_new_match_names()                 # 重开重抽全部名字（战绩清零）
	for i in 4:
		var f := get_node_or_null("Friendly%d" % i)
		if f is Enemy:
			f.set_display_name(_friendly_names[i])  # 友军换新名 + 新局出生保护
			f.spawn_protection = Enemy.SPAWN_PROTECTION
	_life.respawn_now()                # 满血满弹 + 取点 + 恢复输入（存活/死亡/倒计时中均安全）
	_player.rotation.y = 0.0
	_respawner.start()                 # 清场南营敌 + 重新刷 5 敌（新敌名队列）
	_begin_player_protection()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	# 死亡倒计时刷新（死亡黑幕可见时）
	if _death_overlay.visible:
		_death_remaining -= delta
		_update_death_label()
	# 出生保护：白屏脉冲 + 倒计时标签
	if _protect_t > 0.0:
		_protect_t = maxf(_protect_t - delta, 0.0)
		_protect_overlay.modulate.a = 0.22 * (0.5 + 0.5 * sin(_protect_t * 24.0))
		_protect_label.text = "出生保护 %.1fs" % _protect_t
		if _protect_t <= 0.0:
			_protect_overlay.visible = false
			_protect_label.visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_tree().quit()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			# K 自杀测试键（临时，正式游戏去除）：验证死亡/复活/结算全流程——敌人 M3 前不会攻击玩家
			if _life:
				_life.take_damage(999.0)
		elif event.keycode == KEY_R:
			# R 重开（结算后可用；_input 处理保证 UI 面板不吞键——2026-08-13 用户反馈修复）
			if _match and _match.state == TdmMatch.State.RESULT:
				_restart_match()


# ---- 输入路由（L_Main 同款：fire 由 WeaponManager 物理帧轮询，这里路由 reload/aim/切枪）----
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
