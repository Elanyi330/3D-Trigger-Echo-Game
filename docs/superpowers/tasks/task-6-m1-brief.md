# Task 6 Brief — 场景集成 + 手动冒烟（L_Main 武器层）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 6（先读 §5 任务 6 + §4 全局约束）
> 前置: 任务 0-5 全部完成（资源/核心/状态机/控制器扩展/Grenade/视模型）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。
> 参考: 用户指导——攻击逻辑融入企划书参考项目优质算法，保持本项目特色

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 96/96 全绿（任务 5 修复后可能 97+）
- **注意：任务 5 修复可能未提交完，先 `git log --oneline -3` 确认最新状态**

## 交付内容（严格按计划 §5 任务 6）

### 1. L_Main 场景集成（武器层 + 靶子 + 弹药 HUD）
- `Levels/Main/L_Main.tscn`：在 M0 场景（地面+四面墙+灯光+Player）基础上**加武器层**：
  - 实例化 WeaponManager（挂到 Player 下）+ WeaponAnchor（挂到 Head 下）+ 预装载 4 个 .tres + 4 个视模型 PackedScene
  - 测试靶子：Box 目标（Objects 层，Group `"torso"`），2-3 个不同距离（验证衰减）
  - 弹药/命中 HUD 占位：Label 显示当前槽位弹匣/备弹（CS 式 `30 / 90`）+ 命中伤害提示（可选）
- `L_Main.gd`：绑定输入——`fire`（左键按住）/ `reload`（R）/ `aim`（右键按住）/ `weapon_1-4`（数字键）/ `next_weapon`（滚轮）到 WeaponManager；绑定 `weapon_switched` → HUD 更新 + WeaponAnchor 自动（Anchor 已订阅）
- **M0 的移动/下蹲/掩体功能保持原样**（L_Main 是 M0 交付的测试场景，只加不改）

### 2. 收尾事项（任务 3/4 审查移交，顺手处理）
- **Head.set_ads multiplier 防护**：`maxf(multiplier, 1.0)` 夹取（任务 3 审查次要建议）——防错误数据源 inf/NaN
- **ads_multiplier 写入时机**：仅 active 时写入（任务 3 审查次要建议）
- **M67 右键取消投掷**（企划书 §4.2.3⑦ + 任务 2/4 brief 移交）：WeaponManager THROWING 状态 + `aim`（右键）→ 取消投掷、弹药不消耗、回 ACTIVE
- **WeaponManager 相机接线验证**（任务 2 审查观察）：集成测试断言 Manager 层 hitscan（hit_landed）——验证 setup 时 `get_viewport().get_camera_3d()` 在 L_Main 实际场景可用
- **Grenade 接入**（任务 2 THROWING 占位 → 真实）：M67 槽位 try_fire → 生成真实 Grenade（init 位置/方向/强度）→ 引信 → 爆炸（任务 4 已实现，此处接线）

### 3. 测试 `test/unit/test_integration.gd`（RED 先行）
- 加载 L_Main.tscn 成功 → 玩家节点存在、WeaponManager 挂载 4 资源
- `try_fire()` 对靶子触发 `hit_landed`（集成层验证 Manager 相机路径）
- 切枪更新速度（speed_modifier 生效）
- 弹药 HUD 更新（weapon_ammo_updated → Label 文本）
- M67 右键取消投掷 → 弹药不消耗
- Grenade 投掷 → 爆炸对靶子伤害（集成层验证接线）

**测试提示**：L_Main 加载测试用 `load()` + `instantiate()` + `add_child`；hitscan 需要相机 current（Head/Camera3D 场景中已置）；物理帧推进 await。

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_integration 全过 + 全量不回归
3. **手动冒烟（有头模式）**：`godot --path .`——WASD 移动 + 左键开火（AK 全自动） + R 换弹 + 右键机瞄（FOV 缩小） + 1-4 切枪（视模型切换 + 移速变化） + 滚轮循环 + M67 投掷/右键取消
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务6 场景集成 + 收尾事项（L_Main 武器层 + Grenade 接线 + 右键取消）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、手动冒烟结果（若可执行）、遇到的问题、与 brief 的偏差
