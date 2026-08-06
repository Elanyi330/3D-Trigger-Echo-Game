# Task 5 Brief — 拼装视模型 + WeaponAnchor（Assets/Models 分类）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 计划: `docs/superpowers/plans/2026-08-06-m1-weapon-system.md` 任务 5（先读 §5 任务 5 + §4 全局约束）
> 前置: 任务 2 已完成（WeaponManager weapon_switched 信号）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。
> 资产决策: **全模型拼装化**（用户拍板）——BoxMesh/CylinderMesh 拼装，零外部资产；未来精细化打磨时原位替换

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 81/81 全绿（M0 14 + 任务 0 9 + 任务 1 25 + 任务 2 13 + 任务 3 9 + 任务 4 11）

## 交付内容（严格按计划 §5 任务 5）

### 1. 拼装视模型（BoxMesh/CylinderMesh 组合，零外部资产）
- `Assets/Models/Weapons/AK47_view.tscn`：枪管（细长 Box）+ 枪身（主 Box）+ 握把（小 Box）+ 准星（小 Box），比例像 AK 轮廓即可（M1 占位级）
- `Assets/Models/Weapons/Glock18_view.tscn`：枪身 + 枪管（紧凑小手枪轮廓）
- `Assets/Models/Weapons/Knife_view.tscn`：刀身（薄长 Box）+ 刀柄（小 Box）
- `Assets/Models/Weapons/Grenade_view.tscn`：SphereMesh 圆球（手雷占位）
- `Assets/Models/Hands/FpHands.tscn`：左右手各 2-3 个 Box（手掌 + 手指），持枪位
- `Assets/Materials/`：`gun_metal.tres`（金属灰，枪身用）+ `hand_skin.tres`（肤色，手部用）——StandardMaterial3D，颜色合理即可
- **目录规范**：每个模型一个目录（`AK47/` 内放 tscn），符合"模型资产单独分类"决策；`Assets/Models/Characters/` 建目录（M3 AI 用，可放 .gitkeep）

### 2. `Player/WeaponAnchor.tscn`（Node3D，Head 下持枪挂点）
- 位置：`position=(0.25, -0.25, -0.5)`（右下角 CS 式持枪位）
- 持有当前视模型（实例化 AK47_view 等）+ FpHands（显示/隐藏）
- 后坐力视觉反馈：开火时视模型沿 Z 轴小幅位移（0.02m）+ 回弹（代码控制，非动画系统——简单 tween 或 _process 插值）
- 切枪视觉切换：收到 WeaponManager `weapon_switched(slot)` → 换挂对应视模型

### 3. WeaponManager 集成（视模型挂载）
- WeaponManager 需要知道视模型路径：加 `@export var view_models: Array[PackedScene]`（4 槽位对应 4 个视模型场景）或按槽位路径映射（任选，需测试覆盖）
- 切枪时挂载对应视模型到 WeaponAnchor（或 WeaponAnchor 自行订阅 weapon_switched——**推荐 WeaponAnchor 订阅**，保持 Manager 纯逻辑）
- 手部显示/隐藏：切到 melee/throwable 也显示手（CS 式持刀/持雷都有手）；无武器槽位（HOLSTERED）隐藏

### 4. 测试 `test/unit/test_view_model.gd`（RED 先行）
- 4 个视模型场景加载成功（load() 非 null，含 MeshInstance3D 子节点）
- WeaponAnchor 挂载：收到 weapon_switched(0) → AK47_view 实例化挂上；weapon_switched(2) → Knife_view
- 手部节点显示/隐藏逻辑
- FpHands 加载成功
- 后坐力位移：开火信号（或直接调方法）→ 视模型 Z 位移 > 0 → 回弹回 0

**测试提示**：WeaponAnchor 单测可手动构建（Node3D 根 + 实例化 WeaponAnchor.tscn 或 set_script）；weapon_switched 信号可直接 emit 模拟（Manager 已测）；场景加载用 `load()` + `instantiate()` 断言节点存在。

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0，test_view_model 全过 + 全量 81 项不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务5 拼装视模型 + WeaponAnchor（Assets/Models 分类）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
