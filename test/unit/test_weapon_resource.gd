# test/unit/test_weapon_resource.gd
# M1 任务0：Weapon_Resource 资源骨架测试（TDD RED 先行）
# 数值对齐 CS2（2026-03-18 补丁，见 docs/superpowers/reference/cs2-weapon-data.md）
# 唯一数值来源：Weapons/weapon_*.tres（禁止在代码中硬编码散值，企划书 §4.2.5）
extends GutTest

var ak: WeaponResource
var glock: WeaponResource
var knife: WeaponResource
var m67: WeaponResource

func before_each() -> void:
    ak = load("res://Weapons/weapon_ak47.tres")
    glock = load("res://Weapons/weapon_glock18.tres")
    knife = load("res://Weapons/weapon_knife.tres")
    m67 = load("res://Weapons/weapon_m67.tres")

# ---- 4 个 .tres 全部加载成功（加载失败报错） ----
func test_four_tres_all_load() -> void:
    assert_not_null(ak, "AK-47 .tres 加载成功")
    assert_not_null(glock, "Glock-18 .tres 加载成功")
    assert_not_null(knife, "战术匕首 .tres 加载成功")
    assert_not_null(m67, "M67 .tres 加载成功")

# ---- AK-47「铁幕」（CS2：36 / ×4.0 / 600RPM / 30+120 / 2.4s / 215u） ----
func test_ak47_cs2_values() -> void:
    assert_eq(ak.weapon_name, "AK47【回声】", "名称")
    assert_almost_eq(ak.damage, 36.0, 0.001, "伤害 36")
    assert_almost_eq(ak.headshot_multiplier, 4.0, 0.001, "爆头 ×4.0")
    assert_almost_eq(ak.limb_multiplier, 0.8, 0.001, "四肢 ×0.8")
    assert_eq(ak.rpm, 600, "600 RPM")
    assert_eq(ak.magazine, 30, "弹匣 30")
    assert_eq(ak.max_ammo, 120, "备弹 120")
    assert_almost_eq(ak.reload_time, 2.4, 0.001, "换弹 2.4s")
    assert_almost_eq(ak.effective_range, 40.0, 0.001, "满伤段 40m")
    assert_almost_eq(ak.max_range, 60.0, 0.001, "最大射程 60m")
    assert_eq(ak.falloff_curve.size(), 3, "衰减曲线 3 段")
    assert_almost_eq(ak.falloff_curve[0], 1.0, 0.001, "40m 内 = 1.0")
    assert_almost_eq(ak.falloff_curve[1], 0.98, 0.001, "50m = 0.98")
    assert_almost_eq(ak.falloff_curve[2], 0.96, 0.001, "60m = 0.96")
    assert_almost_eq(ak.mobility, 215.0, 0.001, "移速 215u (86%)")
    assert_eq(ak.fire_mode, WeaponResource.FireMode.FULL_AUTO, "全自动")
    assert_eq(ak.recoil_pattern, WeaponResource.RecoilPattern.SET_PATTERN, "固定弹道")
    assert_true(ak.pattern_offsets.size() >= 5, "Set Pattern 逐发数组 >= 5")
    assert_almost_eq(ak.pattern_offsets[0].x, 0.0, 0.001, "首发 0 偏移")
    assert_almost_eq(ak.pattern_offsets[1].x, 0.9, 0.001, "第 2 发 +0.9°")
    assert_almost_eq(ak.pattern_offsets[2].x, 1.8, 0.001, "第 3 发 +1.8°")
    assert_almost_eq(ak.recovery_speed, 8.0, 0.001, "恢复 8°/s")
    assert_almost_eq(ak.first_shot_spread, 0.1, 0.001, "首发散布 0.1°")
    assert_almost_eq(ak.ads_multiplier, 1.5, 0.001, "机瞄 ×1.5")
    assert_almost_eq(ak.move_spread_multiplier, 3.0, 0.001, "移动散布惩罚 ×3.0（CS2 running inaccuracy）")
    assert_almost_eq(ak.crouch_spread_multiplier, 0.7, 0.001, "下蹲散布收窄 ×0.7")

# ---- Glock-18「迅捷」（CS2：30 / 400RPM / 20+80 / 2.3s / 240u / 半自动随机） ----
func test_glock18_cs2_values() -> void:
    assert_eq(glock.weapon_name, "Glock18【回声】", "名称")
    assert_almost_eq(glock.damage, 30.0, 0.001, "伤害 30")
    assert_almost_eq(glock.headshot_multiplier, 4.0, 0.001, "爆头 ×4.0")
    assert_eq(glock.rpm, 400, "400 RPM")
    assert_eq(glock.magazine, 20, "弹匣 20")
    assert_eq(glock.max_ammo, 80, "备弹 80")
    assert_almost_eq(glock.reload_time, 2.3, 0.001, "换弹 2.3s")
    assert_almost_eq(glock.effective_range, 15.0, 0.001, "满伤段 15m")
    assert_almost_eq(glock.max_range, 30.0, 0.001, "最大射程 30m")
    assert_almost_eq(glock.falloff_curve[1], 0.9, 0.001, "中段衰减 0.9")
    assert_almost_eq(glock.falloff_curve[2], 0.85, 0.001, "末段衰减 0.85")
    assert_almost_eq(glock.mobility, 240.0, 0.001, "移速 240u (96%)")
    assert_eq(glock.fire_mode, WeaponResource.FireMode.SEMI_AUTO, "半自动")
    assert_eq(glock.recoil_pattern, WeaponResource.RecoilPattern.RANDOM, "随机后坐力")
    assert_almost_eq(glock.recoil_amount, 0.5, 0.001, "随机基准 0.5°")
    assert_almost_eq(glock.recoil_variance, 0.3, 0.001, "随机方差 0.3°")
    assert_almost_eq(glock.recovery_speed, 14.0, 0.001, "恢复 14°/s")
    assert_almost_eq(glock.first_shot_spread, 0.15, 0.001, "首发散布 0.15°")
    assert_almost_eq(glock.ads_multiplier, 1.0, 0.001, "无开镜")
    assert_almost_eq(glock.move_spread_multiplier, 1.5, 0.001, "移动散布惩罚 ×1.5（手枪移动惩罚小）")
    assert_almost_eq(glock.crouch_spread_multiplier, 0.7, 0.001, "下蹲散布收窄 ×0.7")

# ---- 战术匕首「回声」（CS2：40/25/65/背刺180/0.4s+1.0s/250u） ----
func test_knife_melee_values() -> void:
    assert_eq(knife.weapon_name, "战术匕首【回声】", "名称")
    assert_eq(knife.fire_mode, WeaponResource.FireMode.MELEE, "近战")
    assert_almost_eq(knife.mobility, 250.0, 0.001, "移速 250u (100%)")
    assert_almost_eq(knife.damage, 40.0, 0.001, "基础伤害 40（正面首击）")
    assert_eq(knife.rpm, 0, "近战无视 RPM")
    assert_eq(knife.magazine, 0, "无弹匣")
    assert_eq(knife.max_ammo, 0, "无备弹")
    assert_almost_eq(knife.reload_time, 0.0, 0.001, "无需换弹")
    assert_almost_eq(knife.ads_multiplier, 1.0, 0.001, "无开镜")
    assert_almost_eq(knife.melee_primary_damage, 40.0, 0.001, "首击 40")
    assert_almost_eq(knife.melee_secondary_damage, 25.0, 0.001, "连击 25")
    assert_almost_eq(knife.melee_stab_damage, 65.0, 0.001, "重刺 65")
    assert_almost_eq(knife.melee_backstab_damage, 180.0, 0.001, "背刺 180（秒杀）")
    assert_almost_eq(knife.melee_light_time, 0.4, 0.001, "轻击间隔 0.4s")
    assert_almost_eq(knife.melee_heavy_time, 1.0, 0.001, "重击间隔 1.0s")
    assert_almost_eq(knife.melee_range, 1.5, 0.001, "攻击距离 1.5m")
    assert_almost_eq(knife.melee_angle, 60.0, 0.001, "攻击扇形 60°")
    assert_almost_eq(knife.melee_backstab_angle, 150.0, 0.001, "背刺判定角 150°")
    assert_true(knife.melee_range > 0.0, "攻击距离 > 0")
    assert_true(knife.melee_angle > 0.0, "攻击角度 > 0")

# ---- M67「轰鸣」（CS2：98 / 引信1.5s / 半径6m / 245u） ----
func test_m67_throwable_values() -> void:
    assert_eq(m67.weapon_name, "M67【回声】", "名称")
    assert_eq(m67.fire_mode, WeaponResource.FireMode.THROWABLE, "投掷物")
    assert_almost_eq(m67.damage, 98.0, 0.001, "中心伤害 98")
    assert_almost_eq(m67.fuse_time, 1.5, 0.001, "引信 1.5s")
    assert_almost_eq(m67.blast_radius, 6.0, 0.001, "爆炸半径 6m")
    assert_eq(m67.magazine, 1, "携带 1 枚")
    assert_eq(m67.max_ammo, 1, "备弹 1 枚")
    assert_eq(m67.rpm, 0, "投掷物无视 RPM")
    assert_almost_eq(m67.reload_time, 0.0, 0.001, "无需换弹")
    assert_almost_eq(m67.mobility, 245.0, 0.001, "移速 245u (98%)")
    assert_almost_eq(m67.ads_multiplier, 1.0, 0.001, "右键 = 取消投掷")

# ---- 默认值校验（资源字段缺省时回落默认，测试引用常量而非散值） ----
func test_defaults_on_fresh_resource() -> void:
    var fresh := WeaponResource.new()
    assert_almost_eq(fresh.headshot_multiplier, 4.0, 0.001, "默认爆头 ×4.0")
    assert_almost_eq(fresh.limb_multiplier, 0.8, 0.001, "默认四肢 ×0.8")
    assert_almost_eq(fresh.mobility, 250.0, 0.001, "默认移速 250u")
    assert_eq(fresh.fire_mode, WeaponResource.FireMode.FULL_AUTO, "默认全自动")
    assert_eq(fresh.recoil_pattern, WeaponResource.RecoilPattern.SET_PATTERN, "默认固定弹道")
    assert_almost_eq(fresh.ads_multiplier, 1.0, 0.001, "默认无开镜")
    assert_almost_eq(fresh.fuse_time, 0.0, 0.001, "默认无引信")
    assert_almost_eq(fresh.blast_radius, 0.0, 0.001, "默认无爆炸")
    assert_almost_eq(fresh.move_spread_multiplier, 1.0, 0.001, "默认无移动惩罚（中性）")
    assert_almost_eq(fresh.crouch_spread_multiplier, 1.0, 0.001, "默认无下蹲修正（中性）")
    assert_eq(fresh.attachments.size(), 0, "默认无配件")
    assert_is(fresh, WeaponResource, "类型校验：WeaponResource 实例")
