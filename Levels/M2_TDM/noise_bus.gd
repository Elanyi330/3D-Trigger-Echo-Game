# Levels/M2_TDM/noise_bus.gd
# M3.2 T7（2026-08-17）：NoiseBus 噪音事件总线（L_M2 预留装配点）——纯信号中继，
# 把声源事件广播给订阅方（敌 bot 感知订阅后经 _push_noise_event 注入，source
# =声源阵营）。本任务只建节点与信号，**不装配 L_M2**——接线由 M3.3 L_M2 装配
# 任务执行，接线契约如下：
#   枪声：玩家武器 core 的 shot_fired(ammo) → noise_event("gunshot", 玩家位置,
#         res.noise_radius)——res.noise_radius == 0 的静默武器不接线；
#         bot 枪声 M3.4 接入同源。
#   爆炸：Grenade.exploded(center) → noise_event("explosion", center,
#         m67.noise_radius=50)——扔出无声、炸响另行接线（M3.3）。
#   脚步：FootstepEmitter.footstep(pos, radius) → noise_event("footstep", pos, radius)。
# 感知/决策分离铁律：总线只转发事件，不持有感知引用、不决策。
class_name NoiseBus
extends Node

signal noise_event(kind: String, pos: Vector3, radius: float)   # 噪音事件广播（M3.3 感知订阅）
