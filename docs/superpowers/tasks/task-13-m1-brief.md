# Task 13 Brief — Quaternius 资产接入（替换拼装模型 + 全功能适配 + 动画驱动）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。
> 资产: Quaternius CC0（已下载至 `Assets/Quaternius/`，Godot 已导入验证）

## 资产清单（已就位）

| 文件 | 内容 | 动画（Godot AnimationPlayer 自动生成） |
|------|------|------|
| `Assets/Quaternius/Rifle.glb` | 步枪（对应 AK-47） | FireWBullet / FireWOBullet / **Reload** |
| `Assets/Quaternius/Pistol.glb` | 手枪（对应 Glock） | FireWBullet / FireWOBullet / Reload |
| `Assets/Quaternius/Shotgun.glb` | 霰弹枪（M870 预留） | FireWBullet / FireWOBullet / Reload |
| `Assets/Quaternius/SniperRifle.glb` | 狙击枪（AWM 预留） | FireWBullet / FireWOBullet / Reload |
| `Assets/Quaternius/P90.glb` | SMG（MP5 预留） | FireWBullet / FireWOBullet / Reload |
| `Assets/Quaternius/Revolver.glb` | 左轮（备用） | FireWBullet / FireWOBullet / Reload |
| `Assets/Quaternius/BaseCharacter.glb` | 人形角色 | Idle/Run/Death/RecieveHit/Shoot_OneHanded/SwordSlash/Punch 等 15 个 |

**全部 CC0**（Quaternius 官方确认，可商用/修改/无需署名）——README 许可证章节登记。

## 交付内容

### 1. 武器视模型替换（枪模 + 手部 + 动画驱动）

**视模型**：`Assets/Models/Weapons/` 下的 Box 拼装 tscn 全部替换为 Quaternius glTF 场景：
- AK47_view.tscn ← Rifle.glb（骨架 + AnimationPlayer 自动生成）
- Glock18_view.tscn ← Pistol.glb
- Knife_view.tscn ← 保留拼装刀（Quaternius 无刀——可用 SwordSlash 动画思路 + 现拼装刀，或 BaseCharacter 持刀姿态）
- Grenade_view.tscn ← 保留拼装手雷（Quaternius 无手雷）
- 手部 FpHands.tscn ← 保留拼装手（Quaternius 枪模自带持枪姿态；或简单调位）

**⚠️ 关键——动画驱动（用户要求"换弹动画搬出来"）**：
- 用 glTF 自带的 **AnimationPlayer**（Godot 导入时自动创建）驱动真实换弹/开火动画
- **换弹**：`reload_started` → `anim_player.play("Reload")`（时长 = reload_time 联动；Quaternius Reload 动画 1-2s，与 AK 2.4s/Glock 2.3s 匹配——若时长差大，`anim_player.play("Reload", -1, speed)` 用 speed 缩放）
- **开火**：`shot_fired` → `anim_player.play("FireWBullet")`（每次射击播一次）
- **空仓**：`out_of_ammo` → `anim_player.play("FireWOBullet")`
- **程序化通道保留**：kickback/sway/bob 三通道仍叠加（动画管"形态动作"，程序化管"手感反馈"——两者合成，参考现有 `_apply_motions` 框架，动画作用于模型的骨架动画，程序化作用于 WeaponAnchor 节点位移）
- **测试**：换弹触发 AnimationPlayer 播 Reload、开火播 FireWBullet、时长联动（speed 缩放）

### 2. 敌人模型替换（BaseCharacter/BlueSoldier + 动画）

- `Assets/Models/Characters/Enemy/Enemy.tscn` ← BaseCharacter.glb（或 BlueSoldier 变体随机）
- 敌人动画接入：
  - **Idle**：待机播放（训练场静态桩）
  - **RecieveHit**：受击播放（take_damage 时）
  - **Death**：死亡播放（HP≤0 时，替代现有旋转倒地）
  - **Shoot_OneHanded**：持枪姿态参考（敌人持随机武器时）
- 碰撞体积/血条/部位 Group/武器挂点逻辑保留（Enemy.gd 复用，模型替换 + 动画接线）
- **测试**：敌人受击播 RecieveHit、死亡播 Death、待机 Idle 循环

### 3. 全功能适配（现有 172 测试不回归 + 新适配测试）

- 所有引用了 `Assets/Models/Weapons/*_view.tscn` 的代码/场景自动适配（WeaponAnchor 挂载逻辑不变，只是模型内容换）
- WeaponManager view_models 数组不变（指向新 tscn）
- 换弹/开火动画接线到 WeaponAnchor 或视模型场景内 AnimationPlayer
- 敌人持枪姿态：Quaternius 枪模挂到敌人 WeaponMount + 双臂姿态调整
- **172 测试必须全绿**（模型替换不影响逻辑测试——测试断言部件数 ≥8 的**需改**：现在改断言"glTF 场景加载成功 + AnimationPlayer 存在"）

### 4. 测试更新 `test/unit/`（RED 先行）

- `test_view_model.gd`：部件数断言 → 改为"glTF 场景加载 + AnimationPlayer 存在 + 动画名含 Reload/Fire"
- `test_weapon_animations.gd`：新增——换弹播 Reload（时长联动）、开火播 FireWBullet、空仓播 FireWOBullet
- `test_enemy.gd`：新增——受击播 RecieveHit、死亡播 Death、待机 Idle
- 保留：程序化通道（kickback/sway/bob）测试不变（节点位移层）

## 验证步骤（必须真实运行）
1. `godot --headless --import`（glTF 导入）
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：更新/新增测试全过 + 全量不回归
3. **有头冒烟**：L_Main 持枪可见 Quaternius 枪模、换弹播动画、开火播动画；L_Range 敌人为 Quaternius 角色 + 受击/死亡动画
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务13 Quaternius CC0 资产接入（枪模/角色替换 + 动画驱动换弹/开火/受击/死亡）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
