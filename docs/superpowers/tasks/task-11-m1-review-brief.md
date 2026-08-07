# Task 11 审查 Brief — 模型质感 + 爆炸效果 + 无限弹药

> 审查对象: 提交 `068a6af`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 068a6af 查看 diff）
- `Weapons/ExplosionEffect.gd`（粒子/灯光/冲击波环）
- `Weapons/Grenade.gd`（爆炸生成效果）
- `Weapons/WeaponCore.gd` + `WeaponManager.gd`（infinite_ammo）
- `Levels/Main/L_Main.gd`（cheats 默认 true）
- `Assets/Models/`（4 视模型 8-12 部件 + FpHands 5 指 + Materials 4 材质 + README 规范）
- 测试（test_quality_effects 6 + test_infinite_ammo 6）

## 审查标准

### 一、规格合规（对照 spec §9.6/9.8/9.9 + 任务 11 brief）
1. **模型质感**：枪模 ≥8 部件（AK 12/Glock 12/刀 9/雷 10）、≥3 材质混用、手模 5 指×2 段、Assets/Models/README 规范
2. **爆炸效果**：GPUParticles3D 火花 + OmniLight3D 闪光衰减（8.0→0）+ 冲击波环（0.3s 放大淡出）；1.5s 生命周期；Grenade 爆炸点生成
3. **无限弹药**：infinite_ammo 标志（空匣自动补满/换弹瞬时/备弹恒满/M67 投出补 1）；L_Main cheats=true 默认
4. **不回归**：160/160

### 二、代码质量
1. ExplosionEffect 结构清晰、生命周期管理（1.5s queue_free）
2. 模型拼装质感（比例/材质/部件合理性）
3. 测试质量（真实断言/确定性）
4. 偏差评估：空匣自动补满 vs 不扣弹（效果等价）、AK 12 部件、Glock U 形护圈

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、160/160
2. 抽查：爆炸三组件、infinite_ammo 行为、模型部件数（场景节点计数）

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
