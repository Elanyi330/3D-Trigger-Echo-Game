# M1 实施计划 — 武器系统（四槽位各一款 + CS2 数值对齐）

> 日期: 2026-08-06
> 上游: 设计文档 `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md`（用户已确认）
> 参考源码副本: `docs/superpowers/reference/m1-src/`（Godot4-FPS-Template 武器状态机 + godot4-fps-prototype 后坐力/射击）
> 分支: `feat/m1-weapon-system`（工作树 ../Trigger-Echo-m1）
> 前置: M0 完成（移动/下蹲/掩体 14/14 全绿，合并回 main）

---

## 1. 目标

实现资源驱动武器系统：**四槽位**（主 AK-47 + 副 Glock-18 + 近战匕首 + 投掷 M67），支持切枪/开火/换弹/机瞄/后坐力/移速联动，**全部数值对齐 CS2**（2026-03-18 补丁），拼装视模型。TDD 全程，M0 测试不回归。

## 2. 架构

```
Trigger Echo（Godot 4.7.1 项目）
├── project.godot                 ← 新增 8 输入动作（fire/reload/aim/weapon_1-4/next_weapon）
├── Assets/
│   ├── Models/Weapons/           ← AK47_view.tscn / Glock18_view.tscn / Knife_view.tscn / Grenade_view.tscn（Box 拼装）
│   ├── Models/Hands/FpHands.tscn ← 手部拼装
│   ├── Models/Characters/.gitkeep（M3 启用）
│   └── Materials/                ← 共享材质（枪身金属/手部肤色）
├── Weapons/
│   ├── Weapon_Resource.gd        ← class_name WeaponResource（纯数据，FPS-Template 风格）
│   ├── WeaponManager.gd          ← 四槽位切换状态机（Node3D）
│   ├── WeaponCore.gd             ← 射击核心：hitscan + 后坐力 + 换弹（Node3D）
│   ├── Grenade.gd                ← 投掷物物理体（抛物线 + 爆炸）
│   ├── weapon_ak47.tres          ← CS2 对齐：36/×4.0/600RPM/30+120/2.4s/215u
│   ├── weapon_glock18.tres       ← 30/×4.0/400RPM/20+80/2.3s/240u
│   ├── weapon_knife.tres         ← 40/25/65/背刺180/0.4s+1.0s/250u
│   └── weapon_m67.tres           ← 98/57/引信1.5s/半径6m/245u
├── Player/
│   ├── MovementController.gd     ← 新增 speed_modifier（=1.0 默认）
│   ├── Head.gd                   ← 新增 add_recoil()/set_ads()/灵敏度缩放
│   └── WeaponAnchor.tscn         ← 第一人称武器挂点（Head 下）
└── test/unit/                    ← 新增 test_weapon_core / test_weapon_manager / test_ads / test_grenade
```

**参考要点**（任务 brief 必须引用，禁止在线拉取）：
- 资源驱动：FPS-Template `weapon_resource.gd`（纯数据）→ 本项目 `Weapon_Resource.gd`（字段按 spec §2.2 + CS2 对齐值）
- 切换状态机：FPS-Template `Weapon_State_Machine.gd`（WeaponSlot 槽位 + 切换 + 弹药）→ 本项目 `WeaponManager.gd`
- 后坐力：Prototype `weapon.gd` `has_shot(recoil_offset)` 信号 + spray 曲线 → 本项目 `WeaponCore.recoil_offset()` + `Head.add_recoil()`
- hitscan：Prototype `check_hitscan_collision()`（相机射线 + `PhysicsRayQueryParameters3D`）→ 本项目同思路

## 3. 技术栈

Godot 4.7.1 / GUT 9.7.1 / GDScript 4.x（同 M0，无新依赖）。

## 4. 全局约束（逐字复制，不得偏离）

- 项目名称 `Trigger Echo`；主场景 `res://Levels/Main/L_Main.tscn`
- 纯离线：工程内不得出现任何网络调用
- 物理层：`1=Objects`（命中目标）/ `2=Player`（玩家本体）；**hitscan 射线只对 Objects 层**（`collision_mask=1`）
- 输入动作：保留 M0 全部 11 个原名；新增 `fire`（左键）/`reload`（R）/`aim`（右键）/`weapon_1`（1）/`weapon_2`（2）/`weapon_3`（3）/`weapon_4`（4）/`next_weapon`（滚轮上）
- **武器数值唯一来源 `weapon_*.tres`（WeaponResource 类），禁止硬编码数值**（企划书 §4.2.5 硬性约束）；测试与调参作用于资源
- CS2 数值基准（对齐 2026-03-18 补丁，参考 cs2-weapon-data.md）：
  - AK-47：伤害 36 / 爆头倍率 ×4.0 / 600 RPM / 弹匣 30 / 备弹 120 / 换弹 2.4s / mobility 215u / 首发精度极高 / 衰减 0-40m=1.0、50m=0.98、60m=0.96 / 移速 0.86 / 固定弹道
  - Glock-18：伤害 30 / ×4.0 / 400 RPM / 20 / 80 / 2.3s / 240u / 半自动 / 随机后坐力 / 移速 0.96 / 无开镜
  - 匕首：首击 40 / 连击 25 / 重刺 65 / 背刺 180 / 0.4s 轻 1.0s 重 / 250u（=1.0 基准）
  - M67：中心 98（2m 内）/ 57（有甲，v1.0 无护甲不启用）/ 引信 1.5s / 爆炸半径 6m（98→60→30 距离衰减）/ 245u / 移速 0.98
- 部位倍率：头 ×4.0 / 躯干 ×1 / 四肢 ×0.8；穿甲恒全额（v1.0 无护甲）
- 伤害结算：`最终伤害 = 基础伤害 × 部位倍率 × 距离衰减`（分段阶梯曲线，衰减下限不为 0）
- 换弹（CS2 2026-03 规则）：单值时间；**换弹丢弃弹匣剩余**；换弹可被打断（切枪/开火，弹药不返还）
- 后坐力（CS2 Recoil Pattern）：Set Pattern（AK 固定弹道逐发数组）/ Random（Glock 随机偏移）/ Recovery（恢复速度）；首发精度独立
- 开镜：AK 机瞄 ×1.5（按住右键 FOV 缩放 + 散布收窄 + 灵敏度 ÷1.5）；Glock 无开镜；M67 右键 = 取消投掷
- 移速联动：`speed_modifier = mobility / 250`；MovementController 新增 `speed_modifier`（默认 1.0）；下蹲速度固定 2.59 不受影响；空中无加速（已实现）
- GUT 浮点断言用容差（`assert_almost_eq`）；测试命令 `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0 = 全绿
- 许可证：参考 m1-src 为 MIT（内嵌需保留 NOTICE/README 登记）；拼装模型全自产（BoxMesh/CylinderMesh）零外部资产

---

## 5. 任务分解（每任务 2-5 分钟粒度，TDD：RED→GREEN→REFACTOR）

### 任务 0：输入动作 + Weapon_Resource 资源骨架（TDD）

**输出接口**：
- `project.godot` 新增 8 输入动作（fire 左键 / reload R / aim 右键 / weapon_1-4 数字 1-4 / next_weapon 滚轮上）
- `Weapons/Weapon_Resource.gd`：`class_name WeaponResource extends Resource`，字段（按 spec §2.2 + CS2 字段）：
  ```gdscript
  @export var weapon_name: String
  @export var damage: float
  @export var headshot_multiplier: float = 4.0
  @export var limb_multiplier: float = 0.8
  @export var rpm: int
  @export var magazine: int
  @export var max_ammo: int
  @export var reload_time: float
  @export var effective_range: float
  @export var max_range: float
  @export var falloff_curve: PackedFloat32Array  # [满伤段=1.0, 中段, 末段]，按距离线性插值
  @export var mobility: float = 250.0
  @export var fire_mode: FireMode  # FULL_AUTO / SEMI_AUTO / MELEE / THROWABLE
  @export var recoil_pattern: RecoilPattern  # SET_PATTERN / RANDOM
  @export var pattern_offsets: PackedVector2Array  # Set Pattern 逐发偏移（度）
  @export var recoil_amount: float  # Random 基准偏移
  @export var recoil_variance: float
  @export var recovery_speed: float  # °/s
  @export var first_shot_spread: float  # 首发散布角（度）
  @export var ads_multiplier: float = 1.0  # 开镜倍率（1.0 = 无开镜）
  @export var attachments: Array = []  # 配件槽位（预留，M1 默认空）
  enum FireMode { FULL_AUTO, SEMI_AUTO, MELEE, THROWABLE }
  enum RecoilPattern { SET_PATTERN, RANDOM }
  ```
- 4 个 `weapon_*.tres` 数值文件（CS2 对齐值，见 §4 约束表；AK 的 `pattern_offsets` 初始为近似数组——前 5 发垂直 `[0.9, 1.8, 2.6, 3.2, 3.5]` 度，之后水平摆动 ±0.4 度，M1 近似可调；Glock `recoil_amount=0.5` 度 + `variance=0.3`）

**步骤**：
1. RED：写测试 `test/unit/test_weapon_resource.gd`——加载 4 个 .tres、断言 AK 伤害 36、Glock 弹匣 20、匕首 mobility 250、M67 引信字段、枚举/类型校验（加载失败报错）
2. GREEN：创建 `Weapon_Resource.gd` + 4 个 .tres（含 project.godot 输入动作）
3. REFACTOR：字段命名与 spec 一致；确认无硬编码数值（测试引用常量表而非散值）
4. 验证：`godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0

### 任务 1：WeaponCore 射击核心（TDD 核心）

**消费接口**：`Weapon_Resource`（任务 0）
**输出接口**：`Weapons/WeaponCore.gd`（`class_name WeaponCore extends Node3D`）
```gdscript
signal shot_fired(ammo_left: int)
signal reload_started
signal reload_finished
signal hit_landed(target: Node, damage: float, position: Vector3)
signal out_of_ammo
func setup(resource: WeaponResource, camera: Camera3D) -> void
func try_fire() -> void
func can_fire() -> bool
func start_reload() -> void
func is_reloading() -> bool
func get_ammo() -> Vector2  # Vector2(mag, reserve)
func add_ammo(amount: int) -> void
func get_recoil_offset() -> Vector2  # 本次射击后坐力偏移（度）
func set_ads(active: bool) -> void
```

**步骤**（TDD，每个行为先失败测试）：
1. RED：`test/unit/test_weapon_core.gd`——
   - 开火：子弹减少 1、`shot_fired` 信号、射速节流（600RPM → 0.1s 间隔内连按只响一次）
   - 命中：物理场景放目标（Box, Objects 层）→ hitscan 命中 → `hit_landed` 携带伤害
   - 伤害结算：AK 命中躯干 36 / 头 ×4.0 = 144 / 四肢 ×0.8 = 28.8；距离衰减（50m 处 0.98×36=35.28）
   - 弹匣空 → `out_of_ammo`；换弹 → 计时完成 → 弹匣满（丢弃剩余规则）
   - 换弹中 `try_fire()` 无效；切枪/开火打断换弹
   - 后坐力：SET_PATTERN 返回 `pattern_offsets[i]`、RANDOM 返回 `recoil_amount ± variance`、恢复衰减
   - 移速联动值：`speed_modifier` 由 mobility 换算（0.86/0.96/1.0/0.98）
2. GREEN：实现 `WeaponCore.gd`（hitscan 参考 m1-src weapon_proto.gd 的 `check_hitscan_collision`；射线只对 Objects 层 mask=1；部位判定用碰撞体 Group `"head"/"torso"/"limb"`，无 Group 默认躯干）
3. REFACTOR：部位判定/衰减/后坐力各抽方法
4. 验证：退出码 0；**M0 测试不回归**（运行全量）

### 任务 2：WeaponManager 切换状态机（TDD）

**消费接口**：`Weapon_Resource` + `WeaponCore`（任务 1）+ MovementController（speed_modifier）
**输出接口**：`Weapons/WeaponManager.gd`（`class_name WeaponManager extends Node3D`）
```gdscript
signal weapon_switched(slot: int)  # 0=primary 1=secondary 2=melee 3=throwable
signal weapon_ammo_updated(slot: int, mag: int, reserve: int)
func setup(slots: Array[WeaponResource], movement: MovementController) -> void
func switch_to(slot: int) -> void
func next_weapon() -> void  # 滚轮循环
func get_current_slot() -> int
func try_fire() -> void
func start_reload() -> void
func set_aim(active: bool) -> void
func get_speed_modifier() -> float
```

**步骤**（TDD）：
1. RED：`test/unit/test_weapon_manager.gd`——
   - 初始槽位 0（primary）；切枪 → 槽位更新 + `weapon_switched`
   - deploy 延迟（AK 0.3s 内 `try_fire` 无效，之后生效）
   - 滚轮循环 0→1→2→3→0
   - 换弹中切枪 → 换弹中断、弹药不返还
   - 开火中切枪 → 开火中断
   - `speed_modifier` 随切枪更新（AK 0.86 → 刀 1.0 → M67 0.98 → Glock 0.96）
   - 槽位切换后 `WeaponCore` 重建（新资源）
2. GREEN：实现 `WeaponManager.gd`（参考 m1-src Weapon_State_Machine.gd 的槽位/切换模式；deploy 时间用 `get_tree().create_timer` 或 `_physics_process` 计时；`MovementController.speed_modifier` 由任务 2 扩展）
3. REFACTOR：槽位字典化、切换流程统一
4. 验证：退出码 0；M0 不回归

### 任务 3：MovementController + Head 扩展（TDD）

**消费接口**：任务 2 的 WeaponManager
**输出接口**：
- `Player/MovementController.gd` 新增：
  ```gdscript
  @export var speed_modifier: float = 1.0
  # 在 accelerate() 中用 speed_effective = speed * speed_modifier 替换 speed
  ```
- `Player/Head.gd` 新增：
  ```gdscript
  var recoil_offset: float = 0.0  # 累计后坐力（度，向上为正）
  var ads_active: bool = false
  var ads_multiplier: float = 1.0
  func add_recoil(offset: float) -> void  # rotation.x 叠加后坐力
  func set_ads(active: bool, multiplier: float) -> void  # FOV 缩放 + 灵敏度 ÷multiplier
  ```

**步骤**（TDD）：
1. RED：`test/unit/test_controller_weapon.gd`——
   - `speed_modifier=0.86` 时水平加速度目标 = 6.35×0.86（模拟 `accelerate()` 纯逻辑）
   - 下蹲时 `speed_modifier` 不影响蹲速（2.59 固定）
   - `add_recoil(3.0)` → rotation.x 增加；`recovery` 衰减回零
   - `set_ads(true, 1.5)` → FOV 缩小 1.5 倍 + 灵敏度 ÷1.5
2. GREEN：改 `MovementController.gd` / `Head.gd`（`speed_effective = speed * speed_modifier`；`add_recoil` 与 `set_ads` 按 spec §2.7/2.8；注意保持 M0 现有 14 测试全绿——**speed_modifier 默认 1.0 时行为不变**）
3. REFACTOR：恢复逻辑放 `_physics_process`，开镜状态复位检查
4. 验证：退出码 0；**M0 14/14 全绿**

### 任务 4：Grenade 投掷物（TDD）

**消费接口**：`weapon_m67.tres`（任务 0）
**输出接口**：
- `Weapons/Grenade.gd`（`class_name Grenade extends RigidBody3D`）：
  ```gdscript
  signal exploded(center: Vector3)
  func init(origin: Vector3, direction: Vector3, strength: float) -> void
  func explode() -> void
  ```
- 爆炸逻辑：半径 6m 内 `Area3D` 检测，距离衰减伤害（2m 内 98 / 4m 内 60 / 6m 内 30）；爆炸时释放（queue_free）

**步骤**（TDD）：
1. RED：`test/unit/test_grenade.gd`——
   - 投掷后引信 1.5s 计时 → 爆炸 → `exploded` 信号
   - 爆炸伤害衰减：距离 1m → 98 / 3m → 60 / 5m → 30（目标单位 100HP 场景）
   - 右键取消投掷（WeaponManager 层面）→ 弹药不消耗
   - 弹道：抛物线简化（重力抛体，初始速度向前）
2. GREEN：实现 `Grenade.gd`（RigidBody3D + 引信计时 + `Area3D` 爆炸检测；弹道用 `linear_velocity` 初始冲量 + 重力）
3. REFACTOR：爆炸衰减表参数化（距离→伤害映射）
4. 验证：退出码 0

### 任务 5：拼装视模型 + WeaponAnchor（TDD）

**消费接口**：任务 2 的 WeaponManager（`weapon_switched` 信号）
**输出接口**：
- `Assets/Models/Weapons/AK47_view.tscn`（Box 拼装：枪管 BoxMesh + 枪身 + 握把 + 准星）
- `Assets/Models/Weapons/Glock18_view.tscn` / `Knife_view.tscn`（刀刃薄 Box）/ `Grenade_view.tscn`（圆球 SphereMesh 占位）
- `Assets/Models/Hands/FpHands.tscn`（左右手 Box 拼装，持枪位）
- `Assets/Materials/`：`gun_metal.tres`（金属灰）/ `hand_skin.tres`（肤色）
- `Player/WeaponAnchor.tscn`（Node3D，Head 下，`position=(0.25, -0.25, -0.5)` 右下角）
- `WeaponManager` 集成：切枪时挂载对应视模型 + 手部显示/隐藏

**步骤**（TDD）：
1. RED：`test/unit/test_view_model.gd`——WeaponAnchor 加载 4 视模型场景成功、切枪时视模型节点切换、手部节点显示/隐藏
2. GREEN：创建拼装场景（BoxMesh 组合）+ WeaponAnchor + WeaponManager 集成
3. REFACTOR：视模型挂载抽方法（`mount_view(slot)`）
4. 验证：退出码 0；有头模式手动冒烟（用户）：切枪看模型切换

### 任务 6：场景集成 + 手动冒烟（TDD）

**消费接口**：任务 0-5 全部
**输出接口**：
- `Levels/Main/L_Main.tscn`：实例化 Player + WeaponManager（预装载 4 资源）+ 测试靶子（Box 目标, Objects 层, Group `"torso"`）+ 弹药/命中 HUD 占位（Label）
- `L_Main.gd`：绑定输入（fire/reload/aim/weapon_1-4/next_weapon）到 WeaponManager

**步骤**（TDD）：
1. RED：`test/unit/test_integration.gd`——加载 L_Main.tscn → 玩家节点存在、WeaponManager 挂载 4 资源、`try_fire()` 对靶子触发 `hit_landed`、切枪更新速度
2. GREEN：创建 L_Main 集成（在 M0 场景基础上加武器层；**M0 的移动/下蹲/掩体功能保持原样**）
3. 手动冒烟（用户执行）：`godot --path .` WASD + 左键开火（AK 全自动） + R 换弹 + 右键机瞄（FOV 缩小） + 1-4 切枪 + 滚轮 + G 手雷投掷（注：`fire` 左键在 THROWABLE 槽位 = 投掷）
4. 验证：退出码 0；全量测试通过（含 M0 14 项）

### 任务 7：文档同步

**输出接口**：FEATURES.md / PROGRESS.md / README.md 更新
- FEATURES.md：M1 武器系统功能标记 🟢（资源驱动/四槽位/hitscan/后坐力/开镜/移速联动/拼装模型）+ 配件系统（瞄准镜/弹夹）标 🔴 待开发（后续环节）+ 数值对齐 CS2 标注
- PROGRESS.md：M1 记录（任务完成表 + 决策 9：配件系统列后续 / 拼装资产策略）+ 里程碑状态 M1 🟢
- README.md：武器系统段落更新（四款武器 + 操作键位表）
- 许可证登记：m1-src 参考（MIT，Godot4-FPS-Template + godot4-fps-prototype）加入合规章节

**验证**：三文档更新内容与实际实现一致（抽查关键数值）

---

## 6. 验证与测试（全流程）

- 每任务：RED → 运行确认失败 → GREEN → 运行确认通过 → REFACTOR 保持绿
- 全量命令：`godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0（M0 14 项 + M1 新增全绿）
- 手动冒烟（有头）：`godot --path .`——开火/换弹/切枪/机瞄/投掷手感 + 移速变化（持 AK 明显变慢）
- 数值抽查：AK 爆头 144、躯干 4 发击杀、M67 中心 98、移速 0.86

## 7. 风险与对策

| 风险 | 等级 | 对策 |
|------|------|------|
| 后坐力逐发数组无实据 | 中 | M1 近似拟合（前 5 发垂直升 + 水平摆动），`.tres` 可调 |
| deploy 时间无实据 | 低 | AK 0.3s（CS2 实测）+ 其余 0.5s，参数化 |
| 部位判定依赖 Group 约定 | 中 | 靶子 Group 明确（head/torso/limb），测试覆盖；AI 接入 M3 时统一 |
| 换弹丢弃规则测试易错 | 低 | 明确"弹匣剩余丢弃、备弹不变"断言 |
| M0 回归 | 中 | `speed_modifier` 默认 1.0 保持行为不变；Head 新增接口不改原逻辑；全量测试把关 |

## 8. 账本与分支

- 分支 `feat/m1-weapon-system`，工作树 `../Trigger-Echo-m1`
- 账本 `docs/superpowers/ledger/2026-08-06-m1-ledger.md`（控制器：主会话；实现者：haiku/sonnet 按任务复杂度）
- 每任务：实现 → 审查（规格合规 + 代码质量）→ 提交；关键/重要问题修复后继续
