# Task 6 审查 Brief — 场景集成 + 收尾事项

> 审查对象: 提交 `020b20e`（feat/m1-weapon-system，工作树 /Users/elanyi/Projects/Trigger-Echo-m1）
> 审查方式: 双裁定——①规格合规 ②代码质量

## 审查范围（git show 020b20e 查看 diff）
- `Levels/Main/L_Main.tscn` + `L_Main.gd`（武器层：WeaponManager/WeaponAnchor/靶子/HUD/输入绑定）
- `Weapons/WeaponManager.gd`（相机缓存/set_head/右键取消投掷/真实 Grenade 接线）
- `Weapons/WeaponCore.gd`（refund_throw 弹药返还）
- `Player/Head.gd`（set_ads 防护 + ads_multiplier 写入时机）
- `Levels/Main/Target.gd`（100HP + take_damage）
- `test/unit/test_integration.gd`（7 项）

## 审查标准

### 一、规格合规（对照计划 §4 + 任务 6 brief + 企划书 §4.2.3⑦）
1. **L_Main 武器层**：WeaponManager（Player 下）+ WeaponAnchor（Head 下）+ 预装载 4 .tres + 4 视模型 + 靶子（Objects 层 Group "torso" 2-3 距离）+ 弹药 HUD（CS 式 "30 / 90"）
2. **输入绑定**：fire（按住）/reload/aim/weapon_1-4/next_weapon → WeaponManager；weapon_switched → HUD
3. **M0 不回归**：L_Main 移动/下蹲/掩体原样；全量 103/103
4. **收尾事项**：①Head.set_ads multiplier 防护（maxf→1.0）②ads_multiplier 仅 active 写入 ③M67 右键取消投掷（弹药不消耗）④WeaponManager 相机路径（集成断言 hit_landed）⑤Grenade 接入（真实 init）
5. **企划书对齐**：M67 投掷（弹道 15m/s）/取消（弹药返还）/爆炸（Target.take_damage 通用结算）
6. **数值唯一来源**：throw_strength 等参数化 export；纯离线

### 二、代码质量
1. L_Main 集成清晰（setup 顺序、信号接线）、Target 结算接口通用
2. 测试质量：集成断言真实（hit_landed/取消/爆炸）、物理帧推进
3. 偏差评估：投掷模型重构（扣弹于按下/Grenade 于释放生成）、HUD 双信号互补、靶子布局（CoverShort 遮挡处理）

## 验证（必须真实运行）
1. 进入 `/Users/elanyi/Projects/Trigger-Echo-m1`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0、103/103 全绿
3. `godot --headless --path . --quit-after 300` 主场景启动无错误
4. 抽查：L_Main 集成（setup 顺序/相机解析/输入绑定）、右键取消投掷逻辑、Grenade 接线

## 输出格式
```
裁定：PASS / FAIL（规格合规）
裁定：PASS / FAIL（代码质量）
发现的问题（按严重度：关键/重要/次要）：
- [严重度] 文件:行 — 描述 — 建议修复
结论：批准 / 需修复（列出必须修复项）
```
