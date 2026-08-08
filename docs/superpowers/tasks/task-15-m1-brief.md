# Task 15 Brief — 深度优化 A：战斗反馈层（换弹排队/双层后坐力/曳光弹/hitmarker/flinch）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 参考: `docs/superpowers/reference/fps-animation-reference.md`（深度学习 11 项目成果，先读 §三 3.1/3.4/3.5/3.6/3.9 + §四 增量清单）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 197/197 全绿

## 交付内容（增量清单 1/3/4/5/8/9/10/11）

### 1. 换弹排队 + 空仓自动换弹（清单 1，CC0 gun.gd 照搬）
- **射击中按 R → 排队换弹**：`animation_player.queue("reload")` 等价——WeaponManager 加 `_queued_reload`，当前槽位射击动画/冷却中按 R 标记排队，射完自动 start_reload
- **空仓自动换弹**：弹匣空（out_of_ammo）→ 自动 start_reload（若备弹 > 0）
- 测试：射击中按 R 排队（射完自动换）、空仓自动换、备弹 0 不自动换

### 2. 双层 lerp 相机后坐力（清单 3，Jeh3no 22 行照搬）
- Head 后坐力改为 **target_rotation/current_rotation 双层 lerp**：
  ```gdscript
  target_rotation = lerp(target_rotation, Vector3.ZERO, base_rotation_speed * delta)
  current_rotation = lerp(current_rotation, target_rotation, target_rotation_speed * delta)
  rotation = current_rotation  # 叠加到现有视角
  func add_recoil(recoil_value : Vector3):
      target_rotation += Vector3(recoil_value.x, randf_range(-recoil_value.y, recoil_value.y), randf_range(-recoil_value.z, recoil_value.z))
  ```
- 参数：base_rotation_speed=5.0、target_rotation_speed=12.0、recoil_val（AK (0.06,0.02,0.02)/Glock (0.04,0.015,0.015)，.tres 参数化）
- 替代现 `recoil_offset` 单层——**快抬-慢回+抖动**手感
- 测试：add_recoil 后 current_rotation 抬升 + 回摆归零、Y/Z 随机抖动、参数化

### 3. sway move_toward 精确归零（清单 4，Jeh3no 关键细节）
- WeaponAnchor sway 通道：鼠标输入 < 阈值（4.0）时用 `move_toward(…, 0, back_to_origin_speed*delta)` **精确归零**（防 lerp 漂移）
- 测试：停止鼠标后 sway 精确回 0（非无限逼近）

### 4. 曳光弹线条（清单 8，CC0 bullet_tracer）
- 新类 `Weapons/Tracer.gd`：射击时生成**枪口→命中点短暂线条**（QuadMesh/ImmediateMesh），0.1s 淡出自清
- 触发：shot_fired 后从枪口 Marker 到 hit_landed 位置（未命中则到 max_range 端点）
- 测试：开火生成 tracer、0.1s 消失、位置正确

### 5. 命中标记 hitmarker（清单 9，CC0 HUD）
- L_Main/L_Range HUD 加 **hitmarker**（命中时 X 形闪烁 0.15s + 音效占位）
- 触发：hit_landed 命中敌人（非靶子）
- 测试：命中触发 hitmarker 显示、0.15s 隐藏

### 6. 受击 flinch 分档（清单 10，CC0 照搬）
- Enemy 受击：伤害分档 flinch（≤10→0.1 / ≤20→0.25 / ≤40→0.75 / ≤101→1.5）——视模型/整体后仰
- 测试：小伤小 flinch、大伤大 flinch

### 7. 弹孔挂 collider 下（清单 11，GarbajYT decals）
- BulletHole 生成改为**挂到被击中 collider 下**（随物体动）+ `look_at(点+法线)` 贴平
- 测试：弹孔父节点 = collider、贴合法线

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：新增测试全过 + 全量 197 不回归
3. 有头冒烟（若可）：换弹排队/曳光弹/hitmarker/flinch/弹孔随目标动
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务15 战斗反馈层（换弹排队/双层后坐力/曳光弹/hitmarker/flinch/弹孔挂collider）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
