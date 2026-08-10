# 🤖 新 AI 快速上手（HANDOFF）—— Trigger Echo

> **给下一段对话的 AI**：读这一页即可抓住项目重点与当前里程碑方向，再按需深入下列文档。
> 最近更新：2026-08-10（M2 布局 v2 重构完成，用户验收中；T5 视觉/T7 TDM 待做）。

---

## 一、30 秒了解项目

- **纯离线 3D 第一人称 5v5 竞技射击**（玩家 + 4 AI 队友 vs 5 AI 敌人），Godot 4.7.1，macOS，方块/Minecraft 美术风，GUT 测试。
- **全面参考 CS 手感**：武器数值、人物身高/命中判定、移动速度、后坐力/散布、近战、开镜——全部对标 CS。
- **当前进度**：M0 + M1 + M1.5 + M1.75 全部完成（GUT 163/163 绿）；**M2 小图布局 v2 重构完成**（170/170 绿），用户逐轮验收中。

## 二、M2 小图「回声集市」当前状态（2026-08-10）

**布局 v2 已落地**（`Levels/M2_TDM/map_layout.gd` 数据驱动）：
- 中央大厅 **20×16×4.5m**（12 柱贴墙 + 2 隔断墙 + 4 门 4m + 高屋顶——**底面 4.25m > 跳跃顶 3.22m 防卡顿**）
- **四角建筑×4**（14×15 开放院落 + 2 门朝中心 + 内部 2 隔断墙 + 箱堆）
- **出生封顶建筑×2**（12×10×3m，**左右 3m 出口**）
- 环形街道（西/东/北/南 5m）+ 交火组件（高台两级微台阶/隔断墙/箱堆）
- 南北带填充（矮墙/箱堆/树）+ 绿化（树 decor 无碰撞/花坛/长凳）
- 敌人随机撒点 + 完整武器系统 + 手雷抛物线（50 点 + 落点圆环标记）

**验证**：布局断言 7/7、窄缝扫描 0 处（<1.2m）、漫游探针 19/19、跳跃探针全点位 1.39m、完整 GUT **170/170 绿**。

**待做（T5/T6/T7）**：视觉升级（Kenney 平铺已回退，需按"单面原型→确认→铺全图"重做）、navmesh 烘焙（M3 用）、TDM 框架（计分/复活/胜负/HUD）。

## 三、工作目录 / 验证 / 运行

- **工作目录**（在此开发，单目录）：`/Users/elanyi/Projects/Trigger-Echo`，分支 `feat/m1-assets`。
- **测试**：`godot --headless --path . -s addons/gut/gut_cmdln.gd`（应 170/170 绿）。
- **运行游戏（M2 小图）**：`godot --path . Levels/M2_TDM/L_M2.tscn`（WASD 移动/空格跳/Shift 蹲/左键开火/1-4 切枪/4+长按左键看手雷抛物线）。
- **M1 靶场**：`godot --path . Levels/Main/L_Main.tscn`。

## 四、文档 / 资产地图（按需深入）

| 文档 | 内容 |
|------|------|
| `docs/PROGRESS-M1-ASSETS.md` | M1/M1.5/M1.75 详细进度 |
| `docs/superpowers/specs/2026-08-10-m2-tdm-map-design.md` | **M2 小图设计文档**（含 v2 布局 + 实测教训 §十四——防再犯） |
| `Assets/Models/COMPONENTS.md` | 武器/角色逐组件精确坐标/标记/骨骼/取景总表 |
| `docs/superpowers/reference/cs2-weapon-data.md` | CS 数据 + 比例权威表（数值对齐唯一参照） |
| `docs/PROGRESS.md` / `FEATURES.md` | 总进度路线图 / 功能清单 |
| `docs/2026-08-06-trigger-echo-design.md` | 项目企划书（最终设计规格） |
| `Assets/Models/README.md` | 资产规范（目录/命名/许可/新增武器流程） |

## 五、核心约定（勿踩坑）

- **数值唯一来源 `.tres`**（对标 cs2-weapon-data.md），禁硬编码散值。
- **轴向**：Blender +Y → Godot −Z（前/枪口）、+Z→+Y（上）、+X→+X（右）。**组件标记内置 GLB**（`_Muzzle`/`_GripRight`…），代码用 `find_marker` 后缀匹配——无魔数。
- **第一人称=基准**：ViewModel（程序化手臂+手、相机空间取景）保持 M1.5，**不重做**。第三人称用 `GripRig` 从 `WEAPON_FRAME` 派生对齐。
- **角色**：Soldier_Echo（1.83m/18 骨/Body+Head 两蒙皮网格、无可见手盒），玩家绿/敌红换色。
- **M2 布局教训**（见设计文档 §十四）：室内屋顶 ≥4.5m（底面 > 跳跃顶 3.22m）；室内隔断 1.4m 不可跳；可跳高台两级微台阶；柱贴墙；树 = decor 无碰撞；**无 <1.2m 窄缝**（scan_gaps.py 扫描）。
- **方法论**：Superpowers 流程；**TDD 先写失败测试**；**验证（跑测试/渲染亲眼看）后才声明完成**。

## 六、可复用的验证工具（`tools/render/` + `tools/`）

- 管线：`process_weapon.py` / `build_knife.py` / `build_character.py` / `make_echo_decal.py`
- 拍照核对：`Assets/Viewmodel/PhotoVM.tscn` / `PhotoAnim.tscn`；`tools/render/view_weapon.tscn` / `view_character.tscn` / `view_grip.tscn`；游戏内 `L_Main --photo=<path>`
- **M2 探针**：`tools/probe_walk.gd`（漫游可达）、`tools/probe_jump_smooth.gd`（跳跃流畅）、`tools/probe_global.gd`（全图扫描）、`tools/probe_step_climb.gd`（台阶走通）、`/tmp/scan_gaps.py`（窄缝扫描）
- **M2 场景**：`Levels/M2_TDM/L_M2.tscn`（玩家 + 武器 + 10 随机敌人 + 灰盒地图）
