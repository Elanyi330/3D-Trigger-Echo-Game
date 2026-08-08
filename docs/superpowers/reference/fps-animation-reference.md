# FPS 表现层参考文档（第一人称射击/手模/换弹/近战/投掷动画）

> 日期: 2026-08-08
> 来源: GitHub 高星 Godot FPS 项目深度学习（多组并行研究）
> 目的: M1 深度优化参考——照搬优秀实现，保持本项目 CS2 数值特色

---

## 一、项目总览与许可（照搬合规）

| 项目 | 星 | 许可 | 可照搬度 |
|------|-----|------|---------|
| [xLethargy/MultiplayerFPS](https://github.com/xLethargy/MultiplayerFPS) | 5 | **CC0-1.0** | ⭐⭐⭐ 全可照搬（代码+资产） |
| [Whimfoome/godot-FirstPersonStarter](https://github.com/Whimfoome/godot-FirstPersonStarter) | 993 | MIT | ⭐⭐⭐（已移植控制器） |
| [expressobits/character-controller](https://github.com/expressobits/character-controller) | 434 | MIT | ⭐⭐⭐ FPS 版本 |
| [devloglogan/MultiplayerFPSTutorial](https://github.com/devloglogan/MultiplayerFPSTutorial) | 293 | MIT | ⭐⭐⭐ 武器动画完整 |
| [GarbajYT/godot_updated_fps_controller](https://github.com/GarbajYT/godot_updated_fps_controller) | 248 | MIT | ⭐⭐ |
| [Jeh3no/Godot-simple-FPS-weapon-system](https://github.com/Jeh3no/Godot-simple-FPS-weapon-system) | 99 | MIT | ⭐⭐⭐ 完整武器系统 |
| [IMYdev/OpenFPS](https://github.com/IMYdev/OpenFPS) | 58 | MIT | ⭐⭐ |
| [aarroz/simplefps](https://github.com/aarroz/simplefps) | 35 | MIT | ⭐⭐ |
| [GDQuest/godot-3d-fps-beginner-series](https://github.com/GDQuest/godot-3d-fps-beginner-series) | 34 | MIT | ⭐⭐ 教程式 |
| [Ayush-Mohanty/FPS-Arms-3D](https://github.com/Ayush-Mohanty/FPS-Arms-3D) | 3 | MIT | ⭐⭐⭐ 高质量手臂 |
| [Dragon20C/Godot-4.X-Fps-Controller](https://github.com/Dragon20C/Godot-4.X-Fps-Controller) | 5 | **无** | ⭐ 仅学习理念 |

---

## 二、核心模式（多项目共识，照搬基准）

### 2.1 视模型架构（CC0 MultiplayerFPS + FPS-Template 共识）

```
武器场景（WeaponSway 根节点）
├── AllMesh（可整体动画的网格容器）
│   ├── Elements
│   │   ├── Gun（枪模型 MeshInstance）
│   │   ├── MuzzleFlash（GPUParticles3D 枪口闪光）
│   │   └── Arm / Arm2（左右手模型）
├── AnimationPlayer（shoot/reload/idle 动画）
└── Marker3D（子弹发射点）
```

**关键**：**sway/bob 程序化作用于 WeaponSway 根节点**，**动画（shoot/reload）作用于 AllMesh 内骨架**——两层分离不冲突（与我们任务 13 架构一致 ✅）。

### 2.2 相机后坐力（CC0 MultiplayerFPS，直接照搬）

```gdscript
# gun.gd:124-128 —— 开火后相机上抬
if recoil:
    var recoil_adjustment = view.rotation.x + recoil_amount * delta
    if recoil_adjustment > deg_to_rad(90):
        recoil_adjustment = deg_to_rad(90)
    view.rotation.x = recoil_adjustment
```

**要点**：
- `recoil_amount`（如 1.0）为**开火后目标旋转速率**，每帧叠加
- 有上限钳制（90°）
- 射击后靠用户拉回（CS 式）或动画 RESET

### 2.3 换弹动画（CC0 MultiplayerFPS 队列化 + FPS-Template 动画驱动）

```gdscript
# CC0 gun.gd:132-138 —— 换弹排队（射击中按 R 排队）
func reload_weapon():
    if animation_player.current_animation == "shoot" and !queued_reload:
        animation_player.queue("reload")  # 射击动画结束后自动播换弹
        queued_reload = true
    elif !queued_reload:
        animation_player.stop()
        animation_player.play("reload")
```

**要点**：
- **动画队列**：射击中按 R → queue("reload")，射完自动换弹（CS 式体验！）
- 空仓自动换弹：`current_ammo == 0 → play("reload")`
- 换弹完成回调：`animation_finished("reload")` → 弹药补充

### 2.4 枪口闪光（CC0 MultiplayerFPS + Dragon20C 共识）

- **GPUParticles3D 挂枪口**，开火时 `emitting = true` + 短时停止（one_shot）
- Dragon20C muzzle_flash.gd：粒子 + 点光源脉冲

### 2.5 曳光弹（CC0 bullet_tracer.gd）

- 子弹发射生成**短暂线条 mesh**（从枪口到命中点），0.1s 淡出
- 增强命中视觉反馈

### 2.6 命中反馈（多项目共识）

- **弹孔**：命中点 Decal（我们已实现 64×64 贴图 ✅）
- **命中标记**：HUD 十字准星 hitmarker（X 形闪烁 + 音效）
- **受击反馈**：目标受击闪红/震动

### 2.7 近战挥击（FPS-Template melee + 本项目任务 10）

- FPS-Template：`melee_animation` 动画 + ShapeCast3D 扇形判定
- 我们任务 10 已实现扇形判定 ✅；动画需对齐优秀实现（绕 X 斜挥已改进）

### 2.8 投掷动画（本项目任务 14 已实现 + CC0 参考）

- 我们已实现：长按持雷 + 抛物线预览 + 左手抽拉环 + 脱手挂根 ✅

---

## 三、可照搬的亮点清单（对我们项目的增量）

### 3.1 xLethargy MultiplayerFPS（CC0 全可照搬）核心模式

**视模型五层结构**（照搬基准）：
```
Weapon → WeaponSway(代码 sway 目标) → AllMesh(idle/move 动画) → Elements(shoot 后坐动画) → Gun/Arm(右手)/Arm2(左手)
```
- **手模 = 两段式节点旋转**（手掌+手臂 2 mesh，无骨骼无动画控制器，靠父节点旋转做整体动作）——核心结论
- **后坐力叠加到视模型根**（view.rotation.x + recoil_amount×delta，钳制 90°，0.1s 标志位）——相机不动，枪口上抬
- **Sway**：`mouse_input = lerp(mouse_input, ZERO, sens_to_sway*delta)` 回中衰减 + 双轴 lerp；横移倾斜 roll
- **受击 flinch**：伤害分档（≤10→0.1 / ≤20→0.25 / ≤40→0.75 / ≤101→1.5）叠加 view.rotation.x
- **排队换弹**：shoot 中按 R → `animation_player.queue("reload")`；空仓自动 reload
- **mag_type 换弹**：Single 整夹一次补满 / Revolver 左轮式一次补 1 自动重播
- **近战**：60° X 轴下劈（0.6s）+ **动画驱动伤害窗口**（shoot 动画 0 帧开 Hitbox、0.1s 关）+ 2m RayCast + 墙/人音效区分
- **ADS**：全屏瞄具 UI + 枪居中动画 + FOV 20 + 减速；非瞄准散布 = 射线目标点随机偏移
- **双 AnimationPlayer**：战斗动画（shoot/reload）+ 呼吸动画（idle/move）分离互不打断
- **move 动画内嵌 footstep 方法轨道**：编辑器动画最佳实践

**换弹关键帧数值**（devloglogan + xLethargy）：
- 手枪 shoot：0.4s，位置 y -0.25→-0.186 + 旋转 x 0.454rad(26°)→0
- 手枪 reload：2.0s 两拍式：Gun rotation.x 0→-0.611rad(-35°枪口下沉)→+0.262rad(+15°过冲)→0
- 近战挥击：0.6s，rotation.x 1.0472rad(60°)→0（X 轴下劈）

### 3.2 GDQuest 弹孔/命中粒子（可照搬）

- 弹孔：ShotImpact（Sprite3D scorchmark 贴图 shaded）+ 命中粒子，`look_at_from_position` 沿法线偏移 0.001 防 Z-fighting
- 相机 screen_kick：一次性随机后坐 `rotate_local(Vector2(rand_range(-i,i), rand_range(-i,i)))`（0.01, 0.2s）
- 音效 pitch_scale 随机化（1.0 + randf()/20）

### 3.3 simplefps 投掷（可照搬）

- 投掷方向 `basis.z * -1`（沿视线）；手持物线性速度牵引（`vector * 20`）Source 式

### 3.4 对 M1 的增量应用清单（合并组 1 后定稿）

| # | 亮点 | 来源 | 状态 |
|---|------|------|------|
| 1 | **换弹排队 + 空仓自动换弹** | CC0 gun.gd | 🔴 待做 |
| 2 | **视模型五层结构**（Sway/AllMesh/Elements/Gun/手臂分层） | CC0 | 🟡 已有需对齐 |
| 3 | **后坐力叠加视模型**（相机不动枪口抬） | CC0 | 🟡 已有需对齐 |
| 4 | **两拍式换弹动画关键帧**（-35°→+15°→0） | devloglogan+CC0 | 🔴 待做（当前线性） |
| 5 | **近战 60° X 下劈 + 动画驱动伤害窗口** | CC0 stake | 🟡 已 X 斜挥需对齐 |
| 6 | **曳光弹线条**（枪口→命中点） | CC0 bullet_tracer | 🔴 待做 |
| 7 | **命中标记 hitmarker**（HUD X 闪烁） | CC0 | 🔴 待做 |
| 8 | **受击 flinch 分档** | CC0 | 🔴 待做 |
| 9 | **双 AnimationPlayer**（战斗+呼吸分离） | CC0 | 🔴 待做 |
| 10 | **move 动画 footstep 方法轨道** | CC0 | 🔴 待做 |
| 11 | **ADS 全屏瞄具 + FOV 20 + 减速** | CC0 DBSniper | 🟡 已有机瞄需对齐 |
| 12 | **FPS-Arms-3D 高质量手臂**（MIT rigged） | Ayush-Mohanty | 🔴 可选 |

---

## 四、应用计划（M1 深度优化增量）

1. **换弹排队 + 空仓自动换弹**（亮点 1+2）——CS 式体验核心
2. **相机后坐力对齐**（亮点 3）——recoil_amount 速率模型
3. **枪口闪光核验**（亮点 4）——检查我们的粒子是否挂枪口
4. **曳光弹**（亮点 5）——新增枪口→命中点线条
5. **命中标记 hitmarker**（亮点 6）——HUD 反馈
6. **动画 RESET**（亮点 7）——切枪/换弹后骨架复位
7. **FPS-Arms-3D 手臂**（亮点 9，可选）——提升手模质量
