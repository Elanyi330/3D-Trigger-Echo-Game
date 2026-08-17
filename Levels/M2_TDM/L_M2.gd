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
const JUMP_EDGES := preload("res://Levels/M2_TDM/jump_edges.gd")  # (2026-08-17 M3.3 T17/T18) TacticalPoints 面表来源
const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const FRIENDLY_TINT := Color(0.3, 0.65, 0.35)  # 友方绿（与玩家本色一致）

@export var range_mode := false  # 2026-08-13 用户需求：取消无限弹药/无限手雷——全部有限（弹药箱补给）

var _player: CharacterBody3D
var _head: Node3D
var _manager: WeaponManager
var _view: WeaponView
var _recorder: JumpRecorder
var _spawn_serial := 0   # 敌人名序号（同面一敌一名会撞名——Godot 撞名会重置为 @Class@id）

# ---- TDM 框架（2026-08-13）----
var _board: EventBoard          # 事件板（2026-08-17 M3.2 T9）：死亡事件 TTL 30s 阵营共享
var _match: TdmMatch
var _life: PlayerLife
var _stats: TdmStats
var _north_pool: SpawnPool   # 北营点池（玩家 + 4 友军共用，防重叠）
var _respawner: TdmRespawner  # 南营敌补位器
var _friendly_names: Array = []  # 4 友军名字（本局）
var _enemy_names: Array = []     # 5 敌名队列（死→名回队尾，补位敌取队首——身份恒 5/局）

# ---- M3.3 AI 装配（2026-08-17 T17/T18）----
var _noise_bus: NoiseBus             # 噪音总线（T7 契约：new + add_child）
var _player_steps: FootstepEmitter   # 玩家脚步发射器（敌 bot 听觉的脚步声源）
var _tactical: TacticalPoints        # 战术点库（共享单实例，T12 build_from_faces 一次构建）

# ---- HUD ----
var _ammo_label: Label
var _weapon_label: Label
var _hitmarker: Label
var _minimap: Minimap
var _score_f_val: Label   # 我方得分数字
var _score_t_val: Label   # 对局时间数字
var _score_e_val: Label   # 敌方得分数字
var _pickup_label: Label  # 弹药箱拾取提示（闪现）
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
	# 事件板（2026-08-17 M3.2 T9）：死亡事件 TTL 30s 阵营共享——M3.3 策略层消费
	_board = EventBoard.new()
	_board.name = "EventBoard"
	add_child(_board)
	# TDM 框架：北营点池（玩家+友军）→ 比赛状态机 → 敌营补位 → 玩家生命
	_setup_tdm()
	# 导航（2026-08-13 navmesh 阶段 2/3）：烘焙网格 + 28 处人类验证跳跃链接（M3 AI 寻路消费）
	_setup_navigation()
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
	_setup_ammo_boxes()
	_on_health_changed(_life.health)
	_begin_player_protection()
	# M3.3 AI 装配（2026-08-17 T17/T18）：respawner.start() 已同步产出 5 敌——
	# 共享实例（NoiseBus/TacticalPoints）+ 玩家脚步/枪声接线 + 补挂 5 敌 AI 链；
	# 此后补位敌在 _spawn_enemy 即时挂链。
	_setup_bot_ai()


## 导航装配（2026-08-13 navmesh 阶段 2/3）：烘焙网格区域 + 跳跃链接。
## M3 AI 寻路（NavigationAgent3D）直接消费；--nav-debug 启动参数自绘网格与链接（阶段 5 验收）。
## 2026-08-15 F4 决定性根因重构：链接不再随区域立即创建——_ready 时地图未同步，
## 原始端点悬空 → 首注册被导航服务端全部丢弃，且丢弃永久（P 时刻再快照无法复活，
## 控制器复刻实测 0/54）。改为等地图首轮迭代完成后创建（见 _create_nav_links_after_sync）。
func _setup_navigation() -> void:
	var nav_mesh: NavigationMesh = load("res://Levels/M2_TDM/navmesh.res")
	if nav_mesh == null:
		push_warning("L_M2: navmesh.res 未找到——先运行 godot --headless --path . -s tools/bake_navmesh.gd 重新烘焙")
		return
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	region.navigation_mesh = nav_mesh
	add_child(region)
	_create_nav_links_after_sync.call_deferred()
	if "--nav-debug" in OS.get_cmdline_user_args():
		_build_nav_debug(nav_mesh)  # 自绘导航面+链接（Forward Mobile 不渲染 NavigationServer 调试层）


## 等地图两轮迭代完成后创建 54 跳跃链接（2026-08-15 F4）：首注册端点即
## map_get_closest_point 有效导航点 → 永不因悬空被丢弃（被丢弃链接即便端点改回
## 有效也不复活——丢弃永久性教训，控制器复刻实测 0/54）。哨兵用
## map_get_iteration_id（iter_id 可靠；map_is_active 在未同步地图上假阳性放行，
## F3 实证。probe_lifecycle2 实测：iter 1 时 closest 查询仍返回 (0,0,0)——区域
## navmesh 解析在第二轮迭代才完成，iter 1 即创建会以零点注册重蹈丢弃）。门槛取
## 函数入口基值 +2（绝对阈值在 GUT 等复用地图上会因继承前测迭代数而提前放行）。
## ≤120 帧兜底：超时打警告仍创建（最坏退回旧行为）。
func _create_nav_links_after_sync() -> void:
	var map_rid := get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	var synced := false
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			synced = true
			break
	if not synced:
		push_warning("L_M2: 导航地图 120 帧内未完成两轮迭代，链接创建可能悬空")
	var off_count := 0
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		var link := NavigationLink3D.new()
		link.name = "NavLink_" + str(l["name"])
		# 端点查询带重试（2026-08-15 F4 实测修正）：迭代达标后 closest 仍可能
		# 瞬时返回 (0,0,0)（地图再同步窗口内查询失败，GUT 复用地图复现率 ~1/3）
		# ——零点注册即被导航服务端丢弃且永久，宁可多等一帧（≤10 帧）。
		link.start_position = await _query_nav_point(map_rid, l["from"])
		link.end_position = await _query_nav_point(map_rid, l["to"])
		link.bidirectional = true
		add_child(link)
		# 创建后自检：端点自身即导航点（closest 距自身 >0.1 = 未 snap 成功）
		if NavigationServer3D.map_get_closest_point(map_rid, link.start_position) \
				.distance_to(link.start_position) > 0.1 \
				or NavigationServer3D.map_get_closest_point(map_rid, link.end_position) \
				.distance_to(link.end_position) > 0.1:
			off_count += 1
	if off_count > 0:
		push_warning("L_M2: %d 个链接端点未 snap 到导航面" % off_count)


## 端点导航点查询（失败重试 ≤10 帧）：地图再同步窗口内 closest 可能瞬时返回
## (0,0,0)——零点注册即被丢弃且永久（F4 教训），失败多等一帧重查。
func _query_nav_point(map_rid: RID, p: Vector3) -> Vector3:
	for i in 10:
		var q := NavigationServer3D.map_get_closest_point(map_rid, p)
		if q != Vector3.ZERO:
			return q
		await get_tree().physics_frame
	return NavigationServer3D.map_get_closest_point(map_rid, p)


## 导航可视化（--nav-debug，2026-08-13）：半透明蓝导航面片 + 青色边线 + 绿色跳跃链接线。
## 数据直读 NavigationMesh 顶点/多边形索引环——不依赖引擎 debug 渲染。
func _build_nav_debug(nav_mesh: NavigationMesh) -> void:
	var holder := Node3D.new()
	holder.name = "NavDebug"
	add_child(holder)
	# 面片（三角扇切分凸多边形）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := nav_mesh.get_vertices()
	for i in nav_mesh.get_polygon_count():
		var poly := nav_mesh.get_polygon(i)
		for j in range(2, poly.size()):
			for k in [0, j - 1, j]:
				st.set_normal(Vector3.UP)
				st.add_vertex(verts[poly[k]])
	var face_mesh := MeshInstance3D.new()
	face_mesh.mesh = st.commit()
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.22)
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mesh.material_override = face_mat
	holder.add_child(face_mesh)
	# 边线 + 链接线
	var im := ImmediateMesh.new()
	var line_mesh := MeshInstance3D.new()
	line_mesh.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.3, 0.9, 1.0)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mesh.material_override = line_mat
	holder.add_child(line_mesh)
	im.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	for i in nav_mesh.get_polygon_count():
		var poly := nav_mesh.get_polygon(i)
		for j in poly.size():
			im.surface_add_vertex(verts[poly[j]])
			im.surface_add_vertex(verts[poly[(j + 1) % poly.size()]])
	# 链接线（绿）+ 端点标记
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		im.surface_set_color(Color(0.3, 1.0, 0.4))
		im.surface_add_vertex(l["from"])
		im.surface_add_vertex(l["to"])
	im.surface_end()
	# 链接端点小球
	for l0 in LAYOUT.jump_links():
		var l: Dictionary = l0
		for p in [l["from"], l["to"]]:
			var ball := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.25
			sph.height = 0.5
			ball.mesh = sph
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color(0.3, 1.0, 0.4)
			bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ball.material_override = bmat
			ball.position = p
			holder.add_child(ball)


## 弹药箱 ×10（2026-08-13 用户需求）：固定刷新点，玩家靠近自动拾取
## （弹药回归上限 + 新手雷一枚），拾取后 30s 自动重新刷新。
func _setup_ammo_boxes() -> void:
	for p0 in LAYOUT.ammo_box_points():
		var p: Dictionary = p0
		var box := AmmoBox.new()
		box.name = "AmmoBox_" + str(p["name"])
		add_child(box)
		box.global_position = p["pos"]
		box.setup(_player)
		box.picked_up.connect(_on_ammo_picked)


func _on_ammo_picked() -> void:
	_manager.collect_ammo_box()
	_refresh_hud()
	# 拾取提示闪现（顶部计分板下方）
	_pickup_label.visible = true
	_pickup_label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_pickup_label, "modulate:a", 0.0, 1.2)


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
	# (2026-08-17 M3.3 T17/T18) 补位敌即时挂 AI 链；开局 5 敌先于 _setup_bot_ai 产出
	# （respawner.start 在 bus 创建前）——其链由 _setup_bot_ai 遍历补挂。
	if _noise_bus != null:
		_attach_bot_ai(e)
	return e


func _on_enemy_died(e: Node) -> void:
	# 顺序铁律：先记 stats 再记 match——最后一杀触发 50 杀 end() 时，
	# match_ended 信号链会同步读 stats 构建结算面板（2026-08-13 用户反馈"最后一杀没记录"根因）。
	if e is Enemy:
		_stats.add_death(e.display_name)
		_enemy_names.push_back(e.display_name)  # 名字回队尾（补位敌继承身份）
	_stats.add_kill(_stats.player_name)  # M2 仅玩家击杀（M3 队友击杀归因接入点）
	_match.add_friendly_kill()
	_board.record_death("enemy", e.global_position)  # 事件板（2026-08-17 M3.2 T9）：不含击杀者位置


# ---- M3.3 AI 装配（2026-08-17 T17/T18；最小侵入：仅本文件新增 + _spawn_enemy 挂链）----

## AI 装配总入口（_setup_tdm 末尾调用）：
##   - NoiseBus（T7 契约：new + add_child）+ 玩家枪声/脚步 → 总线接线；
##     Grenade.exploded → "explosion"(50) 接线留注记：L_M2 无 Grenade 引用
##     （WeaponManager._throw_grenade 动态生成），M3.4 战斗集成时接——本任务接 shot_fired。
##     M67 投掷不发声：THROWABLE 核心不发 shot_fired（WeaponCore._execute_shot 门控），
##     「扔出无声、炸响另行接线」T7 契约自然成立。
##   - TacticalPoints 共享单实例（T12：JumpEdges.faces() 面表一次构建）。
##   - 开局 5 敌 AI 链**等导航首同步后**补挂（见 _attach_bots_after_sync——修复 1：
##     BotLocomotion.setup 需 map_get_closest_point 对齐链接端点，首同步前查询报错
##     且返回零点，链接表永久错位；respawner.start() 已同步产出 5 敌，早于同步）。
func _setup_bot_ai() -> void:
	_noise_bus = NoiseBus.new()
	_noise_bus.name = "NoiseBus"
	add_child(_noise_bus)
	# 玩家各武器核心枪声 → 总线（res.noise_radius == 0 的静默武器不接线——现四武器全 >0）
	for i in 4:
		var core := _manager.get_core(i)
		var res := _manager.get_resource(i)
		if core == null or res == null or res.noise_radius <= 0.0:
			continue
		core.shot_fired.connect(_on_shot_fired.bind(res.noise_radius))
	# 玩家脚步发射器（敌 bot 听觉的脚步声源；60Hz tick 见 _physics_process）
	_player_steps = FootstepEmitter.new()
	_player_steps.name = "PlayerFootsteps"
	_player.add_child(_player_steps)
	_player_steps.setup(_player)
	_player_steps.footstep.connect(_on_player_footstep)
	# 战术点库（共享单实例；140 点 = 160 面 − 20 导航不可达）
	_tactical = TacticalPoints.build_from_faces(JUMP_EDGES.faces())
	# 开局 5 敌补挂 AI 链（等导航同步——此后补位敌在 _spawn_enemy 即时挂链）
	_attach_bots_after_sync.call_deferred()


## 等导航地图两轮迭代后补挂开局 5 敌 AI 链（2026-08-17 M3.3 T17/T18 修复 1）：
## BotLocomotion.setup 用 map_get_closest_point 对齐 54 链接端点——首同步前查询
## 报错（GUT 记 Unexpected Errors 判测试失败）且返回零点 → 链接表永久错位、跳跃段
## 分类静默丢失。等待口径同 _create_nav_links_after_sync：iter ≥ 基值 +2（≤120 帧
## 兜底——最坏退回旧行为）。出生保护 2s（120 帧）内挂链完成，无行为影响。
func _attach_bots_after_sync() -> void:
	var map_rid := get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	for i in 120:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			break
	for c in get_children():
		if c is Enemy and (c as Enemy).is_enemy:
			_attach_bot_ai(c)


## 单敌 AI 链装配：Enemy → BotPerception（faction="enemy"、player_target=_player）→
## FootstepEmitter → BotBlackboard（初始键：hp=100/mag_frac=1.0/glock_frac=1.0/
## grenade_left=1/reserve=1/spawn_protection_left=body 实时值）→ BotLocomotion
## （map_rid）→ BotStrategy（event_board）→ BotBrain（strategy 由装配方注入——T16
## 决策点只读 params()）。tick 由 L_M2._physics_process 统一驱动（60Hz 铁律）；
## Brain.tick 内职责边界：先 perception.tick → 状态机转移 → locomotion.tick 末
## （BotBrain.tick 注释）。
## 敌 bot 脚步 → 总线接线留 M3.4（NoiseBus 无 source 字段——现接线会以 friendly
## 源注入敌 bot 自己，同阵营过滤失效；M3.4 友军听觉装配时一并解决）。
func _attach_bot_ai(e: Enemy) -> void:
	if e.get_node_or_null("BotBrain") != null:
		return  # 幂等（重开/重复调用防双链）
	var perc := BotPerception.new()
	perc.name = "BotPerception"
	e.add_child(perc)
	perc.setup(e, "enemy", _player)
	var steps := FootstepEmitter.new()
	steps.name = "FootstepEmitter"
	e.add_child(steps)
	steps.setup(e)
	var bb := BotBlackboard.new()
	bb.name = "BotBlackboard"
	e.add_child(bb)
	# 黑板初始键（简报装配语义规格）
	bb.set_value("hp", 100.0)
	bb.set_value("mag_frac", 1.0)
	bb.set_value("glock_frac", 1.0)
	bb.set_value("grenade_left", 1)
	bb.set_value("reserve", 1)
	bb.set_value("spawn_protection_left", e.spawn_protection)
	var loco := BotLocomotion.new()
	loco.name = "BotLocomotion"
	e.add_child(loco)
	loco.setup(e, get_world_3d().navigation_map)
	var strat := BotStrategy.new()
	strat.name = "BotStrategy"
	e.add_child(strat)
	strat.setup("enemy", _board, bb, e)
	var brain := BotBrain.new()
	brain.name = "BotBrain"
	e.add_child(brain)
	brain.setup(e, perc, bb, loco, _tactical)
	brain.strategy = strat  # T17/T18 装配注入
	# 噪音总线 → 该 bot 感知（简报口径：M3.3 总线源仅玩家 = friendly）
	_noise_bus.noise_event.connect(func(kind: String, pos: Vector3, radius: float) -> void:
		perc._push_noise_event(kind, pos, radius, "friendly"))


## 玩家武器枪声 → 总线（bind 半径后接 shot_fired 弹药参数）。
func _on_shot_fired(radius: float, _ammo_left: int) -> void:
	_noise_bus.noise_event.emit("gunshot", _player.global_position, radius)


## 玩家脚步 → 总线（敌 bot 听觉源；半径由 FootstepEmitter 分级）。
func _on_player_footstep(pos: Vector3, radius: float) -> void:
	_noise_bus.noise_event.emit("footstep", pos, radius)


## 导航剩余路程（2026-08-17 M3.3 T16 注记：黑板键 path_remaining 由装配方写——
## Brain._path_remaining 缺键回退直线距，写键后转精确路径剩余；BotStrategy 路径长
## 同键消费）。BotLocomotion 无公开剩余路程接口（本任务禁改其文件），装配方直读其
## _path（GDScript 无强制私有；水平距口径与到达判定一致）。
func _locomotion_path_remaining(loco: BotLocomotion, body: Node3D) -> float:
	if loco == null or body == null:
		return 0.0
	var pts: PackedVector3Array = loco.get("_path")
	if pts.is_empty():
		return 0.0
	var total := Vector2(pts[0].x - body.global_position.x,
			pts[0].z - body.global_position.z).length()
	for i in range(1, pts.size()):
		total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	return total


## AI tick 链（2026-08-17 M3.3 T17/T18；60Hz 物理帧铁律）：
## 玩家脚步发射器 → 每敌 bot：黑板装配方键 → strategy.tick → brain.tick
## （Brain 内先 perception.tick + 状态机 + locomotion.tick 末）。
## 装配方黑板键（审查移交口径）：
##   spawn_protection_left：直映射 body.spawn_protection 实时值（每 tick 刷新——
##     T13 审查 Minor 2，禁止另起独立倒计时防双计时；Enemy._physics_process 已递减）；
##   alive_own/alive_enemy：双键同 tick 原子写全（T15 审查注记，供 Hold 策略）；
##   path_remaining：精确路径剩余（T16 注记，见 _locomotion_path_remaining）。
## M3.3 bot 不开枪：意图信号不接武器（M3.4 接线），既有对局行为零回归。
func _physics_process(delta: float) -> void:
	if _noise_bus == null:
		return  # 装配前（_ready 早期帧）零运行
	if _player_steps != null:
		_player_steps.tick(delta)
	# 存活统计（同 tick 算一次，双键写全——原子口径）
	var alive_own := 0
	var alive_enemy := 0
	for c in get_children():
		if c is Enemy and not (c as Enemy).dead:
			if (c as Enemy).is_enemy:
				alive_own += 1
			else:
				alive_enemy += 1
	if _life != null and not _life.dead:
		alive_enemy += 1
	for c in get_children():
		if not (c is Enemy) or not (c as Enemy).is_enemy or (c as Enemy).dead:
			continue
		var brain: Node = c.get_node_or_null("BotBrain")
		if brain == null:
			continue
		var bb: Node = c.get_node_or_null("BotBlackboard")
		var loco: Node = c.get_node_or_null("BotLocomotion")
		var strat: Node = c.get_node_or_null("BotStrategy")
		var steps: Node = c.get_node_or_null("FootstepEmitter")
		bb.set_value("spawn_protection_left", (c as Enemy).spawn_protection)
		bb.set_value("alive_own", alive_own)
		bb.set_value("alive_enemy", alive_enemy)
		bb.set_value("path_remaining", _locomotion_path_remaining(loco as BotLocomotion, c))
		strat.tick(delta)   # 策略先于 Brain（Brain 消费 params()；state 键上一帧已写）
		brain.tick(delta)
		steps.tick(delta)   # 脚步发射器 60Hz 驱动（现无订阅方——M3.4 接线消费）


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
	# 2026-08-13 用户需求：取消无限弹药/无限手雷——全部有限（弹药箱补给）；
	# range_mode 保留 false（L_Main 靶场模式用；L_M2 有限制）。
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
	# 弹药箱拾取提示（计分板下方，初始隐藏）
	_pickup_label = _hud_label(layer, Vector2(vp.x * 0.5 - 90, 110), "弹药箱 +", 26, Color(0.5, 0.95, 1))
	_pickup_label.visible = false
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
	_board.record_death("friendly", _player.global_position)  # 事件板（2026-08-17 M3.2 T9）


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
	for c in get_children():           # 弹药箱全部恢复激活（新一局）
		if c is AmmoBox:
			(c as AmmoBox).force_respawn()
	_begin_player_protection()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	_board.tick(delta)  # 事件板 TTL 剔除（2026-08-17 M3.2 T9，每帧驱动）
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
		get_tree().quit()  # Esc 退出程序（普通游玩语义，2026-08-16 用户拍板）
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K:
			# K 自杀测试键（M3 开发期保留，M6 去除）：验证死亡/复活/结算全流程——敌人 M3 前不会攻击玩家
			if _life:
				_life.take_damage(999.0)
		elif event.keycode == KEY_R:
			# R：结算后重开比赛（_input 处理保证 UI 面板不吞键——2026-08-13 用户反馈修复）
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
