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

| # | 亮点 | 来源 | 照搬方式 | 状态 |
|---|------|------|---------|------|
| 1 | **换弹排队**（射击中按 R 排队，射完自动换） | CC0 MultiplayerFPS | 照搬 gun.gd:132-138 逻辑到 WeaponManager | 🔴 待做 |
| 2 | **空仓自动换弹**（ammo==0 → 自动 reload） | CC0 MultiplayerFPS | 照搬 | 🔴 待做 |
| 3 | **相机后坐力叠加**（recoil_amount 速率 + 钳制） | CC0 MultiplayerFPS | 对齐我们 Head.add_recoil 接线 | 🟡 已有待完善 |
| 4 | **枪口闪光粒子**（GPUParticles3D） | CC0 + Dragon20C | 枪口挂粒子 | 🟡 已有（检查） |
| 5 | **曳光弹线条**（枪口→命中点 0.1s） | CC0 bullet_tracer | 新增 | 🔴 待做 |
| 6 | **命中标记 hitmarker**（HUD X 闪烁） | CC0 | 新增 HUD | 🔴 待做 |
| 7 | **动画 RESET 回位**（animation_player.play("RESET")） | CC0 gun.gd:224 | 切枪/换弹后复位 | 🔴 待做 |
| 8 | **WeaponSway 容器分层**（sway 作用根、动画作用内部） | CC0 结构 | 已对齐 ✅ | 🟢 已有 |
| 9 | **FPS-Arms-3D 高质量手臂**（MIT rigged） | Ayush-Mohanty | 可替换我们的方块手（可选） | 🔴 可选 |

---

## 四、应用计划（M1 深度优化增量）

1. **换弹排队 + 空仓自动换弹**（亮点 1+2）——CS 式体验核心
2. **相机后坐力对齐**（亮点 3）——recoil_amount 速率模型
3. **枪口闪光核验**（亮点 4）——检查我们的粒子是否挂枪口
4. **曳光弹**（亮点 5）——新增枪口→命中点线条
5. **命中标记 hitmarker**（亮点 6）——HUD 反馈
6. **动画 RESET**（亮点 7）——切枪/换弹后骨架复位
7. **FPS-Arms-3D 手臂**（亮点 9，可选）——提升手模质量
