# Task 5 审查 Brief — 拼装视模型 + WeaponAnchor

> 审查对象: 提交 `182fead`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 182fead 查看 diff）
- `Assets/Models/Weapons/AK47/AK47_view.tscn` 等 4 视模型 + `Hands/FpHands.tscn` + `Materials/` 2 材质 + `Characters/.gitkeep`
- `Player/WeaponAnchor.gd` + `.tscn`（class_name WeaponAnchor）
- `Weapons/WeaponManager.gd`（view_models 导出 + get_view_model 防御）
- `test/unit/test_view_model.gd`（14 项）

## 审查标准

### 一、规格合规（对照计划 §4 + 任务 5 brief + 资产决策）
1. **资产决策**：全部 BoxMesh/CylinderMesh/SphereMesh 拼装，零外部资产；每模型独立目录（AK47/ 等）；未来原位替换可行
2. **WeaponAnchor**：position=(0.25,-0.25,-0.5)；订阅 weapon_switched(slot) → 换挂视模型（0→AK47/1→Glock18/2→Knife/3→Grenade）；手部常显（CS 式）；后坐力 kick（Z 位移 0.02m + 回弹）
3. **Manager 集成**：view_models Array[PackedScene] 4 槽位 + 越界防御；Manager 保持纯逻辑（Anchor 订阅信号）
4. **纯离线**：无外部资源/网络
5. **M0 不回归**：96/96 全绿

### 二、代码质量
1. 场景结构清晰（节点命名/层次）、材质合理
2. 测试质量：场景加载断言、信号订阅行为、kick 位移/回弹
3. 偏差评估：目录布局（每模型独立目录 vs brief 扁平路径）、Player.tscn/L_Main 未改（集成属任务 6）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、96/96 全绿
3. 抽查：WeaponAnchor 场景结构（挂点坐标）、kick 位移/回弹实现、Manager view_models 接线

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
