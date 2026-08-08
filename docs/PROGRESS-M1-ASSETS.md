# M1 资产 + M1.5 集成 — 完成进度（2026-08-08 多模态重建）

> 分支: `feat/m1-assets`（工作树 ../Trigger-Echo-m1-assets）
> 本次会话: **用多模态能力（渲染亲眼验证）重建 M1 资产 + 完成 M1.5 集成**。
> 测试: **GUT 150/150 全绿**（M0 14 + 武器逻辑 + 集成）。

---

## 一、本次解决的核心问题（用户点名）

| 问题 | 根因（多模态诊断） | 解法 |
|------|------|------|
| **枪口朝向混乱** | 各武器朝向轴向不一致（AK/Glock=X，Revolver/Grenade=Z），无任何约定 | 建 **canonical 约定**（枪口=Blender+Y=Godot−Z），实验标定（cal_query 钉死），逐武器渲染验证 |
| **组件定义不清晰** | 枪口/握把/弹匣/枪栓全靠 Viewer 魔数硬猜 | **每武器内置命名标记**（Muzzle/GripRight/GripLeft/Magazine/Bolt/EjectPort/Sight/PullRing/Spoon/Tip），逻辑/动画按名读取 |
| **手-武器不协调** | 旧方案烘焙全身姿态，手臂根本没握枪 | **视图模型构造保证**：手臂端点直接取自 GripRight/GripLeft 标记，手永远精确握枪 |
| **角色 3D 问题** | v5/v7 手臂过短、杂散 Icosphere、网格/骨骼同名冲突 | **重建 Soldier_Echo**（合理比例、18 骨含 Hand_L/R、单蒙皮网格、单骨绑定，姿态测试无拉伸） |
| **损坏资产** | Revolver 剩薄片、Knife 缩成点 | Revolver 移除（与 Glock 重复）；Knife **程序化自产重建**（方块风统一） |

## 二、交付清单

**M1（资产）**：
- 4 件 Echo 系列武器（canonical 朝向 + 组件标记 + 橙色 ECHO 印记）：AK47_Echo / Glock18_Echo / Knife_Echo / Grenade_M67_Echo
- 角色 Soldier_Echo（重建，方块风，可换色，含手部骨骼）
- 资产规范 `Assets/Models/README.md`（分类目录/命名/朝向/标记/新增流程/许可）
- 可复现管线脚本（提交入 tools/render/）：process_weapon / build_knife / build_character / measure / inspect_asset
- 查看器 Viewer（角色+武器转台 + 枪口射线可视化）

**M1.5（集成）**：
- 移植旧 M1 验证过的武器逻辑：WeaponCore(hitscan/后坐力/换弹) / WeaponManager(4槽状态机/投掷/近战/ADS) / Weapon_Resource + 4 .tres(CS2数值) / Melee/Grenade/Tracer/BulletHole 等
- 新表现层 **WeaponView**（ViewModel + 程序化动画 kickback/sway/bob/reload/swing/throw + 枪口火光@Muzzle 标记），替代旧 WeaponAnchor（FpsRig 崩坏路径）
- M0 Player 增强：Head(add_recoil/set_ads) + MovementController(speed_modifier/is_moving/is_crouching) + Crouch 联动 + 输入动作(fire/reload/aim/weapon_1-4/next_weapon)
- L_Main 主场景：代码装配武器系统 + HUD(弹药/准星/命中标记) + 训练靶（TargetA + 6 红色敌人）
- Enemy（干净版：Soldier_Echo 换红 + 躯干/头部 hitbox 爆头 + 血条 + 倒地淡出）

## 三、验证证据

- GUT **150/150**（17 脚本 / 711 断言）
- 多模态渲染验证：武器标记落位 / 角色姿态 / 视图模型协调 / 实际游戏画面（HUD+敌人+视图模型）

## 四、操作说明（验收）

`godot --path . Levels/Main/L_Main.tscn`（或直接打开 Godot 运行）
- WASD 移动 / 空格跳 / Shift 蹲 / 鼠标视角
- 左键开火 / R 换弹 / 右键机瞄(枪)或重刺(刀) / 1-4 或滚轮切枪
- 靶场：金色 TargetA + 红色敌人（爆头 ×4）

## 五、遗留 / 后续

- MP5/M870/AWP 等其余型号 = M5（管线已就绪，加配置即可）
- 队友/敌人 AI 持武器姿态 = M3（角色手骨已备）
- 手感微调 = M2 地图后（用户既定决策）
