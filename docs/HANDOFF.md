# 🤖 新 AI 快速上手（HANDOFF）—— Trigger Echo

> **给下一段对话的 AI**：读这一页即可抓住项目重点与当前里程碑方向，再按需深入下列文档。
> 最近更新：2026-08-09（M1.5 验收通过，进入 M1.75）。

---

## 一、30 秒了解项目

- **纯离线 3D 第一人称 5v5 竞技射击**（玩家 + 4 AI 队友 vs 5 AI 敌人），Godot 4.7.1，macOS，方块/Minecraft 美术风，GUT 测试。
- **全面参考 CS 手感**：武器数值、人物身高/命中判定、移动速度、后坐力/散布、近战、开镜——全部对标 CS。
- **当前进度**：M0 引擎骨架 + M1 武器资产 + **M1.5 武器集成 全部完成并通过用户验收**（GUT 158/158 全绿，CS 对比 agent 终审 PASS）。

## 二、当前里程碑：M1.75 优化打磨

**M1.75 = M1.5 与 M2 之间专设的优化版本**——只对 M1.5 内容做更进一步打磨，**不进新功能**，用户验收驱动逐项改进。验收通过后才进 M2（地图与模式）。

- **优化候选清单**（优先级由用户验收反馈定）：见 `docs/PROGRESS-M1-ASSETS.md` 末尾「九、M1.75 优化打磨」。包括：手感/动画细节、近战 CS 严格项（连击窗口/stab 射程分级）、M67 爆炸半径、比例一致性复查、多层垂直判定预留等。
- **工作方式**：用户实机反馈 → 修复 → 派 CS 对比验收 agent → PASS 后开 Godot 供用户亲验。

## 三、工作目录 / 验证 / 运行

- **工作树**（在此开发）：`/Users/elanyi/Projects/Trigger-Echo-m1-assets`，分支 `feat/m1-assets`。**勿碰主仓** `Trigger-Echo`。
- **测试**：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（应 158/158 绿）。
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
- **手-武器协调 = 构造保证**：ViewModel 手臂取自 Grip 标记 + 每帧动态追踪。
- **角色**：Soldier_Echo（1.83m/18骨/单蒙皮网格），玩家绿/敌红换色；敌人经 `BoneAttachment3D` 挂 `Hand_R` 随机持枪。
- **方法论**：遵循本机 `CLAUDE.md` 的 Superpowers 流程；**TDD 先写失败测试**；**验证（跑测试/渲染亲眼看）后才声明完成**。

## 六、可复用的验证工具（`tools/render/`）

- 管线：`process_weapon.py`（新武器加配置即可）/ `build_knife.py` / `build_character.py` / `make_echo_decal.py`（印花贴图）。
- 拍照核对：`Assets/Viewmodel/PhotoVM.tscn` / `PhotoAnim.tscn`（动作某相位）；`tools/render/view_weapon.tscn`（武器）/ `view_character.tscn`（角色持枪）；游戏内 `L_Main --photo=<path> [--burst=N --pz=Z --pitch=D --ads]`。

---

**给用户的开场提示词（复制即用）**：

> 读 `docs/HANDOFF.md` 和 `docs/PROGRESS-M1-ASSETS.md` 末尾的 M1.75 计划，了解 Trigger Echo 当前状态（M1.5 已验收完成）。我们在工作树 `Trigger-Echo-m1-assets`（分支 feat/m1-assets）上做 **M1.75 优化打磨**。本轮我想优化的是：【在此填你的优化点】
