# M1 资产先行 — 开发进度（2026-08-08）

> 分支: `feat/m1-assets`（工作树 ../Trigger-Echo-m1-assets）
> 上游: main 已回退到 M0 完成点 bfdf669（M0 运动逻辑 14/14 保留）
> M1 旧分支: `feat/m1-weapon-system`（29 提交保留，含 FpsRig/动画实现，M1.5 配套时参考）

---

## 一、开发策略调整（用户 2026-08-08 拍板）

**旧模式失败**：逻辑先行 → 资产后补 → 实机崩（5 轮 TDD 全绿但体验极差）
**新模式**：资产先行 → Blender/CC0 建模完美 → 查看器验证 → M1.5 融入运动逻辑

**里程碑重定义**：
| 里程碑 | 内容 |
|--------|------|
| M0 | 引擎骨架 + 运动逻辑 ✅（bfdf669，14/14） |
| **M1（新）** | **纯资产开发**：武器/角色/手模建模 + 查看器验证（当前阶段） |
| **M1.5（新）** | 资产配套：融入 M0 运动逻辑 + 武器开火/换弹/攻击逻辑 |
| M2+ | 地图/模式/AI（企划书原计划顺延） |

## 二、资产规范（用户确认）

**大小（视模型 = 真实 × 1.4，FPS 惯例）**：
| 武器 | 真实 | 视模型 | 状态 |
|------|------|--------|------|
| AK47 | 0.86m | 1.20m | ✅ 已归一化 |
| Glock18 | 0.20m | 0.28m | ✅ 已归一化 |
| Revolver（备用） | 0.28m | 0.39m | ✅ 已归一化 |
| 战术刀 | 0.35m | 0.49m | ✅ 已归一化（刀身金属灰/握把木棕） |
| M67 手雷 | 0.10m | 0.14m | ✅ 已归一化 |

**角色规范**：玩家/队友/敌人建模一致仅颜色区分；统一方块手（MC 风格）；整体偏方块特色；高 1.75m（对齐 M0 胶囊 1.83m）。

## 三、资产来源与许可（全合规）

| 资产 | 来源 | 许可 | 位置 |
|------|------|------|------|
| AK47 | poly.pizza Quaternius | CC0 | Assets/Models/Weapons/AK47/AK47.glb |
| Glock18 | Quaternius Animated FPS Guns | CC0 | Assets/Models/Weapons/Glock18/Glock18.glb |
| Revolver | Quaternius Animated FPS Guns | CC0 | Assets/Models/Weapons/Revolver/Revolver.glb |
| 战术刀 | poly.pizza Naj Combat Knife | CC-BY 3.0（署名） | Assets/Models/Weapons/Knife/Knife.glb |
| M67 手雷 | poly.pizza Pichuliru Frag West | CC0 1.0 | Assets/Models/Weapons/Grenade/Grenade.glb |
| 角色 | **自产**（Blender 脚本，方块风） | 自产 CC0 | Assets/Models/Characters/Player/Player.glb |

## 四、当前进度（进行中）

### ✅ 已完成
1. **main 回退 M0 点** bfdf669（M0 14/14 验证通过）
2. **feat/m1-assets 分支** + 工作树 ../Trigger-Echo-m1-assets 就位
3. **五件武器全部入库 + 统一缩放**（见上表）
4. **资产规范文档** Assets/Models/README.md
5. **角色 v5 建模**（Blender 脚本自产）：Z-up 站立 1.75m、小头 0.28m、四肢两段式 + 15 骨骨骼（肘/膝可弯）
6. **Godot 资产查看器**（Assets/Viewer/Viewer.gd + Viewer.tscn）：
   - 人物 + 武器 + 鼠标拖拽 360° 查看 + 1/2/3/4 切武器
   - 已修复：人物朝向（绕 Y 180° 面朝 -Z）、武器朝向（绕 Y -90° 枪口朝前）、手臂姿势（Skeleton3D set_bone_pose_rotation + Quaternion）

### 🔄 进行中（用户最后查看）
- **人物持四武器姿态展示**：AK47 姿态已装配（枪口朝前 + 手臂握枪），用户最后反馈"人物面朝反了"→ 已修（人物转 180°）
- 待用户确认：人物面朝前 + 手臂前伸 + AK47 枪口朝前是否满意
- 待做：Glock/刀/手雷三种姿态确认

### 🔴 待做
1. 四种武器姿态全部确认
2. 角色入库（当前 Player.glb 在 /tmp/m1ref/BlockyChar_v5.glb，已复制到 Assets/Models/Characters/Player/）
3. 队友/敌人 = 玩家模型换色（未来）
4. 全部资产验收 → 转 M1.5（融入 M0 运动逻辑 + 武器逻辑，参考 feat/m1-weapon-system 分支）

## 五、关键技术坑（避免重犯）

1. **Blender 是 Z-up**：人物建模高度轴用 Z（脚底 z=0 头顶 z=1.75），我之前误用 Y 导致人物躺倒
2. **glTF 导入 Godot 朝向转换**：Blender -Y 前方 → Godot +Z 后方（需绕 Y 180°）
3. **武器 glTF 长轴 X**：枪口方向需几何验证（+X 端特征：细管+准星），绕 Y ±90° 对齐 -Z 前方
4. **Blender 脚本改 glTF 矩阵不可靠**（RootNode EMPTY 层级/apply 后失效）→ **用 Godot 节点 rotation 控制朝向**（可靠）
5. **Skeleton3D.set_bone_pose_rotation 需要 Quaternion**（非 Vector3 欧拉角）
6. **材质 Solid 模式显示**：需同时设 Principled BSDF + diffuse_color

## 六、环境

- 分支 feat/m1-assets，工作树 /Users/elanyi/Projects/Trigger-Echo-m1-assets
- Blender 5.2（/opt/homebrew/Caskroom/blender/5.2.0/Blender.app）
- Godot 4.7.1
- 查看器运行：`cd /Users/elanyi/Projects/Trigger-Echo-m1-assets && godot --path . Assets/Viewer/Viewer.tscn`
