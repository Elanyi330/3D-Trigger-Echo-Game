# Task 0 Brief — 输入动作 + Weapon_Resource 资源骨架

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 0（先读）
> 方法: TDD 铁律——先写失败测试（RED），确认失败原因正确，再实现（GREEN），最后 REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`（在此目录内操作）
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 注意: GUT class_names 陷阱——新增 class_name 脚本后需先 `godot --headless --import` 再跑测试
- M0 基准: 14/14 全绿（你的改动不得破坏）

## 交付内容（严格按计划 §5 任务 0）

### 1. project.godot 新增 8 个输入动作（保留 M0 全部 11 个原名）
| 动作 | 键位 |
|------|------|
| `fire` | 鼠标左键（InputEventMouseButton, button_index=1） |
| `reload` | R（physical_keycode=82） |
| `aim` | 鼠标右键（button_index=2） |
| `weapon_1` | 数字 1（physical_keycode=49） |
| `weapon_2` | 数字 2（physical_keycode=50） |
| `weapon_3` | 数字 3（physical_keycode=51） |
| `weapon_4` | 数字 4（physical_keycode=52） |
| `next_weapon` | 滚轮上（InputEventMouseButton, button_index=4） |

### 2. `Weapons/Weapon_Resource.gd`（class_name WeaponResource extends Resource）
字段定义（严格按此签名，测试引用）：
```gdscript
enum FireMode { FULL_AUTO, SEMI_AUTO, MELEE, THROWABLE }
enum RecoilPattern { SET_PATTERN, RANDOM }

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
@export var falloff_curve: PackedFloat32Array  # [满伤段=1.0, 中段, 末段]
@export var mobility: float = 250.0
@export var fire_mode: FireMode = FireMode.FULL_AUTO
@export var recoil_pattern: RecoilPattern = RecoilPattern.SET_PATTERN
@export var pattern_offsets: PackedVector2Array  # Set Pattern 逐发偏移（度）
@export var recoil_amount: float
@export var recoil_variance: float
@export var recovery_speed: float
@export var first_shot_spread: float
@export var ads_multiplier: float = 1.0
@export var fuse_time: float = 0.0     # 投掷物引信（M67 用）
@export var blast_radius: float = 0.0  # 爆炸半径（M67 用）
@export var attachments: Array = []    # 配件槽位（预留，M1 默认空）
```

### 3. 四个 .tres 数值文件（CS2 对齐，唯一数值来源；禁止硬编码散值）
- `Weapons/weapon_ak47.tres`：weapon_name="AK-47「铁幕」" / damage=36 / headshot_multiplier=4.0 / limb_multiplier=0.8 / rpm=600 / magazine=30 / max_ammo=120 / reload_time=2.4 / effective_range=40 / max_range=60 / falloff_curve=[1.0, 0.98, 0.96] / mobility=215 / FULL_AUTO / SET_PATTERN / pattern_offsets=前 5 发垂直上升 `[(0.0,0),(0.9,0),(1.8,0),(2.6,0),(3.2,0)]` 之后水平摆动 ±0.4（M1 近似，可调）/ recovery_speed=8.0 / first_shot_spread=0.1 / ads_multiplier=1.5
- `Weapons/weapon_glock18.tres`：weapon_name="Glock-18「迅捷」" / damage=30 / rpm=400 / magazine=20 / max_ammo=80 / reload_time=2.3 / effective_range=15 / max_range=30 / falloff_curve=[1.0, 0.9, 0.85] / mobility=240 / SEMI_AUTO / RANDOM / recoil_amount=0.5 / recoil_variance=0.3 / recovery_speed=14.0 / first_shot_spread=0.15 / ads_multiplier=1.0（无开镜）
- `Weapons/weapon_knife.tres`：weapon_name="战术匕首「回声」" / damage=40 / rpm=0（近战无视） / magazine=0 / max_ammo=0 / reload_time=0 / mobility=250 / MELEE / melee 附加字段（见下）/ ads_multiplier=1.0
- `Weapons/weapon_m67.tres`：weapon_name="M67「轰鸣」" / damage=98 / rpm=0 / magazine=1 / max_ammo=1 / reload_time=0 / mobility=245 / THROWABLE / fuse_time=1.5 / blast_radius=6.0 / ads_multiplier=1.0

**注意**：匕首/手雷需要计划外的附加字段，按需在 Weapon_Resource 补加（如 `melee_primary_damage`/`melee_secondary_damage`/`melee_stab_damage`/`melee_range`/`melee_angle` 等），保持字段可 export 且测试覆盖。

### 4. 测试 `test/unit/test_weapon_resource.gd`（RED 先行）
- 加载 4 个 .tres 全部成功（`load()` 非 null）
- AK：damage==36、headshot_multiplier==4.0、rpm==600、magazine==30、max_ammo==120、reload_time==2.4、mobility==215、fire_mode==FULL_AUTO、pattern 长度>=5、ads_multiplier==1.5
- Glock：damage==30、magazine==20、fire_mode==SEMI_AUTO、recoil_pattern==RANDOM、ads_multiplier==1.0
- 匕首：fire_mode==MELEE、mobility==250
- M67：fire_mode==THROWABLE、fuse_time==1.5、blast_radius==6.0、magazine==1
- 数值断言用 `assert_eq`（整型/枚举）或 `assert_almost_eq`（浮点，容差）

## 验证步骤（必须真实运行）
1. `godot --headless --import`（注册新 class_name，GUT 陷阱）
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0 且新增测试全过
3. 全量测试通过（含 M0 14 项不回归）
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务0 输入动作 + Weapon_Resource 资源骨架（CS2 对齐数值）"`

## 完成报告
返回报告：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果（全量测试输出摘要）、遇到的问题
