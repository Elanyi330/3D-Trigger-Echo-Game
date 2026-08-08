# Task 16 Brief — 深度优化 B：动画表现层（双 AnimationPlayer/两拍式换弹/近战节奏/投掷动画）

> 分支: `feat/m1-weapon-system`（工作树 `/Users/elanyi/Projects/Trigger-Echo-m1`）
> 参考: `docs/superpowers/reference/fps-animation-reference.md`（§三 3.1/3.6/3.7/3.8/3.9 + §四 增量清单 2/6/7/12/13/15）
> 方法: TDD 铁律——先写失败测试（RED）→ 确认失败原因 → 实现（GREEN）→ REFACTOR。不跳步。

## 工作环境
- 工作树: `/Users/elanyi/Projects/Trigger-Echo-m1`
- 测试命令: `godot --headless -s addons/gut/gut_cmdln.gd`（退出码 0 = 全绿）
- 当前测试基线: 226/226 全绿

## 交付内容（增量清单 2/6/7/12/13/15）

### 1. 双 AnimationPlayer 分离（清单 12，CC0 + fps-arms）
- 视模型场景加**第二个 AnimationPlayer**（`AnimationPlayerIdle`）：idle 呼吸动画（位置 y 微幅下沉 + 旋转 x 微幅，循环）
- 现有 AnimationPlayer（战斗：shoot/reload）保持
- **分离互不打断**：战斗动画播放时 idle 暂停，结束恢复
- 测试：idle 循环播放、战斗动画打断 idle、结束恢复 idle

### 2. 两拍式换弹动画（清单 6，devloglogan + Jeh3no 关键帧）
- AK/Glock 换弹动画改为**两拍式**（非当前线性）：
  - 手枪（参考 devloglogan）：rotation.x 0→-0.611rad(-35° 枪口下沉)→+0.262rad(+15° 过冲)→0（2s 或对齐 reload_time）
  - 步枪（参考 Jeh3no）：position z 0→-0.006 下沉 + rotation Y 0→1.396rad(80° 横转)→0
- 实现：程序化关键帧插值（WeaponAnchor 换弹通道改两拍曲线）或 AnimationPlayer 关键帧
- 测试：换弹动画经过中间态（下沉→过冲→回位）、时长对齐

### 3. 近战挥击节奏（清单 7，GarbajYT 数值）
- 挥击改 **0.02s 快下挥 70° + 0.1s 慢回位**（当前 sin 包络太慢）：
  - 轻击：0.02s 绕 X 快速下挥 70° → 0.1s 慢回位（1:5 节奏）
  - 重刺：类似快出手慢回
- 命中判定窗口 = 下挥期（快挥瞬间）
- 测试：下挥快（0.02s 达 70°）、回位慢（0.1s）、节奏比例

### 4. 投掷动画对齐（清单 13，CC0 蓄力→挥出）
- 手雷投掷：**蓄力动画**（0.5s 后拉 30° 持雷手臂）→ 挥出（反向挥回）
- 现有抽拉环动画保留（引信阶段）
- 测试：蓄力后拉、挥出回位、节奏

### 5. ADS 对齐（清单 15，fps-arms 正反播）
- 机瞄改用**动画正反播**（`play("AimAnim")` / `play_backwards`）替代即时 FOV 缩放——枪滑向视线中心 + FOV 联动
- 测试：开镜动画播放、关镜反向、FOV 联动

### 6. 动画信号驱动（清单 2，OpenFPS）
- 换弹完成改用 AnimationPlayer `animation_finished("reload")` 信号驱动（替代计时器）——动画时长在动画里调，代码零改动
- 测试：动画完成触发换弹结算（非计时器）

## 验证步骤（必须真实运行）
1. `godot --headless --import`
2. `godot --headless -s addons/gut/gut_cmdln.gd` 退出码 0：新增测试全过 + 全量 226 不回归
3. 有头冒烟（若可）：两拍式换弹/快挥慢回/蓄力投掷/ADS 正反播/idle 呼吸
4. git commit（工作树内）：`git add -A && git commit -m "feat: M1 任务16 动画表现层（双AnimationPlayer/两拍式换弹/近战节奏/投掷蓄力/ADS正反播）"`

## 完成报告
返回：DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED
- 报告内容：实现的文件清单、测试结果摘要、遇到的问题、与 brief 的偏差
