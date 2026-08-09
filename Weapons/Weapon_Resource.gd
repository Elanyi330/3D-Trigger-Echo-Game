# Weapons/Weapon_Resource.gd
# M1 武器数据资源（纯数据，参考 FPS-Template weapon_resource.gd 的资源驱动风格）
#
# 铁律（企划书 §4.2.5）：武器数值唯一来源 Weapons/weapon_*.tres，禁止在代码中硬编码散值。
# 数值对齐 CS2（2026-03-18 补丁，见 docs/superpowers/reference/cs2-weapon-data.md）。
class_name WeaponResource
extends Resource

enum FireMode { FULL_AUTO, SEMI_AUTO, MELEE, THROWABLE }
enum RecoilPattern { SET_PATTERN, RANDOM }

@export var weapon_name: String
@export var damage: float
@export var headshot_multiplier: float = 4.0
@export var limb_multiplier: float = 0.8
@export var rpm: int
@export var magazine: int
@export var max_ammo: int
@export var reload_time: float
@export var effective_range: float
@export var max_range: float
@export var falloff_curve: PackedFloat32Array  # [满伤段=1.0, 中段, 末段]，按距离线性插值
@export var mobility: float = 250.0
@export var deploy_time: float = 0.3  # 切枪部署延迟（s）：AK/Glock/刀 0.3s、M67 0.5s（参数化，brief §行为要求）
@export var fire_mode: FireMode = FireMode.FULL_AUTO
@export var recoil_pattern: RecoilPattern = RecoilPattern.SET_PATTERN
@export var pattern_offsets: PackedVector2Array  # Set Pattern 逐发偏移（度）
@export var recoil_amount: float  # Random 基准偏移
@export var recoil_variance: float
@export var recovery_speed: float  # °/s
# M1 任务15：相机后坐力（Jeh3no 双层 lerp，rad/发）：x = 上抬、y/z = 随机抖动幅度。
# AK (0.06, 0.02, 0.02) / Glock (0.04, 0.015, 0.015)（.tres 参数化）；近战/投掷默认 ZERO。
@export var recoil_val: Vector3 = Vector3.ZERO
@export var first_shot_spread: float  # 首发散布角（度）
@export var move_spread_multiplier: float = 1.0  # 移动散布惩罚（AK 3.0 / Glock 1.5，.tres 参数化；CS2 running inaccuracy 182 vs 7）
@export var crouch_spread_multiplier: float = 1.0  # 下蹲散布收窄（AK/Glock 0.7，.tres 参数化；CS2 crouch tighter）
@export var ads_multiplier: float = 1.0  # 开镜倍率（1.0 = 无开镜；FOV/灵敏度缩放）
# M1.5：开镜散布收窄倍率（开镜 vs 腰射准度差异，参考 CS 开镜显著更准——AUG/SG 开镜散布约减半）。
# 作用于全部射击（首发 + 连射弹道偏移）；<1 越低开镜越准。1.0 = 无差异。
@export var ads_spread_multiplier: float = 0.5
@export var fuse_time: float = 0.0  # 投掷物引信（M67 用）
@export var blast_radius: float = 0.0  # 爆炸半径（M67 用）
@export var blast_falloff: PackedFloat32Array = []  # 爆炸距离衰减表（绝对伤害值，按 blast_radius 等距分带；M67 [98, 60, 30]，CS2 HE；首段须与 damage 一致，测试锁定）
@export var attachments: Array = []  # 配件槽位（预留，M1 默认空）

# ---- 近战附加字段（战术匕首「回声」，CS2：40/25/65/背刺180/0.4s+1.0s/250u） ----
@export var melee_primary_damage: float = 0.0  # 轻击/左键斜挥·首挥（CS2 40）
@export var melee_secondary_damage: float = 0.0  # 连击/后续斜挥（CS2 25——首挥 40、连击窗口内后续 25，奖励节奏惩罚连点）
@export var melee_stab_damage: float = 0.0  # 重击/右键前刺（CS2 65）
@export var melee_backstab_damage: float = 0.0  # 背刺（CS2 180 秒杀）
@export var melee_light_time: float = 0.0  # 轻击间隔（CS2 0.4s）
@export var melee_heavy_time: float = 0.0  # 重击间隔（CS2 1.0s）
@export var melee_range: float = 0.0  # 攻击距离（m，水平面触及——等效 CS 刀眼位视线触及；2.0 ≈ CS 有效触达）
@export var melee_angle: float = 0.0  # 攻击判定扇形角度（度，M1 近似，可调）
@export var melee_backstab_angle: float = 150.0  # 背刺判定角（度：目标朝向与攻击者方向夹角 > 此值 = 背刺）
# M1.5：命中延迟（s）——伤害延迟到挥击动画的"接触帧"才结算（修复"重刺秒出伤"：重击以蓄力换高伤）。
# 取值对齐 WeaponView 挥击包络的接触时刻：轻击斜挥 ~0.35 相位 ×0.4s≈0.15s；重刺前刺满伸 ~0.45 相位 ×1.0s≈0.45s。
@export var melee_light_hit_delay: float = 0.15  # 轻击接触延迟（CS 左键近乎即时）
@export var melee_heavy_hit_delay: float = 0.45  # 重刺接触延迟（CS 右键明显蓄力后出伤）
