# M1.75 实施计划 —— 近战/手雷 CS 数值修复 + 统一持握 GripRig

> 分支 feat/m1-assets · 单目录 /Users/elanyi/Projects/Trigger-Echo · 基线 GUT 158/158 绿
> 对应设计：docs/superpowers/specs/2026-08-10-m175-unified-grip-cs-damage-design.md
> 全局铁律：数值唯一来源 weapon_*.tres；TDD RED 先行；验证后才声明完成。
> 合规：CS 数据仅"学习机制"，实现为自研 GDScript（不复制 Valve 代码，CLAUDE.md 红线）。

---

## 阶段 1：伤害修复（小、独立、可单测，先行交付）

### 任务 A：近战跳过 head 组（修复双重结算）
- 文件：`Weapons/MeleeController.gd` `_resolve_swing()`
- 改动：遍历候选目标时 `if target.is_in_group("head"): continue`（CS：近战无部位倍率；head hitbox 转发本体会导致 ×2）。
- RED 测试（新增 `test/unit/test_melee_enemy_double.gd`）：构造真实 `Enemy`（含 HeadHitbox）注入 `melee.targets`，轻击一次 → `take_damage` 恰结算一次 40（非 80）。
- 回归：现有 test_melee.gd 全绿（其夹具无 head 组，不受影响）。

### 任务 B：手雷跳过 head 组（修复双重结算 → 脚下 98 不秒杀）
- 文件：`Weapons/Grenade.gd` `_apply_blast_damage()`
- 改动：命中循环里 `if target.is_in_group("head"): continue`（collider_id 去重拦不住"本体+转发 hitbox"组合）。
- RED 测试（新增 `test/unit/test_grenade_enemy_double.gd`）：真实 `Enemy` 在爆心 1m，爆炸 → 恰结算一次、伤害 98、`health==2`（存活，不秒杀）。

### 任务 C：手雷线性衰减 + 半径 8.89m（CS 同款）
- 公式（Source RadiusDamage，自研实现）：`damage_in_radius(d) = clampf(damage * (1.0 - d/blast_radius), 0.0, damage)`，`d` 为爆心到目标原点距离。
- 文件：
  - `Weapons/Grenade.gd`：`damage_in_radius()` 改线性；移除 `blast_falloff` 读取。
  - `Weapons/weapon_m67.tres`：`blast_radius` 6.0→**8.89**；删除 `blast_falloff` 行；`damage` 保持 98。
  - `Weapons/Weapon_Resource.gd`：移除 `blast_falloff` 字段（先 grep 确认无其他消费方；仅 Grenade 用）。
- 测试改写（有意行为变更）：
  - `test/unit/test_grenade.gd` §2/§4 阶梯断言 → 线性断言：0m=98、4.445m≈49、8.89m→0、>8.89m 不伤害、负距离 0。
  - 期望值一律 `m67.damage`/`m67.blast_radius` 派生，不硬编码散值。
- LOS 遮挡（设计 P1，增强）：**本轮降级延后** → 专项待办。理由：爆心→目标脚底原点的射线极易被地面误判遮挡，需改为指向目标体表中心 + 排除目标自身碰撞体，正确性与无头测试成本高；用户本轮明确诉求是伤害数值（98 不秒杀 + 距离衰减），已满足。列入 M2 地图前待办（见 PROGRESS 遗留）。

---

## 阶段 2：统一持握 GripRig（架构重构，后置）

> 目标：玩家/敌人共用同一组件同一持握数据，方块手（不做精致手模），相机挂玩家模型眼位。
> 风险最高，故置于伤害修复验证通过之后；分小步、每步 GUT 门禁 + 渲染拍照。

### 任务 D：资产拆分 build_character.py（Body/Head 两网格）
- 现单蒙皮网格 → `Soldier_Echo_Body`（无头）+ `Soldier_Echo_Head`（头+眼），同骨架同比例。
- 验证：渲染 view_character 确认敌人两网格正常、无拉伸。

### 任务 E：GripRig 组件（`Character/GripRig.gd`）
- `setup(skeleton)` / `equip(weapon_scene, resource)` / `unequip()` / 每帧双臂两骨 IK。
- GRIP_STYLE 唯一数据表（替代 ViewModel.WEAPON_FRAME + Enemy.ENEMY_WEAPONS）：mount 位姿、双手标志、非持握手空闲姿态。
- 武器挂 WeaponMount（角色根子节点）；IK 目标 = `_GripRight/_GripLeft` 标记世界位；方块手贴合握把朝向。
- RED 测试：equip 后 `_GripRight` 与右手骨位重合（容差）；有 `_GripLeft` 武器左手解算到位；换武器旧实例释放。

### 任务 F：敌人接入 GripRig
- `Enemy.gd._equip_random_weapon()` → `GripRig.equip(随机武器)`；删除 ARM_RAISE_DEG + 固定欧拉角。
- RED 测试：敌人持双手武器左手到位；渲染拍照对比前后姿态。

### 任务 G：玩家接入（真模型 + 眼位相机 + 手感动画迁移）
- Player 下实例化 Soldier_Echo（玩家绿、隐藏 Head）；相机保持眼位 1.63m。
- WeaponView 动画数学保留，输出目标改为 GripRig mount 偏移；ADS 改 _Sight 反推；退役 ViewModel.gd/假下半身。
- 真实尺寸武器（废除 ×2.0/×1.5/×2.2 缩放）。
- RED 测试：Player 下有 Soldier_Echo 且 Head 隐藏；不再创建 ViewModel 盒子。

### 任务 H：渲染验证 + 文档同步 + CS 对比
- photo/view_character 渲染：敌人 4 武器姿态、玩家 4 武器 + ADS + 低头见身体。
- 更新 COMPONENTS.md / cs2-weapon-data.md / PROGRESS / HANDOFF。

---

## 验证关卡（每阶段末）
1. `godot --headless --path . -s addons/gut/gut_cmdln.gd` 全绿。
2. 渲染拍照肉眼核对（渲染工具见 HANDOFF §六）。
3. 阶段 2 末：开游戏供用户亲自验收（用户拍板后才进 M2）。
