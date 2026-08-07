# Task 12 Brief — 敌人训练场（随机 3 敌人 + 血条 + 分散排布 + 全倒刷新）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> spec: `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md` §9.10（先读）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 160/160 全绿

## 必读文件（动手前先读）
1. spec §9.10（敌人模型 + 靶场训练场景）
2. `/Users/elanyi/Projects/Trigger-Echo-m1/Assets/Models/README.md`（建模规范——敌人模型必须符合）
3. `/Users/elanyi/Projects/Trigger-Echo-m1/Levels/Main/Target.gd`（100HP + take_damage——敌人复用或扩展）
4. `/Users/elanyi/Projects/Trigger-Echo-m1/Levels/Main/L_Main.gd`（参考集成方式；训练场独立场景）
5. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/`（4 个 .tres——敌人持随机武器）

## 交付内容

### 1. 敌人模型 `Assets/Models/Characters/Enemy/Enemy.tscn`（几何拼装，符合 README 规范）

- **结构**：躯干 + 头 + 四肢（Box/Capsule 组合，胶囊+躯干盒），多材质（服装色/肤色/装备色 2-3 材质）
- **身高/比例**：约 1.8m 人形（对标玩家胶囊 1.83m），头/躯干/四肢比例合理
- **手持武器表现**：敌人带武器挂点（`WeaponMount` Node3D，双手位置），可持 4 种武器（复用视模型或简化版——**复用 Assets/Models/Weapons 视模型 + 敌人持枪姿态**：双臂前伸持枪）
- **碰撞体积**：胶囊碰撞体（Objects 层 1 或 Player 层 2？——**敌人是受击目标，用 Objects 层 1** 以便 hitscan/近战命中）
- **血条**：头顶 UI（Sprite3D/WorldLabel 或 SubViewport——**推荐简单方式**：敌人体内 `Label3D` 或 HUD 列表；需显示 100HP 受击更新；用 Label3D 头顶显示即可，M1 简单实现）
- **部位 Group**：head/torso/limb 分组（复用 WeaponCore 部位判定）

### 2. 敌人逻辑 `Assets/Models/Characters/Enemy/Enemy.gd` 或 `Levels/Enemy/Enemy.gd`

- 100HP + `take_damage(damage)`（复用 Target 接口，扩展血条更新 + 死亡动画占位）
- **死亡**：HP ≤ 0 → 倒地（旋转 90° 倒地动画/淡出）+ 从活动列表移除
- **不移动**（静态桩，无 AI）
- 持武器：随机 4 种之一（`weapon_slot` 决定挂载的视模型）

### 3. 训练场景 `Levels/Range/L_Range.tscn` + `L_Range.gd`（独立场景）

- **进入即随机生成 3 个敌人**，各持随机武器
- **分散排布不重叠**（用户强调）：生成时用**碰撞检测排布**——候选位置随机（场景内预设几个生成区），检测与已生成敌人的胶囊重叠（`Area3D` 或距离检查 ≥ 1.5m），重叠则重新随机，**保证 3 个敌人互不重叠、都有独立碰撞体积**
- **血条显示**：头顶 Label3D（100HP → 受击更新 → 0 时消失/倒地）
- **全倒后 1s 刷新**：3 个全部 HP ≤ 0 → 1s 计时 → 随机再生成 3 个（新位置 + 新武器）
- 玩家持全部 4 武器（复用 WeaponManager setup，与 L_Main 同模式）+ cheats 无限弹药（默认开）
- 训练场景入口：project.godot 或 L_Main 提示（主场景仍 L_Main；L_Range 手动 `godot --path . Level/...` 或加输入切换——**推荐：project.godot 加启动参数或 L_Main 加数字键切换场景（临时调试）**，简单即可）

### 4. 测试 `test/unit/test_enemy.gd` + `test_range.gd`（RED 先行）

- 敌人：加载场景成功（碰撞体存在）、take_damage 减血、血条更新、死亡（HP≤0 倒地/移除）、部位 Group 正确
- 生成：3 个敌人生成成功、**互不重叠**（距离 ≥ 1.5m）、各持随机武器（4 种覆盖）
- 刷新：全倒 → 1s → 重新生成 3 个（新位置）
- 玩家可命中：hitscan 对敌人（Objects 层）造成伤害（集成）
- 近战/爆炸对敌人同样生效（集成可选）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：test_enemy/test_range 全过 + 全量 160 不回归
3. **有头冒烟**（若可）：`godot --path . Level/Main/L_Range.tscn` 或场景切换——3 敌人可见（持随机武器）、射击打血条、全倒 1s 刷新
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务12 敌人训练场（随机3敌持随机武器 + 血条 + 分散排布 + 全倒刷新）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
