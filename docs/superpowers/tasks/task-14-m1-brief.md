# Task 14 Brief — 深度优化（FpsRig 资产 + 握持系统 + 7 项修复）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。
> 资产: 新增 2 个（已复制至 Assets/Quaternius/，未导入——需 `godot --headless --import`）

## 新增资产

| 文件 | 内容 | 许可 |
|------|------|------|
| `Assets/Quaternius/FpsRig_AKM.glb` | **完整 FPS 装备**：Armature（手臂骨骼）+ ArmModel（方块手臂）+ AKM 枪 + Idle/Reload/Shoot 动画（62 帧 Reload ≈1.03s） | J-Toastie **CC-BY 3.0**（可商用，需署名→README 登记） |
| `Assets/Quaternius/AK47_quaternius.glb` | 真实 AK47 造型枪模（长轴 X 1.42m，无动画） | Quaternius **CC0** |

## 交付内容（全部 TDD）

### 1. 枪模反向修复 + 真实 AK 替换（问题 1）
- **AK47_view.tscn ← FpsRig_AKM**（完整装备：AKM 枪 + 手臂 + 骨骼动画）——替换现有 Rifle.glb（X 轴负缩放镜像导致枪托朝前）
- 或 ← AK47_quaternius.glb（纯模型 + 手模分离）
- **任选其一（推荐 FpsRig 一体）**：FpsRig 自带手臂+枪+动画，直接解决枪反向+手模+换弹三合一
- 变换烘焙：枪口对齐 -Z（修反向）；scale 对齐 0.86m 全长
- 保留程序化通道（kickback/sway/bob 在节点位移层）

### 2. 手模替换（问题 2，Minecraft 方块手）
- FpsRig ArmModel（方块手臂）替换现 FpHands 拼装
- 或：重构 FpHands 为**方块手**（手掌 1 Box + 手指 4 Box 粗块，MC 风格——不精细指关节）

### 3. 握持系统（问题 3，不同武器不同握持）
- **步枪（AK）**：右手握扳机 + 左手托枪托（FpsRig Armature 骨骼姿态）
- **手枪（Glock）**：右手持枪 + 左手辅助右手握持（双手）
- **短刀**：单右手握持，左手空置
- **手雷**：右手握持，左手空置；**投掷动作时左手抽拉环**（动画）
- 实现：WeaponAnchor/视模型场景按槽位配置骨骼姿态（FpsRig 骨骼 pose 或代码控制手节点位置）

### 4. 换弹效果补齐（问题 4）
- **AK**：FpsRig Reload 动画（62 帧 ≈1.03s，speed_scale 对齐 reload_time 2.4s）
- **Glock**：**补齐换弹动画**（Pistol.glb 的 Reload 动画——任务 13 只做了 AK，Glock 未接线？核查；若缺用程序化下移+倾斜）

### 5. 刀挥击改为斜挥（问题 5）
- 当前：绕 Y 旋转（平动）→ 改 **绕 X 轴旋转**（左上→右下斜挥，`swing_rot.x` 负向→正向）
- 挥击方向：视模型绕 X 前挥（模拟左上→右下），幅度/时长保留

### 6. 手雷投掷 + 爆炸坑（问题 6）
- **投掷动画**：Grenade 槽位投掷时播投掷动画（左手抽拉环 + 右手抛掷）
- **脱手后脱离玩家**：Grenade 挂到**场景根**（`get_tree().root` 或独立 Projectiles 容器）而非玩家子节点——脱手后不随玩家运动
- **爆炸坑**：ExplosionEffect 加 **Crater**（黑色圆盘 mesh 贴地，爆炸点生成）——**存在 30s 后自动消失**（用户要求）
- 烟尘/光效不随玩家（已随爆炸点生成，修复脱手跟随后自然解决）

### 7. 敌人/弹孔不可见修复（问题 7）
- **敌人**：淡出 scale 缩到 0 后恢复问题（新波次复用？）——修复：新生成时 `_visuals.scale = Vector3.ONE` 复位；排查其他可见性原因
- **弹孔**：Decal 无贴图不可见——加**贴图**（程序化生成圆形黑色贴图或 use 现材），确保可见
- 验证：实机可见

### 8. 测试（RED 先行）
- 枪模：AK47_view 加载含 Armature/AK 正确朝向（枪口 -Z，非反向）
- 握持：4 槽位骨骼姿态/手位置不同（步枪双手/手枪双手/刀右手/雷右手+拉环动画）
- 换弹：AK/Glock 都播 Reload 动画（时长联动）
- 刀：swing_rot.x 变化（斜挥）
- 手雷：投掷动画 + Grenade 挂场景根（非玩家子节点）+ 爆炸坑存在 30s 消失
- 敌人/弹孔：可见性（scale 复位/弹孔有贴图）

## 验证步骤（必须真实运行）
1. `godot --headless --import`（新 glTF 导入）
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：新增测试全过 + 全量 184 不回归
3. 有头冒烟：AK 朝前不反/手模方块/握持区分/换弹动画/刀斜挥/手雷脱手+爆炸坑 30s/敌人弹孔可见
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务14 深度优化（FpsRig 资产 + 握持系统 + 7 项修复）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
