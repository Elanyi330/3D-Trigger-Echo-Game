# M2 手感修复轮 brief 汇编（归档）

> **日期**：2026-08-12
> **背景**：用户 v3 实机反馈三点——①台阶不跳上不去（0.6m 台阶全图皆是）②静止起跳纯垂直、无法跳上身旁障碍 ③两侧市街长廊太空、集火效果差。控制器调研定稿后拆为 F1（step-up）→ F2a（step-up 加固×2 轮）→ F2b（空中控制 + MOVEMENT_REV）→ F3（横脊墙）→ F5（台阶手感微调）→ F6（收尾）六个实现任务，全部子代理驱动 + 逐任务审查。
> **提交链**：F1 `4abaa98` → F2a 加固 `4f16592` → F2a 守卫二轮 `1bf12d5` → F2b 空中控制+失效键 `87c19d9` → F3 初版 `e932b62`+`2abea33` → F3 返工 `07352f3` → F5 手感微调 `dd1ca1b` → F6 收尾 `33daf67` → F7 门柱再缩短 `4e87d05` → F8 横脊墙缩短 `71d57d9`（F4 为文档收尾无代码提交；F9 文档收尾另见本文件末）
> **关键裁决**：
> 1. step-up 取 0.62m：覆盖 0.6m 坡道级/0.3 微台阶/0.6 摊阁台阶；0.9m 箱保持只能跳上。CS 权威 18u=0.457m 因本项目台阶几何为 0.6m 级（AI navmesh 与方块视觉需求）而偏离，注释留档。
> 2. 空中控制定 Source PM_AirAccelerate 投影式 + 起跳定档（REST 3.0 / RUN 0.76）+ 落地钳制 6.35 防 bhop；同轮裁决追加 **MOVEMENT_REV 移动机制版本失效键**——移动语义变更必须 bump，与布局哈希共构跳跃记录重置键；跳高口径按生产实测修正为 1.51±0.05（probe_jump 1.39 为理想化积分序）。
> 3. **F3 缺口门墙数学不可能裁决**：2.5m 外环豁口 + 1.0m 满宽门墙 + 两端留通道 = 两端各 <1.2m 窄缝红线，数学不可能。初审（review-f3）否决封豁事故 → 返工指令：**删除缺口门墙×4、豁口恢复全通行、横脊墙规格钉死、probe_v3_walk 连通性门禁强化（瞬移仅许起点 1 次，超限 EXIT 失败）** → 复审（review-f3b）PASS。
> 4. ⚠️ **F3 部分注记：缺口门墙×4（EastGapWallN/S、WestGapWallN/S）已在返工中删除（07352f3），下文 F3 brief 中的门墙坐标作废**；仅横脊墙×4（EastSpurN/S、WestSpurN/S）有效。
> 5. 确立教训（已入 HANDOFF §五）：窄缝扫描角部盲区——"扫描绿≠可通行"，由探针连通门禁兜底；加墙必须给通行留 ≥1.2m 或完全不放。
> 6. **F5（用户实测反馈，dd1ca1b）**：三点卡顿根因——①摊阁台阶↔门柱 0.45m 夹缝（scan_gaps 垂直阈值盲区）②微台阶逐级去穿透振荡 ③首接触帧墙门控读上一帧碰撞停 16ms/级。修复：门柱 z 3→2.25 留 1.2m 通道（布局唯一改动）+ 同帧连锁登台（B1）+ 首帧登台（B2 脚部前向探针）+ PACE 0.2 落点钳制（brief 外新增，实测 0.258→0.2）。
> 7. **F6（收尾）**：MOVEMENT_REV bump r3（F5 登台语义变更，铁律）——与布局哈希（门柱尺寸变）双键双保险；探针 advance 公式对齐 + P5c 注释更新；文档基线 275 同步。
> 8. **F7（用户二次反馈，4e87d05）**：摊阁台阶↔门柱 1.2m 通道仍卡（玩家 1.0m 仅两侧 0.1m 余量，斜向登台擦柱）→ 柱深 2.25→1.5 留 1.95m 通道（仅门柱 4 根，旋转对称硬约束）；偏差：test_belt_pavilions 同步/注释同步。
> 9. **F8（用户实测定位，71d57d9）**：EastSpurS/WestSpurN 墙头↔塔坡道绕墙通道仅 1.0m（零余量）→ 长 3→2m 留 2.0m 通道；偏差：center 16→15.5（墙贴 rim 面不动，唯一解）；EastSpurN/WestSpurS 不动。
> 10. **用户实机验收 PASS（2026-08-13）**："地图十分完美，各个地方都符合我的要求"——F9 文档收尾（基线 276 同步、HANDOFF/FEATURES/PROGRESS/README/记忆、本文件追加 F7/F8 brief）。

---

# ═══════════ F1 brief（原文） ═══════════

# 修复 F1 brief —— MovementController 自动登台（step-up 0.62m）

## 背景（根因已查实）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。v3 地图楼梯/坡道是 0.3-0.6m 台阶盒，CharacterBody3D 的 move_and_slide 对垂直台阶零处理 → 玩家上下楼梯必须跳跃，手感差。
用户要求："一定高低差内，玩家可以自由从一个平面移动到另一个平面，视为斜坡"。
调研结论（已定稿）：step-up = **0.62m**（覆盖全部 0.6m 坡道级/0.3 微台阶/0.6 摊阁台阶；0.9m 箱保持只能跳上——设计意图不变）。CS 权威值 18u=0.457m 不适用，因本项目台阶几何为 0.6m 级（AI navmesh 与方块视觉需求），注释记录该偏离理由。

## 机制设计（Player/MovementController.gd）
```
const STEP_MAX := 0.62
```
在 _physics_process 中，当 is_on_floor() 且水平速度 >0.1 时尝试登台（move_and_slide 之前）：
1. 相位 1：把胶囊从"抬升 STEP_MAX 的位置"沿水平速度方向 shape-cast（PhysicsShapeCastParameters3D，exclude 自身，mask=1 Objects 层）——有碰撞 = 上方路径被挡，放弃
2. 相位 2：从抬升+前移位置向下 shape-cast（STEP_MAX + 0.2 余量）——找到地面 → 把 global_position 落到命中点上的站立位（胶囊原点），velocity.y = 0，随后 move_and_slide 正常继续
3. 空中（非 on_floor）绝不触发（防下落贴墙瞬移上高台）
4. 注意胶囊 CollisionShape3D 的本地偏移（读 Player.tscn/MovementController.tscn 实际 shape position）；shape-cast 的 transform 必须与真实胶囊一致

## TDD（test/unit/test_controller.gd 追加，沿用该文件既有物理测试模式——若现有模式是纯逻辑非物理，则新建 test_step_up.gd 用真实场景：地面 StaticBody + 台阶盒 + MovementController 实例，wait 物理帧）
RED 用例（先写先红）：
1. `test_step_up_climbs_06()`：平地 + 0.6m 台阶盒；玩家朝台阶持续输入前进（直接设 input_axis 或模拟 Input action），无跳跃输入；若干物理帧后玩家在台阶顶上（y ≈0.6±0.05）且 is_on_floor——**不跳自动登上**
2. `test_step_up_micro_stairs()`：0.3→0.6 两级微台阶，同样走上顶
3. `test_step_up_blocked_by_09()`：0.9m 箱——同样输入后玩家仍在箱底（x 无越过箱体），不上去
4. `test_step_up_low_ceiling()`：0.6 台阶上方 1.0m 处有顶板（净空 < 玩家高）——不触发登台（不嵌进顶板）；玩家位置 y < 0.6
5. `test_no_step_up_airborne()`：玩家从高处下落经过台阶侧面（初速向下、水平推向台阶）——不触发登台（落地在台阶旁地面 y≈0）
6. `test_step_down_smooth()`：从 0.6 台面向前走下——落地后 is_on_floor 恢复，无异常弹跳（y 单调下降至 0±0.1）
GREEN：实现至全绿 + 既有 test_controller.gd 全绿（跳跃高度等既有行为零回归）。

## 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_step_up.gd   # （或既有文件）新用例全绿
godot --headless --path . -s addons/gut/gut_cmdln.gd    # 全套件绿（247+新增）
```
提交：`feat(move): 自动登台 step-up 0.62m——楼梯可行走上下（CS 18u 偏离注记 + 6 物理测试）`

## 禁止
- 不改跳跃垂直参数（jump_height/重力）；不改布局；不做清单外改动

## 报告格式
状态 + RED/GREEN 证据 + 验证输出 + 提交哈希 + 偏差/concern。

---

# ═══════════ F2a brief（原文） ═══════════

# 修复 F2a brief —— step-up 加固轮（审查深验 5 类问题修复）

## 背景
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。F1（step-up 0.62m，提交 4abaa98）经多视角深验发现 5 类问题，本轮全部修复。**只改 Player/MovementController.gd + Levels/M2_TDM/jump_recorder.gd（仅法线常量）+ test/unit/test_controller.gd，不加新功能（空中控制是下一任务）**。

## 问题与修复（全部必做）

### P1【严重·手感】step-up 瞬移与速度脱钩 → 爬台阶连锁突进
现状：探针 advance 与目标落点与玩家速度无关，每帧可水平瞬移 ~0.55m → 走上多级台阶时每 1-3 帧登一级，塔坡 10 级 ~0.2s 登完（等效 30m/s）。
修复原则：**每帧 step-up 的水平进度不得超过玩家实际前进步幅**——probe advance = maxf(hvel.length() * delta, 0.02)（低速保底防探针退化）；抬升探测、边缘射线、落点目标全部限制在"当前帧前进量 + 越棱必需量（棱线内侧 STEP_EDGE_INSET）"内；若本帧前进量不足以越过棱线 → 本帧不登台（下帧累积再来）。效果：登台节奏 = 行走节奏，平滑无突进。
注意：低速保底 0.02 只为探针数值有效，落点仍受棱线位置约束，不允许用保底制造超幅位移。

### P2【正确性】查询 mask 与身体不一致 + 敌人阻塞登台
现状：4 处查询硬编码 mask=1，身体 move_and_slide mask=3；敌人（StaticBody3D layer 1，group "torso"/"head"）会被 step 查询看到 → 波次敌人站台阶边即卡死登台；手雷（RigidBody3D layer 2）查不到 → 瞬移进雷体再被引擎推出。
修复：所有 step 查询 mask 改 `collision_mask`（身体自身值 3）；intersect_shape 结果**过滤掉** is_in_group("torso")/is_in_group("head") 的 collider（敌人不是地形）；intersect_ray 若命中敌人体：把该 RID 加入 exclude 重放一次（最多一次重试）。效果：手雷落台阶边 → 自然阻挡登台（物理合理）；敌人贴台阶 → 不阻挡不嵌入。

### P3【正确性】法线阈值与引擎地板判定不一致
现状：STEP_FLOOR_NORMAL_Y=0.7（严格 >）≈ 接受 45.57° 坡，宽于 move_and_slide 默认 floor_max_angle 45°（cos 0.7071）→ 边界坡度面上 step-up 认为是地板、引擎认为是墙 → 振荡。
修复：控制器改为 `cos(floor_max_angle)`（读自身属性，不硬编码）；**同步改 jump_recorder.gd 的 FLOOR_NORMAL_Y**：改从 player.floor_max_angle 计算（recorder 持有 _player 引用，setup 时存 ` _floor_normal_y := cos(player.floor_max_angle)`），两处注释互相引用说明同源。

### P4【手感】落点 0 间隙嵌入 → 每级台阶着陆抖动
现状：落点精确 0 间隙在棱凸角上，move_and_slide 每帧先做去穿透恢复 → 抖动/吞滑动帧。
修复：落点目标抬高 0.01m（交给 floor_snap_length 吸附），嵌入防护查询保留；若实现发现 0.01 引入新问题可微调至 0.02，注释说明取值依据。

### P5【结构/性能】
a. `_find_collision_shape()` 每帧扫子节点 → 改缓存：`@onready var _col_cached: CollisionShape3D = _find_collision_shape()`；保留函数本体供 lazy 兜底（缓存为 null 时首次使用再扫一次）。注：Crouch 改的是 shape 的 height/center 不是子节点列表，缓存 NODE（非 shape）安全
b. 查询参数对象复用：PhysicsShapeQueryParameters3D 与 PhysicsRayQueryParameters3D 做成成员变量，每帧只改 transform/from/to/exclude，不每帧 new（exclude 数组在 _ready 建 `[get_rid()]` 复用，敌人 RID 重试时临时追加）
c. step-up 触发加门控：`is_on_wall()`（上一帧 move_and_slide 结果）为假时跳过整套查询（平地行走零开销；首次撞墙帧玩家已被 move_and_slide 停住，下帧登台无可感知延迟）

## 测试（test_controller.gd）
**重构**：before_each 改 `load("res://Player/MovementController.tscn").instantiate()`（删除 _production_capsule/_controller_collision/手镜像属性块/CAP_HALF 字面量推导——全部来自 tscn）；_make_floor 用 _make_box 表达（一个盒体构造器）；0.9 档引用 V3.COVER_CROUCH。
**新增用例**（RED 先行——对当前 HEAD 应先红）：
1. `test_step_up_pace_coupled()`：3 级台阶（级深 0.62 级高 0.6）以 6.35 行走登上——总耗时 ≥ (3×0.62)/6.35 ×0.8（不允许显著快于行走速度）；且过程中单帧水平位移 ≤ 0.2（无突进帧）
2. `test_step_up_enemy_not_blocking()`：台阶顶缘旁 0.3m 放 group "torso" 假敌人（StaticBody3D + CapsuleShape，layer 1）——登台成功（位置达台顶）
3. `test_step_up_grenade_blocks()`：台阶顶面放 layer 2 圆球刚体（模拟手雷，radius 0.15，置于登台落点）——不触发瞬移嵌入（断言：尝试登台 N 帧后玩家仍在地面或位置未与球体重叠；宽松断言防物理细节脆性）
4. `test_jump_frame_guard_locked()`：走向台阶同时按跳——跳跃冲量保留（velocity.y==7.54 帧存在），不被 step-up 吞掉
5. `test_crouch_step_up()`：胶囊手动改蹲姿尺寸（高 1.37 中心 -0.23，模拟 Crouch 行为）走向 0.6 台阶 + 2.0m 净空顶板——蹲姿登台成功（y≈0.6+0.685±0.05）
**既有 12 用例全部保持绿**（语义断言不动；若新机制改变帧数/容差，仅调整等待帧数类参数并注释原因）。

## 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_controller.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd
```
提交：`fix(move): step-up 加固——速度耦合/敌人过滤/手雷阻挡/法线同源/落点平滑/查询缓存（+5 测试）`

## 禁止
- 不加空中控制（下一任务）；不改布局；不改跳跃参数；P1-P5 外不动其他逻辑

## 报告格式
状态 + 逐项 P1-P5 落地说明 + RED/GREEN 证据 + 验证输出 + 提交哈希 + 偏差/concern。

---

# ═══════════ F2b brief（原文，含 X1/X2 追加项） ═══════════

# 修复 F2 brief —— 空中控制：Source 投影式加速 + 原地跳转向 + 落地钳制

## 背景（调研已完成，机制已定稿）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。当前 MovementController 空中零加速（temp_accel=0）→ 静止起跳纯垂直，无法跳上身旁障碍。
用户需求："无初速度起跳时空中可用方向键移动；有初速度起跳时跳跃不增加速度"。
调研定稿机制（Source PM_AirAccelerate 投影公式 + 起跳状态上限 + 落地钳制）：
- **投影公式**（所有空中帧）：`proj = 水平速度·wishdir；addspeed = wish_cap − proj；addspeed>0 时 速度 += wishdir × min(AIR_ACCELERATE × wish_cap × dt, addspeed)`——有初速跑跳时 proj≫cap → 天然零加速（CS 手感）；纯侧向输入获得 ≤cap 微调（CS air-strafe 特性保留）
- **起跳时定上限**：起跳瞬间水平速度 < REST_TAKEOFF_THRESHOLD(0.5) → 本跳 wish_cap = AIR_WISH_CAP_REST(3.0)（原地跳可空中转向 ~1.5m，足够跳上身旁障碍）；否则 wish_cap = AIR_WISH_CAP_RUN(0.76，=CS 30u)
- **落地钳制（防 bhop）**：落地瞬间水平速度 > 6.35（基础 speed）→ 钳回 6.35
- 参数依据：CS sv_airaccelerate=12、wish 帽 30u=0.76m/s（Quakeworld/Source 权威值）；REST 档 3.0 为手感调参（≤半速，不给 bhop 能量源——第 2 跳起跳速度 ≥0.5 自动回落 RUN 档，无叠速链）
- 代码注释注明来源（Source PM_AirAccelerate）与参数出处

## 实现（Player/MovementController.gd）
```gdscript
const AIR_WISH_CAP_RUN := 0.76
const AIR_WISH_CAP_REST := 3.0
const AIR_ACCELERATE := 12.0
const REST_TAKEOFF_THRESHOLD := 0.5
var _air_wish_cap := AIR_WISH_CAP_RUN   # 起跳时写入
```
- 跳跃触发处（现有 `if Input.is_action_just_pressed("jump")` 分支）：写入 `velocity.y = jump_height` 的同时：`_air_wish_cap = AIR_WISH_CAP_REST if Vector2(velocity.x, velocity.z).length() < REST_TAKEOFF_THRESHOLD else AIR_WISH_CAP_RUN`
- `accelerate()` 空中分支：把现有 `temp_accel = 0.0`（空中无加速）替换为投影公式（direction 非零时）；注意现有代码结构（temp_vel 水平投影 + lerp 逻辑），空中分支独立处理：`velocity += wishdir * min(AIR_ACCELERATE * _air_wish_cap * delta, addspeed)`，不改变垂直分量
- move_and_slide 后：若本帧从不接地→接地（is_on_floor() 且上帧非），水平速度 >speed 时钳制：`velocity.x/z *= speed/h_len`
- 保持地面加速逻辑完全不变

## TDD（test/unit/test_air_control.gd 新建，真实物理场景：地面 StaticBody + MovementController 实例）
RED 用例：
1. `test_rest_jump_steers()`：静止起跳 + 持续前输入 → 滞空期间水平速度从 0 增长（断言空中某帧 |v_h| > 1.0）；落点比起跳点前移 > 0.8m
2. `test_rest_jump_climbs_adjacent_box()`：静止站在 0.9m 箱旁（贴面），起跳 + 朝箱输入 → 落在箱顶（y≈0.9±0.1）——**用户核心场景**
3. `test_run_jump_no_accel()`：先加速到 6.35 跑动中起跳 + 持续同向输入 → 全程水平速度 ≤ 6.36（零加速）
4. `test_run_jump_lateral_micro()`：跑动中起跳 + 纯侧向输入 → 获得侧向分量（>0.3）但合速 ≤ 6.41（≤cap 微调保留）
5. `test_no_bhop_chain()`：静止起跳+前输入（REST 档）→ 落地立即再跳（模拟 just_pressed 或直设）→ 第 2 跳全程速度 ≤ 6.4；连续 3 跳后速度仍 ≤ 6.4（无叠速）
6. `test_landing_clamp()`：人为设置高空水平速度 8.0 落地 → 落地后速度 == 6.35±0.01
7. `test_jump_height_unchanged()`：垂直跳高行为零回归（最大高度 ≈1.39±0.05——同既有测试口径）
GREEN：全绿 + 既有全套件零回归。

## 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_air_control.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd
```
提交：`feat(move): 空中控制——Source 投影式加速/原地跳 REST 档转向/落地钳制防 bhop（7 物理测试）`

## 禁止
- 不加 jump buffer/coyote（YAGNI）；不改 F1 的 step-up；不改布局；不做清单外改动

## 报告格式
状态 + RED/GREEN 证据 + 验证输出 + 提交哈希 + 偏差/concern。

## 追加项（审查发现，本轮一并处理）

### X1. 记录器移动机制版本失效键（堵数据污染洞）
问题：step-up/空中控制改变了移动语义但布局哈希不变 → 旧物理录的 episode 与新物理混存，重置铁律拦不住。
修复：
- `JumpRecordCore.map_hash(solids: Array, movement_rev: String = "") -> String`：序列化末尾追加一行 `rev|<movement_rev>` 再 sha256（空串保持旧行为兼容测试）
- `MovementController` 增 `const MOVEMENT_REV := "move-r2:step0.62,air-rest3.0/run0.76"`（注释：移动机制修订标识——任何移动语义变更必须 bump 此值，触发跳跃记录重置）
- `JumpRecorder.setup()`：`JumpRecordCore.map_hash(layout_solids, player.MOVEMENT_REV if player else "")`（player 为 MovementController 类型读常量；manifest 结构不变）
- 测试（test_jump_record_core.gd 追加）：同 solids 不同 rev → 哈希不同；同 rev → 哈希相同
- 测试（test_jump_recorder.gd 追加）：预写 manifest 用旧 rev 哈希 + 假 episode → setup（新 rev）→ episode 被清、manifest 哈希为新值——**实证移动机制变更触发重置铁律**
- 注：本轮提交后用户实机启动会触发一次重置（live 目录清空）——用户 36 条已归档至 jump_training_archive_20260812_user36_v1physics，属预期行为

### X2. 注释修正（2 处，审查发现）
- MovementController.gd L210-211 附近："贴墙静止帧地板支撑同样不上报碰撞" → "贴墙**行走**帧"（静止帧有上报，实测更正）
- test_controller.gd `test_no_step_up_on_slope` 注释补一句归因说明：该构型实际由 G1 支撑射线拦截（坡体内射线空命中），G3 棱线法线分支为独立保险层（50° 立面场景实证有效）

### 验证追加
全套件绿（261+新增）后按原 brief 消息提交，消息追加"记录器移动机制版本失效键"：
`feat(move): 空中控制——Source 投影式加速/原地跳 REST 档转向/落地钳制防 bhop + 记录器机制版本失效键（N 物理测试）`

---

# ═══════════ F3 brief（原文；⚠️ 缺口门墙坐标已作废，见头部注记 4） ═══════════

# 修复 F3 brief —— 东西市街加高墙（8 面）+ 跳跃记录归档

## 背景（设计已定稿）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。用户反馈两侧市街（8.5×28m 长廊）太空、集火效果差 → 加高墙增加博弈空间。控制器已完成全部碰撞/门禁推演，坐标照抄即可。

## A. 跳跃记录状态确认（归档已由控制器完成）
用户 36 条 episode 已归档至 `jump_training_archive_20260812_user36_v1physics`（控制器在 F2a 前完成，**不要重复归档**）。MOVEMENT_REV 变更已使 live 目录在下次启动时重置。本任务布局变更会再次触发重置——在 D 的实机跑中确认日志出现"[JumpRecorder] 地图布局已变更，跳跃记录已重置"即可，报告 live 目录当前 episode 数（应为 0 或极少）

## B. STREETS 表新增 8 面高墙（kind "wall"，3m 高，照抄）
```
EastSpurN    center (16.0, 1.5, 7.1)   size (3.0, 3.0, 0.8)   # 横脊墙北：rim 侧伸入街中，x∈[14.5,17.5] z∈[6.7,7.5]
EastSpurS    center (16.0, 1.5, -7.1)  size (3.0, 3.0, 0.8)
EastGapWallN center (22.0, 1.5, 6.75)  size (1.0, 3.0, 2.5)   # 缺口门墙北：贴长墙内侧正对外环豁口 z∈[5.5,8]
EastGapWallS center (22.0, 1.5, -6.75) size (1.0, 3.0, 2.5)
WestSpurS    center (-16.0, 1.5, -7.1) size (3.0, 3.0, 0.8)   # = EastSpurN 180° 旋转
WestSpurN    center (-16.0, 1.5, 7.1)  size (3.0, 3.0, 0.8)   # = EastSpurS 180° 旋转
WestGapWallS center (-22.0, 1.5, -6.75) size (1.0, 3.0, 2.5)  # = EastGapWallN 旋转
WestGapWallN center (-22.0, 1.5, 6.75) size (1.0, 3.0, 2.5)   # = EastGapWallS 旋转
```
（命名与 _rot_pair 映射自洽：EastSpurN↔WestSpurS、EastSpurS↔WestSpurN、EastGapWallN↔WestGapWallS、EastGapWallS↔WestGapWallN）

## C. 测试同步
- STREETS 实体计数断言更新（east_count 26→30、总数等既有计数）；standable 面不变
- 全部门禁自动重跑（旋转对称/无重叠/boost gate/预算 ≤220 → 实际 197）——若有意外红，**不自行改墙坐标**，报告交控制器
- 新增 1 个断言（test_map_layout_v3.gd）：8 新墙全部 kind=="wall"、top==3.0、在各自市街带内（|x|∈[14,23.5]、|z|≤14）

## D. 全门禁复验（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd        # 全绿
python3 tools/scan_gaps_v3.py                                # 0 窄缝（新墙缝隙已推演为 0 或 ≥1.2）
godot --headless --path . -s res://tools/probe_v3_walk.gd    # 71/71（若路线撞新墙：仅允许微调途经点，报告记录）
godot --headless --path . -s res://tools/probe_sightlines.gd # 硬门控 0 对
godot --headless --path . -s res://tools/probe_timing.gd     # t∈[4,6.5]
godot --headless --path . Levels/M2_TDM/L_M2.tscn             # 10 秒无错误（启动时日志应出现"地图布局已变更，跳跃记录已重置"——铁律生效实证）
```

## E. 提交
`feat(m2v3): 东西市街加高墙×8——横脊墙+缺口门墙（跳跃记录已归档，重置铁律生效）`

## 禁止
- 不改墙以外任何布局；不改移动/记录器代码；不做清单外改动

## 报告格式
状态 + 归档确认 + 测试同步 + 六条门禁输出 + 重置日志实证 + 提交哈希 + 偏差。

---

# ═══════════ F5 brief（原文；2026-08-12 用户实测反馈） ═══════════

# 修复 F5 brief —— 台阶手感微调（用户实测反馈）+ 单墙微调

## 背景（用户验收反馈，根因已由控制器定位）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。用户反馈：①摊阁台阶处"十分卡顿"②祭坛微台阶"一点点卡顿"③两侧塔坡道普遍卡顿。
**用户红线：地图核心零改动，仅允许微调手感 + 一处墙体。** 本文档的布局改动仅限"墙"一项（门柱），其余全为 MovementController 登台逻辑（纯手感）。

## 根因（控制器数据定位）
① 市集带摊阁台阶 ↔ 钟门柱 0.45m 夹缝：`BeltN_PavStepE` x∈[2.75,4.25] z∈[11.8,12.55] vs `GateN_PillarE` x∈[1.25,5] z∈[13,16]——水平净距 0.45m（玩家宽 1.0 挤不过），登台落点胶囊后缘擦门柱面 → 被挤出卡死。scan_gaps 未捕获（台阶高 0.6 < 垂直重叠阈值 0.8）。
② 微台阶每级 0.3m 深：登台落点（棱线+0.05 内嵌）后胶囊前缘必然嵌入下一级台阶体积 → 引擎去穿透每帧挤出 → 抖动。
③ step-up 墙门控读上一帧碰撞：首接触帧无墙记录 → 停 16ms 再登 → 每级台阶一个微停顿（10 级塔坡 = 160ms 累计）。

## A. 布局改动（唯一：门柱缩短，0.75m）
`Levels/M2_TDM/map_layout_v3.gd` GATES 表 `_bell_gate(side)`：
- GateN_PillarE/W 与 GateS_PillarE/W 的 size.z：**3.0 → 2.25**，center.z 同步（门柱 z∈[13,16] → **[13.75,16]**，北门；南门镜像 z∈[-16,-13.75]）——靠广场侧收缩 0.75m
- 校验：门柱与摊阁台阶净距 0.45 → **1.2** ✓（恰合规）；过梁（z∈[12.75,16.25]）不动仍覆盖柱顶；门柱与摊阁（z∈[10,11.8]）间距保持；旋转对称保持（size.z 2.25、center.z 变化在生成器内同步）
- 注释：2026-08-12 用户验收反馈——摊阁台阶夹缝 0.45m 卡顿，柱深 3→2.25 留 1.2m 通道

## B. 手感修复（MovementController.gd，纯登台逻辑）
### B1 同帧连锁登台（修②）
`_try_step_up` 当前单级：落点嵌入下一级 → 抖动。改为：登台后检测落点是否仍与前方台阶体积重叠（胶囊前缘嵌入检测），若嵌入且剩余高度预算允许（累计上升 ≤ STEP_MAX），**同帧继续登下一级**（循环最多 2 级：0.3+0.3=0.6 ≤0.62 恰覆盖微台阶双级；摊阁 0.6 单级不受影响）。实现注意：复用地形墙/棱线探测，防无限循环（每级上限 2 次）；注释说明"等效斜坡"意图。
### B2 首帧登台（修③）
当前墙门控 `_has_terrain_wall()` 读上一帧 move_and_slide 碰撞——首接触帧无记录。改为：**脚部前向探针**——当前帧从脚底（feet_y+0.02）向移动方向投射短射线（长度 = advance + 胶囊半径 + 0.2），命中近垂直地形面（法线 y<0.5）即视为墙（等效首帧门控）；保留原 slide 碰撞门控作为补充（任一通过即触发）。首帧登台后正常流程不变。
- 注意：探针不得误触手雷/敌人（torso/head 过滤沿用）、不得在平地假阳性（平地前方无台阶立面，射线不命中）。

## C. 测试（test_controller.gd 追加/更新）
RED 先行：
1. `test_micro_stairs_no_jitter()`：0.3→0.6 双级微台阶，行走登上——过程无振荡（每帧 y 单调非降，或登台完成后连续 N 帧 y 稳定 ±0.01）
2. `test_tower_ramp_first_frame()`：塔坡道 10 级行走登顶——总时间 ≤ 无 B2 时基线的 70%（量化首帧延迟消除），且每级间无 >2 帧停顿（探针输出级间帧数）
3. `test_pavilion_step_clearance()`（布局侧，test_map_layout_v3.gd）：4 组摊阁台阶与相邻门柱净距 ≥1.2（数据断言——钉住 A 的修复）
4. 既有 20 个登台用例全绿（0.9 箱拒绝/低顶板拒绝/跨隙拦截/坡道放弃等守卫不得被 B1/B2 破坏——尤其 B1 循环不得越过 0.9 箱：0.6+0.6=1.2>0.62 上限天然拦截，测试确认）
5. 全套件 + scan_gaps（必须 0 窄缝，门柱缩短后重扫）+ probe_v3_walk（79 点连通门禁）+ 场景 headless

## D. 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_controller.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd
python3 tools/scan_gaps_v3.py
godot --headless --path . -s res://tools/probe_v3_walk.gd
godot --headless --path . Levels/M2_TDM/L_M2.tscn   # 10 秒无错误（重置日志应为新哈希）
```
提交：`fix(m2v3): 台阶手感微调——门柱缩短留 1.2m 通道/同帧连锁登台/首帧登台（F5 用户反馈）`

## 禁止
- **除门柱 size.z 外零地图改动**（用户红线）；不改跳跃参数/空中控制/布局其他任何实体

## 报告格式
状态 + A/B 落地 + RED/GREEN 证据 + 五条验证输出 + 提交哈希 + 偏差。

---

# ═══════════ F6 brief（原文；收尾：MOVEMENT_REV bump + 注释对齐 + 文档同步） ═══════════

# F6 brief —— 收尾：MOVEMENT_REV bump + 注释对齐 + 文档同步

## 背景
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。F5（dd1ca1b）审查 PASS，3 条 Minor 观察 + 铁律合规项收尾。**纯收尾：一行常量 + 两处注释 + 文档，不改行为逻辑。**

## A. MOVEMENT_REV bump（铁律）
MovementController.gd：`const MOVEMENT_REV := "move-r2:step0.62,air-rest3.0/run0.76"` → **"move-r3:step0.62+chain+firstframe,air-rest3.0/run0.76"**（F5 改了登台语义：同帧连锁登台 + 首帧登台——铁律要求移动语义变更必须 bump；本次布局哈希（门柱）也已变，双键双保险）。
注释同步说明 r3 变更内容。

## B. 审查 Minor 修正（2 处注释/公式，无行为变更）
1. `_has_foot_wall_probe` 内部 advance 公式对齐：与 line 263 的 `max(_walk_speed, hvel.length()) * delta` 一致（差异 ~0.0008m 探针长度，纯一致性）
2. P5c 注释更新："未撞墙跳过整套查询（平地行走零开销）" → 改为"脚部前向探针每帧一条短射线（成本可忽略）+ slide 碰撞门控补充；登台完整查询仅贴墙帧触发"（B2 引入后行为描述与事实一致）

## C. 文档同步
1. **docs/HANDOFF.md**：
   - 门禁基线：GUT 272→**275**；实体 193 不变（门柱尺寸变不增数）；漫游 79 点不变
   - §二布局行补：门柱尺寸 z 3→2.25（2026-08-12 用户反馈：摊阁台阶↔门柱 1.2m 通道）
   - 手感修复轮专块补 F5：同帧连锁登台（微台阶 2 帧登完无振荡）+ 首帧登台（塔坡 43 帧登顶）+ PACE 0.2 落点钳制
   - MOVEMENT_REV 现值更新为 move-r3
2. **docs/FEATURES.md**：step-up 条目补"同帧连锁/首帧登台"；门柱条目（若存在）更新
3. **docs/PROGRESS.md**：§7 手感修复轮补 F5 记录（dd1ca1b，用户实测反馈→根因 0.45m 夹缝/连锁振荡/首帧延迟→修复+量化测试）
4. **账本**：F5 行（impl a0e0981d7340f3b0d、审查 ac86ab480d7d8b9ee PASS、提交 dd1ca1b、偏差 4 项）+ F6 行（本任务）
5. **计划归档**：docs/superpowers/plans/2026-08-12-m2-feel-fixes.md 追加 F5/F6 brief 汇编
6. **记忆**：m2 进度文件补 F5 记录 + MOVEMENT_REV r3；跳跃记录规则文件 MOVEMENT_REV 现值更新

## D. 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd        # 275/275
grep -n "move-r3\|275\|1.2m 通道\|43 帧" docs/HANDOFF.md | head
godot --headless --path . Levels/M2_TDM/L_M2.tscn            # 10 秒无错误，重置日志含新哈希（r3 双键）
```
提交：`chore(m2v3): F6 收尾——MOVEMENT_REV r3 bump/探针公式对齐/文档基线同步`

## 禁止
- 不改行为逻辑（A/B 为常量与注释）；不做清单外改动

## 报告格式
状态 + A/B/C 落地 + 验证输出 + 提交哈希。

---

# ═══════════ F7 brief（原文；2026-08-12 用户二次反馈） ═══════════

# 修复 F7 brief —— 门柱再缩短：摊阁台阶↔门柱通道 1.2m → 1.95m（用户二次反馈）

## 背景（用户反馈 + 控制器实测）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。用户复测反馈：**对称的两处摊阁台阶（市集带南北）旁的墙体与台阶距离仍过近，玩家通过会卡住，需要缩短墙体**。其余组件不动。
控制器实测（dump 全量数据）：4 组市集带摊阁台阶（BeltN_PavStepE/W、BeltS_PavStepE/W）与钟门柱净距 = **1.2m**（F5 已从 0.45 修到 1.2）——对 1.0m 宽玩家仍仅两侧各 0.1m 余量，斜向登台即擦柱卡顿。
**用户红线：地图只动这两处墙体，其他组件零改动。** 180° 旋转对称是项目硬约束（test_streets_rotation_pairs 强制）——南北门柱互为旋转镜像，须 4 根同步缩短（东/西 × 北/南），这正是"对称的两处"的完整解。

## A. 布局改动（唯一：门柱 size.z 再缩短，4 根同步）
`Levels/M2_TDM/map_layout_v3.gd` `_bell_gate(side)`：
- GateN/S 四根门柱 size.z：**2.25 → 1.5**，center.z 同步：北柱 z∈[13.75,16] → **[14.5,16]**（center 14.875→15.25）；南镜像 z∈[-16,-14.5]
- 结果：摊阁台阶 z_max 12.55 ↔ 门柱 z_min 14.5 → 净距 **1.95m**（玩家 1.0m + 两侧 0.475m 余量）
- 校验（逐项）：
  - 摊阁（z∈[10,11.8]）↔ 门柱 14.5：2.7m ✓
  - 双箱（z∈[12,13]）↔ 门柱 14.5：1.5m ✓
  - 门廊净空：两柱间 x 缝不变（size.x 3.75 未动）→ 门廊 2.5m ✓
  - 过梁（z∈[12.75,16.25]）仍覆盖柱顶 ✓（柱 z_max 16 未变）
  - 台阶（BeltN_PavStep z∈[11.8,12.55]）↔ 门柱 14.5：1.95 ✓
  - 旋转对称：4 根同改，center 互为 ±side ✓
- 注释：2026-08-12 用户二次反馈——1.2m 通道仍卡，柱深 2.25→1.5 留 1.95m

## B. 测试
1. `test_pavilion_step_clearance`（test_map_layout_v3.gd 既有，F5 新增）：gap 断言 1.2−0.001 → **1.95−0.001**；size.z 断言 2.25 → **1.5**
2. 全套件全绿（旋转对/无重叠/预算 193 不变/breach 不受影响）
3. scan_gaps_v3 必须 0 窄缝（新门柱与台阶 1.95、与双箱 1.5、与摊阁 2.7 全合规）

## C. 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_map_layout_v3.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd
python3 tools/scan_gaps_v3.py
godot --headless --path . -s res://tools/probe_v3_walk.gd
godot --headless --path . Levels/M2_TDM/L_M2.tscn   # 10 秒无错误；重置日志新哈希
```
提交：`fix(m2v3): 门柱再缩短——摊阁台阶↔门柱通道 1.95m（F7 用户二次反馈，仅门柱 4 根）`

## 禁止
- **除门柱 size.z 外零布局改动**（用户红线：其他组件不做任何改动）；不改移动代码；不做清单外改动

## 报告格式
状态 + A 落地 + RED/GREEN 证据 + 五条验证输出 + 提交哈希 + 偏差。

---

# ═══════════ F8 brief（原文；2026-08-12 用户实测定位） ═══════════

# 修复 F8 brief —— 横脊墙缩短：绕墙通道 1.0m → 2.0m（用户实测定位）

## 背景（用户确认）
Trigger Echo。目录 /Users/elanyi/Projects/Trigger-Echo。用户实测定位卡点：**东市街南段横脊墙（EastSpurS）与东塔坡道**、**西市街北段横脊墙（WestSpurN）与西塔坡道**之间绕墙通道仅 **1.0m**（玩家宽 1.0m，零余量，斜向通过即卡）。用户确认："就是这个地方，把墙体修改一下即可，其他一切地方和组件不要动。"

## A. 布局改动（唯一：2 面横脊墙缩短 1m，旋转对称对）
`Levels/M2_TDM/map_layout_v3.gd` STREETS：
- **EastSpurS**：size.x **3.0 → 2.0**（center.x 16.0 不变）→ x∈[14.5,16.5]（墙头 17.5 → **16.5**）
- **WestSpurN**（EastSpurS 的 180° 旋转镜像）：size.x **3.0 → 2.0** → x∈[-16.5,-14.5]（墙头 -17.5 → **-16.5**）
- **EastSpurN / WestSpurS 不动**（其余两面绕行路径净距充足，用户确认不卡）
- 结果：墙头↔塔坡道（x=±18.5）净距 **1.0 → 2.0m**（玩家两侧 0.5m 余量）
- 校验：墙贴 rim 面（x=14.5 面接触）不变；墙长 2m 仍提供拐角博弈位；其余组件/移动代码零改动
- 注释：2026-08-12 用户实测定位——绕墙通道 1.0m 卡顿，横脊墙 3→2m 留 2.0m

## B. 测试
1. `test_streets_f3_highwalls`：EastSpurS/WestSpurN 的 size.x 断言 3.0 → **2.0**（±0.01）；EastSpurN/WestSpurS 保持 3.0（可加断言钉住"只改两处"）
2. **新增绕墙通道断言**（test_map_layout_v3.gd）：EastSpurS 墙头（x=16.5）与 EastTowerRamp 足迹（x_min 18.5）净距 **2.0−0.001**；WestSpurN 镜像同——数据级钉住用户场景
3. 全套件全绿（旋转对自动适配：size 同改仍对称；无重叠/boost/预算 193 不变）
4. scan_gaps_v3 必须 0 窄缝（1.0→2.0 通道不再构成任何窄缝）

## C. 验证（实际运行贴输出）
```bash
cd /Users/elanyi/Projects/Trigger-Echo
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_map_layout_v3.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd
python3 tools/scan_gaps_v3.py
godot --headless --path . -s res://tools/probe_v3_walk.gd
godot --headless --path . Levels/M2_TDM/L_M2.tscn   # 10 秒无错误；重置日志新哈希
```
提交：`fix(m2v3): 横脊墙缩短——绕墙通道 2.0m（F8 用户定位，仅 EastSpurS/WestSpurN 两处）`

## 禁止
- **除上述 2 面横脊墙 size.x 外零改动**（用户红线：其他一切地方和组件不要动）；不改移动代码；不做清单外改动

## 报告格式
状态 + A 落地 + RED/GREEN 证据 + 五条验证输出 + 提交哈希 + 偏差。
