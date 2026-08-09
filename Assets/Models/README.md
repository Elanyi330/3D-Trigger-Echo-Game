# Assets/Models 资产规范（M1 资产先行 → M1.5 定稿）

> 更新: 2026-08-09（多模态重建 + CS 对齐轮）
> 核心原则: **canonical 朝向 + 组件标记内置 + 型号特异命名 + 分类目录**，新武器零歧义接入。
> 📋 **逐组件精确坐标/骨骼/取景总表 → [COMPONENTS.md](COMPONENTS.md)**（新 AI 快速了解全仓库资产看这份）

---

## 一、目录组织（按类别/型号分类，彼此独立）

```
Assets/Models/
  Weapons/<类别>/<型号_Echo>/<型号_Echo>.glb     # 游戏资产（canonical，含标记+ECHO印记）
    Rifle/AK47_Echo/AK47_Echo.glb
    Pistol/Glock18_Echo/Glock18_Echo.glb
    Melee/Knife_Echo/Knife_Echo.glb
    Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb
  Characters/Soldier_Echo/Soldier_Echo.glb       # 角色（玩家/队友/敌人共用，仅换色）
tools/render/sources/                            # 原始下载件（构建输入，非游戏资产）
tools/render/*.py                                # 处理/构建脚本（可复现，已提交）
```

- **型号特异命名**：节点一律 `<型号>_Echo_<部件>`（如 `AK47_Echo_Muzzle`），未来新型号/新系列不冲突。
- **Echo 系列**：首批初始武器统一「回声/Echo」系列，本体带橙色 `ECHO` 印记（左侧面，玩家可见）。

## 二、canonical 朝向约定（钉死，勿再猜）

| Blender | → Godot | 含义 |
|---------|---------|------|
| **+Y**  | **−Z**  | **前方 / 枪口方向** |
| +Z      | +Y      | 上   |
| +X      | +X      | 右   |

- 枪口（近战刀尖）→ **−Z**（Godot 前向，= 相机前向）；角色面朝 **−Z**（眼睛/脚尖 −Z）。
- 每件武器 **原点 = GripRight（右手握把）**，视图模型挂接零偏移。
- 游戏资产为**真实尺寸**（×1.0）；视图模型缩放由 Godot 侧 `ViewModel.vm_scale` 控制。

## 三、组件标记（每件武器内置的命名 Marker3D，M1.5 动画/逻辑读取）

| 标记 | 含义 | 用途 |
|------|------|------|
| `_Muzzle` | 枪口尖 | 曳光/枪口火光起点；前向 = 出膛方向 |
| `_GripRight` | 右手握把 | 右手挂接（= 原点） |
| `_GripLeft` | 左手护木 | 左手挂接（双手武器） |
| `_Magazine` | 弹匣 | 换弹动画（弹匣脱/装） |
| `_Bolt` | 枪栓/滑套 | 换弹/上膛动画（活动部件） |
| `_EjectPort` | 抛壳口 | 弹壳抛出 |
| `_Sight` | 瞄具 | ADS 对齐 |
| `_PullRing` | 手雷拉环 | 投掷拉环动画 |
| `_Spoon` | 手雷握片 | 投掷握片动画 |
| `_Tip` / `_Guard` | 刀尖 / 护手 | 近战刺击点 / 护手 |

> 在 Godot 用 `ViewModel.find_marker(weapon, "_Muzzle")` 按后缀查找（型号无关）。

## 四、角色（Soldier_Echo）

- 方块风，高 1.78m，面朝 −Z；18 骨（含 `Hand_L`/`Hand_R` 挂武器）。
- 单一蒙皮网格 `Soldier_Echo_Body`（避免节点/骨骼同名冲突），顶点组单骨绑定（防折断/拉扯）。
- 换色：改材质 albedo（玩家绿/队友蓝/敌人红）。

## 五、如何新增一件武器（零歧义流程）

1. 把原始 .glb 放入 `tools/render/sources/<型号>.glb`。
2. 在 `tools/render/process_weapon.py` 的 `WEAPONS` 加一项配置：
   - `rot_z`（把枪口转到 +Y 的角度；用 `measure.py`/`inspect_asset.py` 渲染判读枪口朝向）
   - `real_len`、`grip_raw`、`markers`（canonical 坐标，先 `--bare` 出图量取）
   - `mark`（ECHO 印记位置/大小）
3. 跑 `--debug-spheres` 渲染校对标记 → 满意后正式导出。
4. 新建 `weapon_<型号>.tres`（数值唯一来源，参考 cs2-weapon-data.md）。

## 六、许可（全合规）

| 资产 | 来源 | 许可 |
|------|------|------|
| AK47_Echo | poly.pizza Quaternius | CC0 |
| Glock18_Echo | Quaternius Animated FPS Guns | CC0 |
| Grenade_M67_Echo | poly.pizza Pichuliru Frag West | CC0 1.0 |
| Knife_Echo | **自产**（build_knife.py，替代损坏的 CC-BY 下载件） | 自产 CC0 |
| Soldier_Echo | **自产**（build_character.py） | 自产 CC0 |

> 损坏弃用：Revolver（网格残缺）已移除；旧 Knife 下载件（缩放点状）由程序化自产替代。
