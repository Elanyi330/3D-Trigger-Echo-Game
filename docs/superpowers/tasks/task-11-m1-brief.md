# Task 11 Brief — 模型质感提升 + 爆炸效果 + 无限弹药测试环境

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> spec: `docs/superpowers/specs/2026-08-06-m1-weapon-system-design.md` §9.6/9.8/9.9（先读）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 148/148 全绿

## 必读文件（动手前先读）
1. spec §9.6（模型质感）/§9.8（爆炸效果）/§9.9（无限弹药）
2. `/Users/elanyi/Projects/Trigger-Echo-m1/docs/superpowers/reference/m1-src/explosion.gd`（Mucurata，MIT——爆炸结构参考）
3. `/Users/elanyi/Projects/Trigger-Echo-m1/Assets/Models/`（现有拼装模型——本次提升）
4. `/Users/elanyi/Projects/Trigger-Echo-m1/Weapons/WeaponCore.gd`（infinite_ammo 接入点）
5. `/Users/elanyi/Projects/Trigger-Echo-m1/Levels/Main/L_Main.gd`（cheats 开关）

## 交付内容

### 1. 模型质感提升（§9.6，几何拼装框架内）

**枪模 8-12 部件**（现有 3-4 → 提升）：
- AK47_view：枪管 + 护木 + 机匣 + 弹匣（**弯曲弧线**——AK 标志性弹匣，可用多个小 Box 斜接或 CSG）+ 握把 + 枪托 + 准星 + 导轨 + 拉机柄 + 散热孔
- Glock18_view：枪身 + 套筒 + 枪管 + 握把 + 扳机护圈 + 准星
- **多材质**（Assets/Materials/）：gun_metal（金属高光 metallic=0.8）+ gun_dark（深色聚合物）+ grip_texture（握把）+ wood（枪托木色，AK）——2-3 材质混用每枪
- **比例调优**：按真实枪械轮廓（AK 枪管长/弹匣弯/枪托直）

**手模**（FpHands）：
- 手掌 + **5 指关节**（每指 2-3 段 Box 可弯曲，静态拼装即可——手指分段体现关节）
- 持枪位贴合（手包枪，位置/旋转调优）

**统一标准**：本次提升即 `Assets/Models/` 规范（未来角色/敌人/地图同标准）——建议在 `Assets/Models/README.md` 写规范（部件数/材质数/比例要求）

### 2. 手雷爆炸效果（§9.8，参考 Mucurata explosion）

- `Weapons/Grenade.gd` 爆炸时生成 `Weapons/ExplosionEffect.gd`（Node3D）：
  - **GPUParticles3D** 火花粒子（短时喷射 0.5s）
  - **OmniLight3D** 闪光（light_energy 8.0 → 0 衰减，1.5s）
  - **冲击波环**：扩散圆环 mesh（0.3s 放大 + 淡出）
- 生命周期 1.5s 后 queue_free；位置 = Grenade 爆炸点
- 参考 Mucurata `explosion.gd`（MIT，结构可参考：particles + light + lifetime）

### 3. 无限弹药测试环境（§9.9，cheats 开关）

- WeaponCore 加 `infinite_ammo: bool = false`：
  - true 时开火不扣弹（或自动补满）、换弹瞬时满、备弹无穷
  - M67 投出后自动补 1 枚（投掷路径等价 refund）
- L_Main 加 `cheats: bool = true`（**默认开启**供测试版；正式版 M6 关闭）→ setup 时对所有核心置 `infinite_ammo = true`
- 目的：反复体验射击/投掷不打断测试流

### 4. 测试 `test/unit/test_quality_effects.gd` + `test_infinite_ammo.gd`（RED 先行）

- 爆炸效果：explode → 生成 ExplosionEffect（粒子/灯光/环存在）、1.5s 后释放
- 无限弹药：infinite_ammo=true → 开火弹匣不减、换弹瞬时满、M67 投出后自动补 1 枚
- 模型：4 视模型场景加载成功（部件数 ≥ 8 断言——场景子节点 MeshInstance3D 计数）、FpHands 5 指结构（部件数 ≥ 8）
- L_Main cheats 默认 true → 场景中核心 infinite_ammo

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：新增测试全过 + 全量 148 不回归
3. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务11 模型质感提升 + 爆炸效果 + 无限弹药测试环境"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
