# test/unit/test_bot_perception_los.gd
# M3.2 T6（2026-08-17）：BotPerception 视线子系统测试（TDD，先 RED 后 GREEN）。
# 目标：视锥 120°（yaw 平面角）/视距 40m/节流 0.2s/分段采样防穿缝/敌对阵营过滤。
#   static 纯函数（in_cone/within_range/los_blocked/is_hostile）脱离场景直接单测；
#   test_visible_signal 集成测试装配真实 L_M2（JumpRecorder 即释/等迭代+60 帧）
#   驱动敌对 bot 的感知：视线内友 bot → hostile_visible；移到墙后 → hostile_lost。
# RED 锚：生产类 BotPerception 尚不存在——本脚本引用该类即编译失败（错误信息 =
#   "Could not find type BotPerception" 类加载错误，即正确的 RED 失败原因）。
extends GutTest

const ENEMY_SCRIPT := preload("res://Levels/Enemy/Enemy.gd")
const PLAYER_LIFE_SCRIPT := preload("res://Levels/M2_TDM/player_life.gd")

var _vis_events: Array = []   # [{target: Node, pos: Vector3}]
var _lost_targets: Array = []  # [Node]


func _on_visible(target: Node, pos: Vector3) -> void:
	_vis_events.append({"target": target, "pos": pos})


func _on_lost(target: Node) -> void:
	_lost_targets.append(target)


# ── 测试辅助 ──

## 装配 L_M2 场景 + 立即 queue_free 场景内 JumpRecorder（防测试帧污染
##   user://jump_training 人类语料——项目铁律）+ 等导航两轮迭代（迭代 id ≥ 基值 +2，
##   同 L_M2._create_nav_links_after_sync 口径）+ 再等 60 物理帧（54 链接注册余量，
##   call_deferred 异步链）。返回已同步的场景实例（同 test_bot_locomotion_path.gd 范式）。
func _assemble_l2() -> Node3D:
	var l2: Node3D = load("res://Levels/M2_TDM/L_M2.tscn").instantiate()
	add_child_autofree(l2)
	var recorder: Node = l2.get_node_or_null("JumpRecorder")
	assert_not_null(recorder, "前置：L_M2._ready 应创建 JumpRecorder 子节点")
	if recorder:
		recorder.queue_free()
	var map_rid: RID = l2.get_world_3d().navigation_map
	var base_iter := NavigationServer3D.map_get_iteration_id(map_rid)
	var synced := false
	for i in 120:
		await wait_physics_frames(1)
		if NavigationServer3D.map_get_iteration_id(map_rid) >= base_iter + 2:
			synced = true
			break
	assert_true(synced, "导航地图应在 120 帧内完成两轮迭代")
	await wait_physics_frames(60)
	return l2


## 墙体构造器（同 test_grenade_los.gd 范式）：Objects 层 1 的 StaticBody3D 盒。
func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	add_child_autofree(b)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	b.global_position = center
	return b


## 感知驱动：每物理帧 tick 一次（tick 频率铁律——60Hz 口径，同生产节奏），
## ≤frames 帧推进。返回推进帧数。
func _drive(per: BotPerception, frames: int) -> int:
	var done := 0
	while done < frames:
		per.tick(1.0 / 60.0)
		await wait_physics_frames(1)
		done += 1
	return done


# ── T6-1：yaw=0 前向 -Z 在锥内；侧方 +X 锥外；59.9° 内 / 60.1° 外 ──
func test_in_cone_forward() -> void:
	var half := BotPerception.CONE_HALF_ANGLE
	assert_true(BotPerception.in_cone(Vector3.ZERO, 0.0, Vector3(0, 0, -10), half),
			"正前 -Z 在 120° 锥内")
	assert_false(BotPerception.in_cone(Vector3.ZERO, 0.0, Vector3(10, 0, 0), half),
			"侧方 +X（90°）在锥外")
	var a_in := deg_to_rad(59.9)
	assert_true(BotPerception.in_cone(Vector3.ZERO, 0.0,
			Vector3(sin(a_in) * 10.0, 0.0, -cos(a_in) * 10.0), half),
			"59.9° 边界内 → true")
	var a_out := deg_to_rad(60.1)
	assert_false(BotPerception.in_cone(Vector3.ZERO, 0.0,
			Vector3(sin(a_out) * 10.0, 0.0, -cos(a_out) * 10.0), half),
			"60.1° 边界外 → false")


# ── T6-2：yaw=π/2 前向 = -X（T3 修正口径交叉验证）──
func test_in_cone_yaw_general() -> void:
	var half := BotPerception.CONE_HALF_ANGLE
	assert_true(BotPerception.in_cone(Vector3.ZERO, PI / 2.0, Vector3(-10, 0, 0), half),
			"yaw=π/2 前向 −X：目标 −X 在锥内（−sin yaw, −cos yaw 口径）")
	assert_false(BotPerception.in_cone(Vector3.ZERO, PI / 2.0, Vector3(10, 0, 0), half),
			"目标 +X 在背后锥外")
	assert_false(BotPerception.in_cone(Vector3.ZERO, PI / 2.0, Vector3(0, 0, -10), half),
			"目标 −Z 在右侧 90° 锥外")


# ── T6-3：视距边界——40m 内 true / 40.1m 外 false ──
func test_within_range_boundary() -> void:
	assert_true(BotPerception.within_range(Vector3.ZERO, Vector3(40, 0, 0), 40.0),
			"40m 界内（含边界）→ true")
	assert_false(BotPerception.within_range(Vector3.ZERO, Vector3(40.1, 0, 0), 40.0),
			"40.1m 界外 → false")


# ── T6-4：实心墙遮挡 → true；无墙 → false ──
func test_los_blocked_wall() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	await wait_physics_frames(1)
	var space := holder.get_world_3d().direct_space_state
	var from := Vector3(0, 1.65, 0)
	var to := Vector3(0, 1.2, -10)
	assert_false(BotPerception.los_blocked(space, from, to, 5),
			"空场景主射线+中间点射线均无命中 → false")
	_wall(Vector3(0, 1.5, -5), Vector3(4, 3, 1))
	await wait_physics_frames(1)  # 墙形状入空间需一物理帧（同帧 raycast 不可见）
	assert_true(BotPerception.los_blocked(space, from, to, 5),
			"实心墙在主射线路径上 → true")


# ── T6-5：墙中间 0.08m 细缝——主射线穿过但中间点射线命中墙 → true（防穿缝）──
# 几何：from (0,1.65,0) → to (0,1.2,-10)，z=-6 处双盒夹缝 x∈[-0.04,0.04]（宽 0.08）。
# 主射线过缝（x=0）；中间点（1/3 分位 + 横向散布 0.3）射向目标——在 z=-6 处
# x≈-0.18 命中左盒 → 任一命中即遮挡。
func test_los_segment_sampling() -> void:
	var holder := Node3D.new()
	add_child_autofree(holder)
	await wait_physics_frames(1)
	var space := holder.get_world_3d().direct_space_state
	var from := Vector3(0, 1.65, 0)
	var to := Vector3(0, 1.2, -10)
	_wall(Vector3(-1.02, 1.5, -6), Vector3(1.96, 3, 0.5))  # 左盒 x∈[-2,-0.04]
	_wall(Vector3(1.02, 1.5, -6), Vector3(1.96, 3, 0.5))   # 右盒 x∈[0.04,2]（缝宽 0.08）
	await wait_physics_frames(1)  # 墙形状入空间需一物理帧
	assert_true(BotPerception.los_blocked(space, from, to, 5),
			"主射线穿 0.08m 细缝但中间点射线命中墙 → 遮挡（防穿缝假阳性）")


# ── T6-6：敌对阵营过滤——敌 bot/友 bot/玩家三组合按 faction 正确过滤 ──
func test_hostile_filter() -> void:
	var foe: Enemy = ENEMY_SCRIPT.new()          # is_enemy=true → "enemy"
	var ally: Enemy = ENEMY_SCRIPT.new()
	ally.is_enemy = false                        # "friendly"
	var player := Node.new()                     # 玩家鸭子接口：PlayerLife 脚本直挂
	player.set_script(PLAYER_LIFE_SCRIPT)
	assert_false(BotPerception.is_hostile(foe, "enemy"), "敌 bot 看敌 bot 非敌对")
	assert_true(BotPerception.is_hostile(ally, "enemy"), "敌 bot 看友 bot 敌对")
	assert_true(BotPerception.is_hostile(player, "enemy"), "敌 bot 看玩家敌对")
	assert_true(BotPerception.is_hostile(foe, "friendly"), "友 bot 看敌 bot 敌对")
	assert_false(BotPerception.is_hostile(ally, "friendly"), "友 bot 看友 bot 非敌对")
	assert_false(BotPerception.is_hostile(player, "friendly"), "友 bot 看玩家非敌对")
	# L_M2 装配形态：玩家根节点无 get_faction，阵营由 PlayerLife 子节点提供
	var player_host := Node3D.new()
	var life := PLAYER_LIFE_SCRIPT.new()
	player_host.add_child(life)
	assert_true(BotPerception.is_hostile(player_host, "enemy"),
			"玩家阵营经 PlayerLife 子节点解析（L_M2 装配形态）")
	assert_false(BotPerception.is_hostile(Node.new(), "enemy"),
			"无阵营目标不敌对")


# ── T6-7（集成）：L_M2 装配 + 敌 bot 感知友 bot ──
# 观察者敌 bot 置西侧空地 (-24,0,5) 朝 -Z，目标友 bot 正前 10m (-24,0,-5) 无遮挡；
# 每物理帧 tick 推进 → hostile_visible 发射且 target 正确；目标移到墙后 → hostile_lost。
# 断言为行为断言（不断言精确帧数——节流周期 0.2s ≈ 12 帧，驱动 30 帧余量）。
func test_visible_signal() -> void:
	var l2 := await _assemble_l2()
	var observer: Enemy = ENEMY_SCRIPT.new()
	observer.is_enemy = true
	observer.name = "ObserverBot"
	observer.position = Vector3(-24, 0, 5)  # 定位先于入树（T0 教训：陈旧形状一帧注册）
	observer.rotation.y = 0.0
	add_child_autofree(observer)
	var target: Enemy = ENEMY_SCRIPT.new()
	target.is_enemy = false
	target.name = "TargetAlly"
	target.position = Vector3(-24, 0, -5)   # 正前 10m（无遮挡空地）
	add_child_autofree(target)
	await wait_physics_frames(10)  # 落定 + 形状注册
	var per := BotPerception.new()
	add_child_autofree(per)
	per.setup(observer, observer.get_faction(), l2.get_node("Player"))
	per.hostile_visible.connect(_on_visible)
	per.hostile_lost.connect(_on_lost)
	# 第一阶段：视线内 → hostile_visible
	await _drive(per, 30)
	var hit_target := false
	var hit_pos := Vector3.ZERO
	for ev in _vis_events:
		if ev["target"] == target:
			hit_target = true
			hit_pos = ev["pos"]
	assert_true(hit_target,
			"节流周期内应发射 hostile_visible 且 target 正确（30 帧驱动，事件 %d 条）"
			% _vis_events.size())
	if hit_target:
		assert_almost_eq(hit_pos.distance_to(target.global_position), 0.0, 1e-4,
				"上报位置 = 目标 global_position")
	# 第二阶段：目标移到墙后 → hostile_lost
	_vis_events.clear()
	_wall(Vector3(-24, 1.5, 0), Vector3(4, 3, 1))  # 观察者与目标之间 z∈[-0.5,0.5]
	await wait_physics_frames(2)  # 墙形状入空间
	await _drive(per, 30)
	assert_true(_lost_targets.has(target),
			"目标移到墙后应发射 hostile_lost（驱动 30 帧，lost 列表 %d 条）"
			% _lost_targets.size())
