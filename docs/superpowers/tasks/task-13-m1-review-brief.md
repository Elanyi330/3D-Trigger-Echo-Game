# Task 13 审查 Brief — Quaternius 资产接入

> 审查对象: 提交 `11c500b`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 11c500b 查看 diff）
- `Assets/Models/Weapons/AK47/AK47_view.tscn` + `Glock18/Glock18_view.tscn`（← Quaternius glTF，含烘焙变换）
- `Assets/Models/Characters/Enemy/Enemy.tscn`（← BaseCharacter.glb）
- `Player/WeaponAnchor.gd`（动画驱动换弹/开火/空仓 + 程序化通道保留）
- `Levels/Enemy/Enemy.gd`（Idle/RecieveHit/Death 动画 + 部位 Group 递归扫描）
- `Assets/Quaternius/`（CC0 资产 + .import）
- `README.md`（许可证登记）+ `Assets/Models/README.md`
- 测试（+12 项：动画驱动/glTF 断言/敌人动画）

## 审查标准

### 一、规格合规（对照任务 13 brief + 用户要求）
1. **武器替换**：AK←Rifle.glb / Glock←Pistol.glb（Knife/Grenade/手部保留拼装——Quaternius 无对应，符合 brief）
2. **换弹动画搬出**（用户核心）：reload_started → AnimationPlayer.play("Reload")，时长与 reload_time 联动（speed_scale 缩放）；开火 FireWBullet 每发一播；空仓 FireWOBullet
3. **程序化通道保留**：kickback/sway/bob 与动画共存（动画管骨架、程序化管节点位移）
4. **敌人替换**：Enemy ← BaseCharacter.glb；Idle 待机循环/RecieveHit 受击/Death 死亡动画；碰撞/血条/武器挂点保留
5. **全功能适配**：view_models 指向新 tscn；184/184 不回归
6. **CC0 合规**：README 许可证登记 Quaternius

### 二、代码质量
1. glTF 变换烘焙正确（朝向/尺度对齐）
2. 动画驱动实现（play 时机/时长联动/回退匹配）
3. 测试质量（真实断言/动画播放验证）
4. 偏差评估：Pistol 动画名回退（Fire/Slide vs FireWBullet/FireWOBullet）、部位 Group 单网格 torso

## 验证（必须真实运行）
1. `cd /Users/elanyi/Projects/Trigger-Echo-m1 && godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、184/184
3. 抽查：动画驱动（Reload 播放/时长联动）、敌人 Idle/RecieveHit/Death、glTF 场景挂载

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）
结论：批准 / 需修复
```
