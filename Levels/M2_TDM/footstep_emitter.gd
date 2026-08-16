# Levels/M2_TDM/footstep_emitter.gd
# M3.2 T7（2026-08-17）：FootstepEmitter 脚步噪音发射器——按水平行进距离每满
# STRIDE（2.5m）发一次 footstep(pos, radius) 事件，供敌对 AI 听觉感知消费
# （经 NoiseBus 注入 BotPerception，M3.3 装配）。
# 半径分级：当前水平速度 ≤ CROUCH_SPEED_MAX（3.0 m/s，crouch_speed 2.59 上方）
# → CROUCH_RADIUS（5m，蹲行静步）；否则 RUN_RADIUS（20m，跑动）。
# 累计口径：仅宿主 on_floor 且水平速度 > 0.5 m/s 时累计行进距离（速度×delta）；
# 空中/静止不累计，落地/变速不清零（只在有前进时累计）。
# 零运行装配（同 BotPerception 口径）：本节点由装配方（M3.3 Brain / L_M2）驱动
# tick——未装配即零运行，宿主 _physics_process 每帧调用一次（60Hz tick 铁律）。
# M3.6 注记：RUN_RADIUS/CROUCH_RADIUS 计划参数化迁移 .tres。
class_name FootstepEmitter
extends Node

signal footstep(pos: Vector3, noise_radius: float)   # 脚步事件（敌对 bot 感知消费）

const STRIDE := 2.5          # m：每走 2.5m 发一次事件
const RUN_RADIUS := 20.0     # m：跑动噪音半径（M3.6 参数化 .tres 迁移注记）
const CROUCH_RADIUS := 5.0   # m：蹲行噪音半径
const CROUCH_SPEED_MAX := 3.0  # m/s：≤ 此值视为蹲行（crouch_speed 2.59 上方）
const MIN_STEP_SPEED := 0.5  # m/s：水平速度 > 此值才累计（静止/微动不发声）

var body: CharacterBody3D

var _accum := 0.0   # 当前步幅周期累计行进距离（m）


func setup(b: CharacterBody3D) -> void:
	body = b


## 每物理帧调用（宿主 _physics_process 驱动，60Hz）；按行进距离累计，每满
## STRIDE 发一次 footstep（半径按当前速度分级）。
func tick(delta: float) -> void:
	if body == null or not body.is_on_floor():
		return
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if speed <= MIN_STEP_SPEED:
		return
	_accum += speed * delta
	while _accum >= STRIDE:
		_accum -= STRIDE
		footstep.emit(body.global_position,
				CROUCH_RADIUS if speed <= CROUCH_SPEED_MAX else RUN_RADIUS)
