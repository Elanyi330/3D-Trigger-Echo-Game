# Task 12 审查 Brief — 敌人训练场

> 审查对象: 提交 `9f9cace`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 9f9cace 查看 diff）
- `Assets/Models/Characters/Enemy/Enemy.tscn`（15 部件/碰撞/挂点/血条）
- `Levels/Enemy/Enemy.gd`（take_damage/死亡/持武器）
- `Levels/Range/L_Range.gd` + `.tscn`（随机生成/分散排布/刷新）+ settings .tres
- `Weapons/WeaponManager.gd`（hitscan 伤害结算）
- `Levels/Main/L_Main.gd` + `project.godot`（F6 入口）
- 测试（test_enemy 5 + test_range 7）

## 审查标准

### 一、规格合规（对照 spec §9.10 + 任务 12 brief + 用户要求）
1. **敌人模型**：几何拼装（15 部件/3 材质/1.8m）、**碰撞体积**（胶囊 Objects 层）、武器挂点 + 持枪姿态、部位 Group（head/torso/limb）、头顶血条
2. **敌人逻辑**：100HP + take_damage + 死亡（倒地/淡出/移除）+ **不移动**
3. **训练场景**：随机 3 敌持随机武器（4 种覆盖）、**分散排布不重叠**（≥1.5m 重叠重随机）、**全倒 1s 刷新**（新位置新武器）、玩家 4 武器 + cheats
4. **入口**：F6 切换（训练场往返）
5. **不回归**：172/172（含 hitscan/爆炸/近战对敌人集成）

### 二、代码质量
1. 敌人/场景结构清晰、settings 资源化（数值唯一来源）
2. 测试质量（真实断言/物理帧/确定性）
3. 偏差评估：F6 入口（1-4 被武器占用）、部位 Group 代码驱动（引擎不支持 tscn groups）、近战集成测试低姿 origin

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、172/172
2. `godot --headless res://Levels/Range/L_Range.tscn --quit-after 180` 训练场景无错误
3. 抽查：分散排布（≥1.5m）、全倒刷新（1s）、hitscan 伤害结算、血条更新

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
