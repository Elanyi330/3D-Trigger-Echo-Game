extends CharacterBody3D
class_name MovementController


@export var gravity_multiplier := 2.0
@export var speed: float = 6.35
# 武器移速倍率（mobility/250，M1 任务2）：WeaponManager 切枪时写入；默认 1.0 = 无武器影响，M0 行为不变
@export var speed_modifier: float = 1.0
# 下蹲速度（CS 固定 2.59，M1 任务3）：下蹲时豁免 speed_modifier，蹲速固定不受武器移速影响
@export var crouch_speed: float = 2.59
@export var acceleration := 8
@export var deceleration := 10
# 注意：F2 起空中加速改用 Source 投影式公式（见下方 AIR_* 常量），此参数仍未使用，
# 保留为未来空中控制比例扩展预留
@export_range(0.0, 1.0, 0.05) var air_control := 0.3
@export var jump_height := 7.54
# ── 空中控制（F2）：Source PM_AirAccelerate 投影式空中加速 ──────────────
# 公式（所有空中帧）：proj = 水平速度·wishdir；addspeed = wish_cap − proj；
#   addspeed > 0 时 velocity += wishdir × min(AIR_ACCELERATE × wish_cap × dt, addspeed)
# 有初速跑跳：proj ≫ wish_cap → 天然零加速（CS 手感：跳跃不增加速度）；
# 原地跳 REST 档：≤ AIR_WISH_CAP_REST 的空中转向微调（Source air-strafe 特性保留）。
# 参数出处：AIR_ACCELERATE = CS sv_airaccelerate 12；RUN 档 wish 帽 = 30u/s = 0.76m/s
#   （Quakeworld/Source 权威 air wishspeed）；REST 档 3.0 为手感调参（≤半速，不给
#   bhop 能量源——第 2 跳起起跳速度 ≥0.5 自动回落 RUN 档，无叠速链）。
const AIR_WISH_CAP_RUN := 0.76
const AIR_WISH_CAP_REST := 3.0
const AIR_ACCELERATE := 12.0
const REST_TAKEOFF_THRESHOLD := 0.5
var _air_wish_cap := AIR_WISH_CAP_RUN   # 起跳瞬间定档（按起跳时水平速度，见跳跃分支）
# 移动机制修订标识（X1）——任何移动语义变更（台阶高度/空中控制/速度模型等）必须
# bump 此值：JumpRecorder.setup 用它参与地图哈希，自动触发跳跃记录重置铁律，
# 防旧物理录像与新物理混存（布局哈希不变但移动语义已变）。
const MOVEMENT_REV := "move-r2:step0.62,air-rest3.0/run0.76"
# 自动登台（F1）：on_floor + 水平移动时，高差 ≤ STEP_MAX 视为斜坡直接走上去。
# 取值 0.62 的依据与 CS 偏离说明见 _try_step_up() 头部注释。
const STEP_MAX := 0.62
var direction := Vector3()
var input_axis := Vector2()
# 下蹲状态（M1 任务3）：由 Crouch.gd 进入/退出下蹲时联动设置；下蹲时加速目标用 crouch_speed 固定
var is_crouching: bool = false
# 移动状态（M1 任务8 精度模型）：水平速度 > 0.1 m/s 时 true（_physics_process 更新）——
# WeaponCore 散布惩罚查询（move_spread_multiplier）；不依赖输入轴（斜坡滑行等实际位移也算移动）
var is_moving: bool = false
# Get the gravity from the project settings to be synced with RigidDynamicBody nodes.
@onready var gravity: float = (ProjectSettings.get_setting("physics/3d/default_gravity")
		* gravity_multiplier)


# Called every physics tick. 'delta' is constant
func _physics_process(delta: float) -> void:
	input_axis = Input.get_vector(&"move_back", &"move_forward",
			&"move_left", &"move_right")

	direction_input()

	# 落地钳制（防 bhop）需要：记录 move_and_slide 之前的接地状态
	var was_on_floor := is_on_floor()

	if is_on_floor():
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = jump_height
			# 空中控制定档（起跳瞬间一次写入，F2）：起跳时水平速度 < 阈值 = 原地跳
			# → REST 档（可空中转向）；否则跑跳 → RUN 档（proj≫cap 天然零加速）
			var takeoff_speed := Vector2(velocity.x, velocity.z).length()
			_air_wish_cap = AIR_WISH_CAP_REST \
					if takeoff_speed < REST_TAKEOFF_THRESHOLD else AIR_WISH_CAP_RUN
	else:
		velocity.y -= gravity * delta

	accelerate(delta)

	_try_step_up(delta)
	move_and_slide()
	# 落地钳制（防 bhop，F2）：非接地→接地过渡帧水平速度 > 基础 speed → 钳回 speed。
	# 拦空中叠速（air-strafe/bhop 能量链）；正常跑跳落地速度 ≈ speed 不触发，
	# step-up 登台帧 was_on_floor 为真同样不触发。
	if is_on_floor() and not was_on_floor:
		var land_h := Vector2(velocity.x, velocity.z).length()
		if land_h > speed:
			var land_scale := speed / land_h
			velocity.x *= land_scale
			velocity.z *= land_scale
	# P1：缓存最近一次自由行走（在地板、未撞墙）的速度幅值——撞墙帧 move_and_slide
	# 会把 velocity 写回清零并由 accelerate 低速重建，登台步幅预算须用撞墙前的真实
	# 行走速度，否则登台退化为蠕动
	if is_on_floor() and not is_on_wall():
		_walk_speed = Vector2(velocity.x, velocity.z).length()
	_update_is_moving()


func _update_is_moving() -> void:
	# 水平速度 > 0.1 m/s = 移动中（精度模型散布惩罚查询；阈值参数与 brief 一致）
	var horizontal := Vector2(velocity.x, velocity.z).length()
	is_moving = horizontal > 0.1


func direction_input() -> void:
	direction = Vector3()
	var aim: Basis = get_global_transform().basis
	direction = aim.z * -input_axis.x + aim.x * input_axis.y


func accelerate(delta: float) -> void:
	# Using only the horizontal velocity, interpolate towards the input.
	var temp_vel := velocity
	temp_vel.y = 0

	# 空中（含起跳瞬间）：Source PM_AirAccelerate 投影公式独立分支（不改变垂直
	# 分量）——有初速跑跳 proj≫cap 天然零加速；原地跳 REST 档获得 ≤cap 转向微调
	# （公式与参数出处见 AIR_* 常量注释）。地面 lerp 逻辑完全不变。
	if not is_on_floor() or velocity.y > 0.0:
		if direction.length_squared() > 0.0:
			var wishdir := direction.normalized()
			var proj := temp_vel.dot(wishdir)
			var addspeed := _air_wish_cap - proj
			if addspeed > 0.0:
				temp_vel += wishdir \
						* minf(AIR_ACCELERATE * _air_wish_cap * delta, addspeed)
		velocity.x = temp_vel.x
		velocity.z = temp_vel.z
		return

	var temp_accel: float
	# 下蹲豁免 speed_modifier（CS：蹲速固定 2.59，不受武器移速影响——任务2 审查移交约束）；
	# 站立时用 走速 × 武器移速倍率
	var effective_speed: float = crouch_speed if is_crouching else speed * speed_modifier
	var target: Vector3 = direction * effective_speed

	if direction.dot(temp_vel) > 0:
		temp_accel = acceleration
	else:
		temp_accel = deceleration

	var accel_weight = clamp(temp_accel * delta, 0.0, 1.0)
	temp_vel = temp_vel.lerp(target, accel_weight)

	velocity.x = temp_vel.x
	velocity.z = temp_vel.z


# ── 自动登台（F1 机制，F2a 加固）─────────────────────────────────
# STEP_MAX = 0.62 的依据 + CS 权威值偏离注记：
#   本项目台阶几何为 0.6m 级（AI navmesh 与方块视觉需求），0.62 覆盖全部
#   0.6m 坡道级 / 0.3m 微台阶 / 0.6m 摊阁台阶；V3.COVER_CROUCH(0.9)m 箱保持
#   只能跳上（设计意图不变）。CS 权威 step-up 18u=0.457m 不适用——它低于本
#   项目最小台阶档 0.6m，照搬会导致楼梯仍需跳跃，违背"一定高低差内视为斜坡
#   自由通行"的需求。
# 机制（move_and_slide 之前；is_on_floor + 前进意图 + is_on_wall(上一帧结果) 门控）：
#   相位2 先行：探针（STEP_MAX 抬升 + 本帧步幅）向下垂射线找落点高度——
#          只采纳法线 ≥cos(floor_max_angle) 的可行走面（P3：与引擎地板判定同源），
#          落点高于当前脚底 ≤STEP_MAX 才吸附登台（只升不降、0.9 箱顶面拒绝）；
#   相位1：抬升净空三连静态重叠查询（起点/路径/落点）——被挡（高箱 / 低净空
#          顶板 / 手雷嵌体）即放弃；
#   登台：水平进度限制在本帧预算内（P1），落点抬高 0.02 交给沉降（P4），随后
#          同帧 move_and_slide 以行走速度 + floor snap 动态越过棱线。
# F2a-P1 速度耦合（2026-08-12）：每帧 step-up 的水平进度不得超过玩家实际前进
#   步幅——advance = maxf(_walk_speed*delta, 0.02)（撞墙前的真实行走速度；撞墙帧
#   move_and_slide 会把 velocity 写回清零，不可用；低速保底只为探针数值有效，落点
#   仍受预算约束）；落点水平预算 = advance + STEP_EDGE_INSET（越棱必需量），棱线
#   在预算内时落点收紧到棱线内侧 inset。贴墙帧玩家已被上一帧 move_and_slide 停住，
#   登台瞬移 ≤ advance+inset（走速 0.156），同帧后续前进发生在台面之上——多级
#   台阶不再连锁突进，登台节奏 = 行走节奏。落点跨越棱线的 overhang 由同帧
#   move_and_slide 的 snap+前进动态跨过（静止坐在 overhang 上会被棱凸角推回，
#   实测相位敏感卡滞——step-up 必须保持在 move_and_slide 之前）。
# F2a-P2 查询一致性：所有查询 mask = collision_mask（与身体 move_and_slide 同源
#   =3）；intersect_shape 结果过滤 torso/head 组（敌人不是地形）；intersect_ray
#   命中敌人体 → 该 RID 加 exclude 重放一次。墙门控同样排除敌人（贴敌不登台，
#   防登台-滑落循环）。
# F2a-G1 滑翔跨隙守卫：floor_snap_length 吸附滑翔（走离边缘后 ~snap 长度内
#   is_on_floor 仍真、无真实碰撞）可让探针够到相邻高台跨隙瞬移——登台前下查
#   底缘前缘正下方，支撑面深度超过 floor_snap_length（悬挑跨隙）即放弃。
# F2a-G2 中段穿透守卫：起点/路径/落点三查之外，补"当前→落点"中点抬升重叠查询。
# F2a-G3 立面判定封坡道：触发墙与棱线命中都要求法线 y<0.5（近垂直）——坡面
#   （含 20° 坡走廊、陡坡立面 45°-60° 分量）不触发登台，交给 move_and_slide。
# Godot 4.7 API 注记：intersect_shape 为静态重叠查询（不沿 motion 扫描、返回无
#   position/normal）；cast_motion 扫掠只返回命中分数且胶囊底半球贴棱时高度偏低。
#   故相位1 用静态查询覆盖扫掠体（水平总位移 ≤0.156 « 胶囊直径 1.0，无隧穿
#   可能），相位2 用 intersect_ray 直接命中台面平面取真值高度。
const STEP_DOWN_EXTRA := 0.2   # 相位2 向下余量
const STEP_MIN_ADVANCE := 0.02  # 最小前移量（极低速时保证探针数值有效）
const STEP_MIN_RISE := 0.01    # 只升不降阈值（防平地抖动/反复触发）
const STEP_CAST_MARGIN := 0.001  # 查询 margin：默认 0.04 会误判（0.62-0.04<0.6 卡台阶顶）
const STEP_LANDING_LIFT := 0.02  # P4 落点抬高量（brief 预案 0.01→0.02 微调，实测依据见下）
const STEP_EDGE_INSET := 0.05  # 登台落点越过台阶棱线的距离（越棱必需量）
const STEP_WALL_NORMAL_Y := 0.5  # G3：台阶立面判定阈值——阻挡面/棱线法线 y<0.5（近垂直）
                                 # 才算台阶立面；≥0.5 为坡面/台面，登台交给 move_and_slide

# P5a：碰撞节点 _ready 缓存（Crouch 只改 shape 的 height/center 不换子节点，缓存安全）
@onready var _col_cached: CollisionShape3D = _find_collision_shape()
# P5b：查询参数对象复用——每帧只改 transform/from/to/exclude，不每帧 new
var _shape_params := PhysicsShapeQueryParameters3D.new()
var _ray_params := PhysicsRayQueryParameters3D.new()
var _query_exclude: Array[RID] = []
# P1：最近自由行走速度幅值（撞墙前真实步幅——move_and_slide 撞墙会把 velocity
# 写回清零，不能用撞墙后速度做登台预算）
var _walk_speed := 0.0


func _ready() -> void:
	# P5b：exclude 建 [自身RID] 复用（敌人 RID 重试时临时追加）；
	# P2：查询 mask 与身体 move_and_slide 的 collision_mask 同源（=3：Objects+Player）
	_query_exclude = [get_rid()]
	_shape_params.margin = STEP_CAST_MARGIN
	_shape_params.collision_mask = collision_mask
	_shape_params.exclude = _query_exclude
	_ray_params.collision_mask = collision_mask
	_ray_params.exclude = _query_exclude


func _try_step_up(delta: float) -> void:
	# 空中绝不触发；起跳上升帧（velocity.y>0）不触发，避免吞掉跳跃冲量。
	# 本函数在 move_and_slide 之前调用：is_on_floor()/is_on_wall() 读上一帧
	# move_and_slide 的结果——首次撞墙帧玩家已被停住，本帧登台，无可感知延迟；
	# 登台瞬移后同帧 move_and_slide 立即以行走速度+floor snap 越过棱线（动态
	# 跨棱；若在 move_and_slide 之后瞬移，胶囊会静止坐在棱凸角上被推回，实测卡滞）。
	if not is_on_floor() or velocity.y > 0.0:
		return
	# P5c：未撞墙跳过整套查询（平地行走零开销）。P2 同源：敌人不是地形——
	# 贴住敌人（torso/head）不算可登台的墙，否则贴敌帧反复触发登台-滑落循环
	if not _has_terrain_wall():
		return
	# 前进意图门控：撞墙后 accelerate 每帧从输入重建速度——无前进输入时重建值
	# 为 0，不触发登台（贴墙站立不会被抬上台阶）
	var hvel := Vector2(velocity.x, velocity.z)
	if hvel.length() <= 0.1:
		return
	var col := _col_cached
	if col == null:  # P5a：lazy 兜底（缓存为 null 时首次使用再扫一次）
		col = _find_collision_shape()
		_col_cached = col
	if col == null:
		return
	var capsule := col.shape as CapsuleShape3D
	if capsule == null:
		return

	var space_state := get_world_3d().direct_space_state
	var dir := Vector3(hvel.x, 0.0, hvel.y).normalized()
	# P1：水平进度与玩家速度耦合——advance = 撞墙前真实行走步幅（_walk_speed，
	# 撞墙帧 move_and_slide 写回清零的 velocity 不可用）；低速保底见
	# STEP_MIN_ADVANCE 注记（保底只为探针数值有效，落点仍受预算约束）。
	var advance := maxf(_walk_speed * delta, STEP_MIN_ADVANCE)
	var half_height: float = capsule.height * 0.5
	# shape 查询变换 = 真实胶囊世界变换（含 CollisionShape3D 本地偏移，
	# 与 Crouch.gd 动态改胶囊高度/中心的联动保持一致）
	var capsule_xform := global_transform * col.transform
	var feet_y: float = capsule_xform.origin.y - half_height
	# P3：地板法线阈值读自身 floor_max_angle——与 move_and_slide 引擎地板判定同源
	# （jump_recorder.gd 的 _floor_normal_y 同源于 player.floor_max_angle）
	var floor_normal_y := cos(floor_max_angle)

	# G1：防 snap-glide 悬挑跨隙——地板吸附滑翔（走离边缘后 floor_snap_length 内
	# is_on_floor 仍真但无真实支撑）可让探针够到相邻高台触发跨隙瞬移。守卫：
	# 底缘前缘正下方的支撑面必须落在 floor_snap_length 深度内（真实登台：地板
	# 连续延伸到墙脚，深度≈0；跨隙悬挑：墙脚下方是深坑）。注意不能用"上一帧
	# 是否有地板碰撞"判定——贴墙行走帧地板支撑同样不上报碰撞（实测更正：静止
	# 帧有上报，行走帧没有）。
	var gap_from := capsule_xform.origin + dir * (capsule.radius - 0.05)
	gap_from.y = feet_y + 0.02
	_ray_params.from = gap_from
	_ray_params.to = gap_from + Vector3.DOWN * (floor_snap_length + 0.05)
	var gap_hit := _ray_with_enemy_retry(space_state)
	if gap_hit.is_empty() or gap_hit.position.y < feet_y - floor_snap_length:
		return

	# 相位2（先行）：探针 = STEP_MAX 抬升 + 本帧步幅，向下垂射线找落点高度。
	# 探针偏移 [0, 前进方向满半径]：贴墙时满半径探针恰越过台阶棱线命中台面。
	var probe_origin := capsule_xform.origin + Vector3.UP * STEP_MAX + dir * advance
	var probe_top_y: float = probe_origin.y - half_height + 0.001
	var ray_len: float = STEP_MAX + STEP_DOWN_EXTRA
	var best_y := -INF
	var probe_offsets: Array[Vector3] = [Vector3.ZERO, dir * capsule.radius]
	for offset in probe_offsets:
		var from: Vector3 = probe_origin + offset
		from.y = probe_top_y
		_ray_params.from = from
		_ray_params.to = from + Vector3.DOWN * ray_len
		var hit := _ray_with_enemy_retry(space_state)
		if not hit.is_empty() and hit.normal.y >= floor_normal_y \
				and hit.position.y > best_y:
			best_y = hit.position.y
	if best_y == -INF:
		return
	# 只升不降：走下台阶/平地不干扰
	if best_y - feet_y <= STEP_MIN_RISE:
		return
	# 命中面高于抬升上限（探针中心下射可命中抬升体以上的面，如 0.9 箱顶）→ 不是台阶
	if best_y - feet_y > STEP_MAX:
		return

	# P1：落点水平预算 = 本帧步幅 + 越棱必需量（棱线内侧 STEP_EDGE_INSET）。
	# 棱线在预算内时落点收紧到棱线内侧 inset，不越棱超预算；贴墙帧玩家已被墙
	# 停住（上一帧 move_and_slide 结果），登台瞬移 ≤ advance+inset ≤ 0.156（走速），
	# 同帧 move_and_slide 的后续前进发生在台面之上——多级台阶无连锁突进。
	var landing_dist := advance + STEP_EDGE_INSET
	var edge_from := capsule_xform.origin
	edge_from.y = best_y - 0.05
	_ray_params.from = edge_from
	_ray_params.to = edge_from + dir * landing_dist
	var edge_hit := _ray_with_enemy_retry(space_state)
	if not edge_hit.is_empty():
		# G3：命中的是坡面（法线 y≥0.5）而非台阶立面 → 放弃登台，交给
		# move_and_slide 正常爬坡（封真坡道逐帧瞬移）
		if edge_hit.normal.y >= STEP_WALL_NORMAL_Y:
			return
		landing_dist = minf(landing_dist,
				(edge_hit.position - edge_from).dot(dir) + STEP_EDGE_INSET)

	# P4：落点抬高 0.02 交给 floor snap / 重力沉降。取值依据（brief 预案 0.01→0.02
	# 微调）：登台落点跨越台阶棱线（overhang），底缘圆周与台面同高过棱时必然撞上
	# 棱凸角（斜向接触法线把胶囊推回台阶下、丢地板态，相位敏感卡滞）；抬高 0.02
	# 后底缘越过棱角上方（> margin+求解容差），无角接触，沉降后平贴台面。0 间隙
	# 方案实测同样失败：贴合位出发的高度 0 扫掠无法命中台面（snap 空转悬停后坠落）。
	# 站稳后 rise=0，被"只升不降"守卫拦下，无重触发循环。
	var lift: float = best_y + STEP_LANDING_LIFT - feet_y
	var raised := capsule_xform
	raised.origin += Vector3.UP * lift

	# 相位1：抬升净空三连查（起点/路径终点/落点，均按落点抬高后的变换查询——
	# 落点本身抬高 0.02 » 查询 margin 0.001，不会把台面误判为重叠）——高箱、
	# 低净空顶板、落点嵌体（如手雷落台阶边）即放弃。水平总位移 ≤0.156 « 胶囊
	# 直径 1.0，静态查询无隧穿。
	_shape_params.shape = capsule
	_shape_params.transform = raised
	if not _shape_filtered(space_state).is_empty():
		return
	var raised_fwd := raised
	raised_fwd.origin += dir * advance
	_shape_params.transform = raised_fwd
	if not _shape_filtered(space_state).is_empty():
		return
	if landing_dist > advance:
		var landing_xform := raised
		landing_xform.origin = raised.origin + dir * landing_dist
		_shape_params.transform = landing_xform
		if not _shape_filtered(space_state).is_empty():
			return
	# G2：中段穿透检查——当前位置→落点中点再做一次抬升重叠查询，拦薄几何
	# （细柱/栏杆）中段穿透（水平位移 ≤0.156 « 胶囊直径，两端查已覆盖大部分，
	# 此查为保险层）
	var mid_xform := raised
	mid_xform.origin = raised.origin + dir * (landing_dist * 0.5)
	_shape_params.transform = mid_xform
	if not _shape_filtered(space_state).is_empty():
		return

	global_position += dir * landing_dist + Vector3.UP * lift
	velocity.y = 0.0


## P2：intersect_shape 结果过滤 torso/head 组碰撞体（敌人不是地形，不阻挡登台查询）
func _shape_filtered(space_state: PhysicsDirectSpaceState3D) -> Array:
	var results := space_state.intersect_shape(_shape_params)
	var filtered: Array = []
	for r in results:
		if _is_enemy_collider(r.get("collider")):
			continue
		filtered.append(r)
	return filtered


## P2：intersect_ray 命中敌人体（torso/head）→ 该 RID 加 exclude 重放一次（最多一次）
func _ray_with_enemy_retry(space_state: PhysicsDirectSpaceState3D) -> Dictionary:
	_ray_params.exclude = _query_exclude
	var hit := space_state.intersect_ray(_ray_params)
	if hit.is_empty() or not _is_enemy_collider(hit.get("collider")):
		return hit
	var enemy: Object = hit["collider"]
	_query_exclude.append(enemy.get_rid())
	_ray_params.exclude = _query_exclude
	hit = space_state.intersect_ray(_ray_params)
	_query_exclude.remove_at(_query_exclude.size() - 1)
	_ray_params.exclude = _query_exclude
	return hit


func _is_enemy_collider(collider: Variant) -> bool:
	var body := collider as Object
	return body != null and (body.is_in_group(&"torso") or body.is_in_group(&"head"))


## P5c/P2/G3：上一帧 move_and_slide 碰撞中是否存在"近垂直地形墙"碰撞。
## 条件：法线 y < STEP_WALL_NORMAL_Y（近垂直面才算台阶立面——G3：坡面/斜面
## 法线 y≥0.5 不触发登台，封死真坡道逐帧瞬移；y≥0.5 也天然排除地板类碰撞）
## 且非 torso/head 敌人（P2：敌人不是地形）。
func _has_terrain_wall() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y >= STEP_WALL_NORMAL_Y:
			continue  # 地板/坡面类：非台阶立面
		if _is_enemy_collider(c.get_collider()):
			continue  # 敌人不是地形
		return true
	return false


func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null
