# 🤖 新 AI 快速上手（HANDOFF）—— Trigger Echo

> **给下一段对话的 AI**：读这一页即可抓住项目重点与当前里程碑方向，再按需深入下列文档。
> 最近更新：2026-08-10（M1.75 完成收尾；待用户确认后进 M2）。

---

## 一、30 秒了解项目

- **纯离线 3D 第一人称 5v5 竞技射击**（玩家 + 4 AI 队友 vs 5 AI 敌人），Godot 4.7.1，macOS，方块/Minecraft 美术风，GUT 测试。
- **全面参考 CS 手感**：武器数值、人物身高/命中判定、移动速度、后坐力/散布、近战、开镜——全部对标 CS。
- **当前进度**：M0 + M1 + M1.5 + **M1.75 全部完成**（GUT 163/163 全绿）。M1.75 收尾后待用户确认进 M2。

## 二、M1.75 已完成（2026-08-10 收尾）

**核心原则（用户拍板，勿违反）**：**第一人称 ViewModel 是已验收的好基准，绝不重做**；"统一"= 让**第三人称向第一人称看齐**（GripRig 持握位姿从 `ViewModel.WEAPON_FRAME` 派生），使"眼睛挂相机即复现第一人称"。见记忆 `trigger-echo-fp-is-source-of-truth`。

本轮交付：
- **目录收敛**：三 worktree 合并回单目录 `Trigger-Echo`（feat/m1-assets）。
- **伤害 CS 对齐**：修复 Enemy 躯干+头双 collider 双重结算（近战/手雷跳过 `head` 组）→ 手雷脚下 98 不秒杀、近战 40/65；手雷线性衰减 `98×(1−d/8.89)`、半径 6→8.89m。
- **第三人称统一持握**：新建 `Character/GripRig.gd` 两骨 IK（腕到 `_GripRight/_GripLeft`）；Enemy 接入；修正角色骨骼左右手镜像（`_R`=解剖右）；**去掉可见手盒**（Hand 骨骼保留供 IK/挂枪，防吞没武器）。
- **资产**：Soldier_Echo 拆 Body/Head 两蒙皮网格（共享骨架）。

**遗留（M2 前待办）**：手雷墙体遮挡挡伤（LOS）；近战连击窗口严格化/stab 射程分级；`_in_cone` 垂直差上限。

## 三、工作目录 / 验证 / 运行

- **工作目录**（在此开发，单目录）：`/Users/elanyi/Projects/Trigger-Echo`，分支 `feat/m1-assets`。`main` 保留 M0 基线，M1.75 验收后再合并。（2026-08-10 已把 worktree 收敛回单目录；勿再新建 worktree。）
- **测试**：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（应 163/163 绿）。
- **运行游戏**：`godot --path . Levels/Main/L_Main.tscn`（靶场：WASD/空格跳/Shift蹲/左键开火/右键开镜/R换弹/1-4切枪）。

## 四、文档 / 资产地图（按需深入）

| 文档 | 内容 |
|------|------|
| `docs/PROGRESS-M1-ASSETS.md` | **M1/M1.5 详细进度** + M1.75 优化清单（最该先读） |
| `Assets/Models/COMPONENTS.md` | **武器/角色逐组件精确坐标/标记/骨骼/取景总表**（改模型必读） |
| `docs/superpowers/reference/cs2-weapon-data.md` | **CS 数据 + 比例权威表**（数值对齐唯一参照） |
| `docs/PROGRESS.md` / `FEATURES.md` | 总进度路线图 / 功能清单 |
| `docs/2026-08-06-trigger-echo-design.md` | 项目企划书（最终设计规格） |
| `Assets/Models/README.md` | 资产规范（目录/命名/许可/新增武器流程） |

## 五、核心约定（勿踩坑）

- **数值唯一来源 `.tres`**（对标 cs2-weapon-data.md），禁硬编码散值。
- **轴向**：Blender +Y → Godot −Z（前/枪口）、+Z→+Y（上）、+X→+X（右）。**组件标记内置 GLB**（`_Muzzle`/`_GripRight`/`_Magazine`/`_Bolt`/`_Sight`/`_PullRing`…），代码用 `ViewModel.find_marker(w,"_Muzzle")` 后缀匹配——无魔数。
- **弹孔用 quad 面片**（非 Decal——Forward Mobile 渲染器对每簇 decal 有上限会丢弃）。
- **近战命中/背刺判定用水平面(XZ)投影**——相机眼位(y1.63) vs 敌人脚部原点(y0) 的垂直差会稀释 3D 判定。
- **第一人称=基准**：ViewModel（程序化手臂+手、相机空间取景、部分武器×2 缩放）保持 M1.5，**不重做**。第三人称用 `GripRig` 从 `WEAPON_FRAME` 派生对齐。
- **手-武器协调 = 构造保证**：第一人称 ViewModel 手臂取自 Grip 标记每帧追踪；第三人称 GripRig 两骨 IK 腕到 Grip 标记。
- **角色**：Soldier_Echo（1.83m/18 骨/**Body+Head 两蒙皮网格**、**无可见手盒**——Hand 骨骼保留供 IK/挂枪），玩家绿/敌红换色；敌人经 `GripRig` 随机持枪（右手、步枪靠右）。
- **方法论**：遵循本机 `CLAUDE.md` 的 Superpowers 流程；**TDD 先写失败测试**；**验证（跑测试/渲染亲眼看）后才声明完成**。

## 六、可复用的验证工具（`tools/render/`）

- 管线：`process_weapon.py`（新武器加配置即可）/ `build_knife.py` / `build_character.py` / `make_echo_decal.py`（印花贴图）。
- 拍照核对：`Assets/Viewmodel/PhotoVM.tscn` / `PhotoAnim.tscn`（动作某相位）；`tools/render/view_weapon.tscn`（武器）/ `view_character.tscn`（角色持枪）/ **`view_grip.tscn`（GripRig 第三人称持枪，`--weapon= --yaw= --out=`）**；游戏内 `L_Main --photo=<path> [--burst=N --pz=Z --pitch=D --ads]`。

---

**给用户的开场提示词（复制即用）**：

> 读 `docs/HANDOFF.md` 和 `docs/PROGRESS-M1-ASSETS.md` 末尾的 M1.75 计划，了解 Trigger Echo 当前状态（M1.5 已验收完成）。我们在单目录 `/Users/elanyi/Projects/Trigger-Echo`（分支 feat/m1-assets）上做 **M1.75 优化打磨**。本轮我想优化的是：【在此填你的优化点】
