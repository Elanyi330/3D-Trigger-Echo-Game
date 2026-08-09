# 资产组件标注总表（Weapons + Character · Echo 系列）

> 用途：**让新对话的 AI 不看代码也能快速掌握整个模型仓库的每件资产、每个组件的确切位置与用途**。
> 配套总规范见 [README.md](README.md)（目录/命名/许可/新增流程）；本表是"组件级"精确坐标与接线图。
> 更新：2026-08-09（M1.5 CS 对齐轮）。

---

## 〇、坐标系（一切组件位置的参照系）

所有坐标均为 **canonical 武器坐标系（米）**，原点 = **GripRight（右手握把）**：

| canonical 轴 | → Godot | 含义 |
|---|---|---|
| **+Y** | **−Z** | 前方 / 枪口·刀尖方向（= 相机前向） |
| **+Z** | **+Y** | 上 |
| **+X** | **+X** | 右（武器右侧；印记在 −X 左侧面，玩家视角可见） |

> 实验钉死（`tools/render/cal_query.gd`），勿再猜。游戏资产为真实尺寸；视图模型缩放/取景在 Godot 侧（见 §三 WEAPON_FRAME）。

**组件标记如何在 Godot 被读取**：GLB 里烘入的命名 empty → Godot 的 `Node3D`，节点名 = `<型号>_Echo_<标记>`。
代码用**后缀匹配**（型号无关）：`ViewModel.find_marker(weapon_root, "_Muzzle")` → 返回该 Node3D。
消费方：`_Muzzle`→枪口火光/曳光起点；`_GripRight`/`_GripLeft`→ViewModel 手臂挂接；`_Magazine`/`_Bolt`→换弹动画；`_PullRing`/`_Spoon`→投掷拉环；`_Tip`→近战刺击点。

---

## 一、武器组件逐件标注

### 1. AK47_Echo（步枪 · 主武器）
- 文件：`Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb`；源 `tools/render/sources/AK47.glb`（poly.pizza Quaternius, CC0）
- 网格节点：`AK47_Echo_Body`；真实长 0.86m；`rot_z=-90`（源枪口 −X → +Y）
- ECHO 印记：左侧面（−X）`(-0.048, 0.05, 0.120)`，字高 0.038，橘色贴纸（压平 0.3mm，哑光）
- 数据：`Weapons/weapon_ak47.tres`（CS2：36/×4/600rpm/30+90/2.4s/215u）

| 标记节点 | canonical (x, y, z) m | 用途 |
|---|---|---|
| `AK47_Echo_Muzzle` | (0, 0.432, 0.176) | 枪口尖：曳光/火光起点 |
| `AK47_Echo_GripRight` | (0, 0, 0) | 右手握把（=原点） |
| `AK47_Echo_GripLeft` | (0, 0.140, 0.105) | 左手护木 |
| `AK47_Echo_Magazine` | (0, 0.030, -0.100) | 弹匣（换弹脱/装） |
| `AK47_Echo_Bolt` | (0.036, -0.020, 0.150) | 枪栓（上膛活动件） |
| `AK47_Echo_EjectPort` | (0.047, 0.020, 0.150) | 抛壳口 |
| `AK47_Echo_Sight` | (0, -0.050, 0.215) | 瞄具（ADS 对齐） |

### 2. Glock18_Echo（手枪 · 副武器）
- 文件：`Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb`；源 `tools/render/sources/Glock18.glb`（Quaternius, CC0）
- 网格节点：`Glock18_Echo_Body`；真实长 0.20m；`rot_z=+90`（源枪口 +X → +Y）
- ECHO 印记：左侧面（−X）`(-0.018, 0.05, 0.058)`，字高 0.020
- 数据：`Weapons/weapon_glock18.tres`（CS2：30/×4/400rpm/20+60/2.3s/240u，半自动）

| 标记节点 | canonical (x, y, z) m | 用途 |
|---|---|---|
| `Glock18_Echo_Muzzle` | (0, 0.171, 0.055) | 枪口尖 |
| `Glock18_Echo_GripRight` | (0, 0, 0) | 右手握把（=原点） |
| `Glock18_Echo_Magazine` | (0, -0.020, -0.036) | 弹匣（握把内） |
| `Glock18_Echo_Bolt` | (0, 0.020, 0.060) | 滑套（开火后座） |
| `Glock18_Echo_EjectPort` | (0.016, 0.030, 0.075) | 抛壳口 |
| `Glock18_Echo_Sight` | (0, -0.020, 0.090) | 瞄具 |

> Glock 无 `_GripLeft`（单手持）。视图模型 `scale=2.0`、`rot=-7°`（枪口下压指向准星）。

### 3. Knife_Echo（近战 · 自产）
- 文件：`Assets/Models/Weapons/Melee/Knife_Echo/Knife_Echo.glb`；**自产**（`tools/render/build_knife.py`，替代损坏下载件）
- 网格节点：`Knife_Echo_Body`（刃+护手+柄+首 4 件 overlap 合并为单一网格）；真实长 0.35m；刃尖 +Y
- ECHO 印记：刃左侧面（−X）`(-0.005, 0.10, 0.018)`，字高 0.020
- 数据：`Weapons/weapon_knife.tres`（CS2：斜挥40/连击25/前刺65/背刺180/轻0.4s重1.0s/距离2.0m/250u）

| 标记节点 | canonical (x, y, z) m | 用途 |
|---|---|---|
| `Knife_Echo_GripRight` | (0, -0.060, 0.012) | 右手握把（=原点） |
| `Knife_Echo_Tip` | (0, 0.215, 0.017) | 刀尖（刺击点） |
| `Knife_Echo_Guard` | (0, 0.005, 0.018) | 护手 |

> 竖持取景 `rot=(25,30,0)`（刃口朝上前方，CS 式持刀）；`scale=1.5`。

### 4. Grenade_M67_Echo（投掷 · 对标 CS 高爆雷）
- 文件：`Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb`；源 `tools/render/sources/Grenade_M67.glb`（poly.pizza Pichuliru, CC0）
- 网格节点：`Grenade_M67_Echo_Body`；真实最大尺寸 0.10m；`rot_z=0`（已竖直，引信 +Z 上）
- ECHO 印记：雷体左侧（−X）`(-0.036, 0, -0.02)`，字高 0.016
- 数据：`Weapons/weapon_m67.tres`（CS2 HE：中心98/引信1.5s/半径6m/245u）
- **投掷物视觉**：`Weapons/Grenade.gd._attach_visual()` 加载本 GLB 作为出手后的可见翻滚模型（剥离标记，只留本体网格）

| 标记节点 | canonical (x, y, z) m | 用途 |
|---|---|---|
| `Grenade_M67_Echo_GripRight` | (0, 0, 0) | 掌心握持（=原点） |
| `Grenade_M67_Echo_PullRing` | (0.035, 0, 0.050) | 拉环（投掷拉环动画，上侧） |
| `Grenade_M67_Echo_Spoon` | (0, 0, 0.045) | 握片/压柄（顶部支点） |

> 取景 `scale=2.2`、`rot=-18°`（放大上移入画，压柄+保险环可见）。

---

## 二、角色 Soldier_Echo（自产 · 玩家/队友/敌人共用，仅换色）

- 文件：`Assets/Models/Characters/Soldier_Echo/Soldier_Echo.glb`；**自产**（`tools/render/build_character.py`）
- 高 **1.83m（CS 站立 72u × 0.0254 = 1.8288m；2026-08 按 CS 身高统一缩放，因子 S≈1.0274）**，脚踩 z=0，面朝 **+Y（Blender）= −Z（Godot 前向）**；眼/脚尖朝前
- **单一蒙皮网格 `Soldier_Echo_Body`**（所有部件 join 成一件，避免节点/骨骼同名冲突），每部件单骨顶点组绑定（防拉伸）
- 换色：改网格材质 albedo（玩家绿 `(0.35,0.48,0.32)` / 敌人红 `(0.65,0.25,0.22)`；Enemy.gd 用 `material_override` 整体换色）
- 命中判定（Enemy.gd，CS 比例对齐）：躯干胶囊（半径0.31/高1.54，中心 y+0.92，group `torso`）+ 头部球（半径0.16，y+1.70，group `head`，爆头 ×4）
- **敌人持枪（M1.5）**：`Enemy.gd._equip_random_weapon()` 随机配一款武器——右臂前摆（`UpperArm_R` 局部 X -50°）+ 武器经 `BoneAttachment3D` 挂 `Hand_R`（GripRight=握把原点，真实尺寸，与角色比例统一）

> **坐标注意**：下文骨骼/部件坐标表为 `build_character.py` 的**原始定义值**；GLB 实际值 = 这些 × **S≈1.0274**（CS 身高缩放）。

### 骨骼（18 根；下表为 Blender canonical 坐标，z=高度 m，角色面朝 +Y）
| 骨骼 | head（起） | tail（止） | 父骨 |
|---|---|---|---|
| Root | (0,0,0.93) | (0,0,1.01) | — |
| Spine | (0,0,1.01) | (0,0,1.30) | Root |
| Neck | (0,0,1.46) | (0,0,1.56) | Spine |
| Head | (0,0,1.56) | (0,0,1.78) | Neck |
| Shoulder_L / R | (±0.21,0,1.42) | (±0.265,0,1.42) | Spine |
| UpperArm_L / R | (±0.265,0,1.42) | (±0.265,0,1.10) | Shoulder_L/R |
| Forearm_L / R | (±0.265,0,1.10) | (±0.265,0,0.80) | UpperArm_L/R |
| **Hand_L / R** | (±0.265,0,0.80) | (±0.265,0,0.70) | Forearm_L/R |
| UpperLeg_L / R | (±0.11,0,0.86) | (±0.11,0,0.48) | Root |
| LowerLeg_L / R | (±0.11,0,0.48) | (±0.11,0,0.08) | UpperLeg_L/R |
| Foot_L / R | (±0.11,0,0.08) | (±0.11,0.12,0.02) | LowerLeg_L/R |

> `Hand_L`/`Hand_R` 是 M3 AI 持武器/队友挂武器的挂点。左=+X、右=−X。

### 部件盒（已合并进 `Soldier_Echo_Body`；中心/尺寸 m，绑定骨）
| 部件 | 中心 (x,y,z) | 尺寸 (x,y,z) | 材质 | 骨 |
|---|---|---|---|---|
| Torso | (0,0,1.23) | (0.42,0.24,0.46) | UNIFORM | Spine |
| Pelvis | (0,0,0.93) | (0.40,0.24,0.14) | UNIFORM_DARK | Root |
| Head | (0,0.005,1.65) | (0.26,0.26,0.26) | SKIN | Head |
| Eye_L / R | (±0.06,0.135,1.68) | (0.045,0.02,0.06) | EYE | Head |
| UpperArm_L/R | (±0.265,0,1.26) | (0.11,0.13,0.34) | UNIFORM | UpperArm_L/R |
| Forearm_L/R | (±0.265,0,0.95) | (0.10,0.11,0.30) | UNIFORM_DARK | Forearm_L/R |
| Hand_L/R | (±0.265,0,0.735) | (0.10,0.11,0.13) | SKIN | Hand_L/R |
| UpperLeg_L/R | (±0.11,0,0.67) | (0.16,0.18,0.38) | UNIFORM_DARK | UpperLeg_L/R |
| LowerLeg_L/R | (±0.11,0,0.28) | (0.14,0.16,0.40) | UNIFORM | LowerLeg_L/R |
| Foot_L/R | (±0.11,0.05,0.04) | (0.14,0.26,0.08) | BOOT | Foot_L/R |

### 材质（tintable）
| 材质 | 颜色 | 用于 |
|---|---|---|
| UNIFORM | 可换色（默认玩家绿 0.35,0.48,0.32） | 躯干/上臂/小腿 |
| UNIFORM_DARK | 0.7×UNIFORM | 骨盆/前臂/大腿 |
| SKIN | (0.85,0.68,0.55) | 头/手 |
| BOOT | (0.15,0.13,0.12) | 脚 |
| ACCENT | (0.12,0.12,0.14) | 腰带/护具 |
| EYE | (0.10,0.10,0.12) | 眼 |

> **第一人称一致性**：视图模型手臂（`Assets/Viewmodel/ViewModel.gd`）与 Soldier_Echo **同尺寸同色系**（上臂0.11×0.13/前臂0.10×0.11/手0.10×0.11×0.13），低头可见下半身（`WeaponView._build_body`）——相机挂在角色眼睛上，不割裂。

---

## 三、视图模型取景表（ViewModel.WEAPON_FRAME · Godot 相机空间）

每件武器的持握取景（`offset`=相机空间握把位 / `scale`=视图缩放 / `rot`=持握欧拉角°）。CS 对比校准。

| 武器 | offset (右,下,前) | scale | rot (°) |
|---|---|---|---|
| AK47_Echo | (0.28, -0.33, -0.55) | 1.0 | (0, 0, 0) |
| Glock18_Echo | (0.20, -0.24, -0.46) | 2.0 | (-7, 0, 0) |
| Knife_Echo | (0.20, -0.20, -0.40) | 1.5 | (25, 30, 0) 竖持 |
| Grenade_M67_Echo | (0.10, -0.18, -0.38) | 2.2 | (-18, 0, 0) |

> **手-武器协调 = 构造保证**：ViewModel 手部网格直接放在 `_GripRight`/`_GripLeft` 标记上，且**每帧动态追踪**握把（`_update_arms`）——换弹/挥砍/后坐力动武器时手不脱把、肩部（屏外）不入镜。

---

## 四、新增资产速查（详见 README §五）

- **新武器**：源 glb → `tools/render/sources/`；`process_weapon.py` 的 `WEAPONS` 加配置（rot_z/real_len/grip_raw/markers/mark）；`--debug-spheres` 校对 → 导出；建 `weapon_<型号>.tres`（数值对标 [cs2-weapon-data.md](../../docs/superpowers/reference/cs2-weapon-data.md)）。
- **新角色/换色**：`build_character.py --tint R,G,B`。
- **命名铁律**：节点一律 `<型号>_Echo_<部件>`，新型号/新系列不冲突。
