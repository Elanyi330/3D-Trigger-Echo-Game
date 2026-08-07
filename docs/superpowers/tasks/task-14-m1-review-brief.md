# Task 14 审查 Brief — 深度优化（FpsRig + 握持系统 + 7 项修复）

> 审查对象: 提交 `98c521c`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 98c521c 查看 diff）
- `Player/WeaponAnchor.gd`（握持系统 4 槽位/FpsRig Idle+动画/刀 X 斜挥/抽拉环）
- `Weapons/WeaponManager.gd`（throw_primed 信号/手雷挂 root 脱手）
- `Weapons/ExplosionEffect.gd` + `Weapons/Crater.gd`（爆炸坑 30s）
- `Weapons/BulletHole.gd`（贴图修复可见）
- `Levels/Enemy/Enemy.gd`（scale 复位）
- `Assets/Models/Weapons/AK47/AK47_view.tscn`（FpsRig 包装/枪口 -Z）+ `FpHands.tscn`（MC 方块手）+ `AK47_world.tscn`（敌人持枪）
- `Assets/Quaternius/FpsRig_AKM.glb` + `AK47_quaternius.glb`（新资产）
- `README.md`（CC-BY 3.0 署名）
- 测试（+12 项）

## 审查标准（对照任务 14 brief，7 项用户问题）

### 一、规格合规
1. **枪模反向**：AK47_view 枪口 -Z（非镜像反向）+ 0.86m 全长
2. **手模**：MC 风格方块手（手掌 1 Box + 4 指粗块 ×2）
3. **握持系统**：4 槽位区分——步枪双手（右扳机左托枪）/手枪双手/刀单右手/雷单右手+投掷抽拉环动画
4. **换弹补齐**：AK FpsRig Reload（speed_scale 对齐 2.4s）+ Glock 换弹（时长联动确认）
5. **刀斜挥**：swing 绕 X 轴（左上→右下）
6. **手雷脱手+爆炸坑**：Grenade 挂场景根（不随玩家）+ Crater 30s 自动消失
7. **可见性**：敌人 scale 复位 + 弹孔贴图
8. **CC-BY 合规**：README 署名登记；196/196 不回归

### 二、代码质量
1. 握持系统实现（骨骼姿态/手位置/动画衔接）
2. Crater 实现（贴地/生命周期）
3. 手雷挂根（时序/清理）
4. 测试质量（真实断言）
5. 偏差评估：敌人持枪 AK47_world 纯枪模（防手臂套手臂）、Glock 换弹已接线、刀斜挥 X 轴实现

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、196/196
3. 抽查：握持 4 槽位、刀 X 斜挥、手雷挂根、Crater 30s、弹孔贴图、敌人 scale

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
