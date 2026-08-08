# Task 15 审查 Brief — 战斗反馈层

> 审查对象: 提交 `ec85830`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show ec85830 查看 diff）
- `Weapons/WeaponManager.gd`（换弹排队/空仓自动/曳光弹/hitmarker/flinch 接线）
- `Weapons/WeaponCore.gd`（tracer_fired 信号）+ `Weapons/Tracer.gd`（新）
- `Player/Hitmarker.gd`（新，X 形闪烁）+ `Player/Head.gd`（双层 lerp 后坐力）
- `Player/WeaponAnchor.gd`（sway move_toward 归零）
- `Weapons/BulletHole.gd`（挂 collider）
- `Levels/Enemy/Enemy.gd`（flinch 分档）
- `Weapons/Weapon_Resource.gd` + .tres（recoil_val）
- HUD 接线（L_Main/L_Range）
- 测试（+29 项）

## 审查标准（对照任务 15 brief + 参考文档增量清单）

### 一、规格合规
1. **换弹排队 + 空仓自动**（清单 1）：射击中按 R 排队→射完自动换；空仓自动换（备弹>0）
2. **双层 lerp 后坐力**（清单 3）：target/current 两层（base 5.0/target 12.0）+ Y/Z 随机；替代单层；recoil_val .tres 参数化
3. **sway 精确归零**（清单 4）：输入 < 阈值 move_toward 回 0 防漂移
4. **曳光弹**（清单 8）：枪口→命中点 0.1s 淡出
5. **hitmarker**（清单 9）：X 形 0.15s 闪烁（命中敌人）
6. **flinch 分档**（清单 10）：≤10→0.1/≤20→0.25/≤40→0.75/≤101→1.5
7. **弹孔挂 collider**（清单 11）：挂被击中 collider + look_at 贴平
8. **不回归**：226/226

### 二、代码质量
1. 各实现与参考文档一致性（照搬保真度）
2. 测试质量（真实断言/边界）
3. 偏差评估：曳光弹起点相机近似、add_recoil float→Vector3、flinch 作用于 Visuals、sway 阈值缩放空间、Melee/Grenade 不触发 hitmarker

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、226/226
3. 抽查：双层 lerp 回摆、排队换弹、曳光弹淡出、hitmarker 闪烁、flinch 分档、弹孔挂 collider

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
