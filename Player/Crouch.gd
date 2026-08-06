extends Node
## 下蹲组件（替代原 Sprint）——CS 风格下蹲
## 设计规格（2026-08-06 定稿）：
##   胶囊高 2.0m → 1.3m；相机全局 1.64m → 0.95m；移速 10 → 6 m/s（60%）
##   设计联动：未来矮掩体统一 1.4m —— 蹲下完全隐蔽，站立露头 0.24m
## 输入：sprint 动作（保留 FirstPersonStarter 输入名，语义改为下蹲）
## 几何（玩家 origin 在 y=0 处；胶囊底部固定 y=-1 贴地）：
##   站立：胶囊高 2.0 → Collision 节点 y=0（中心在 origin），Head 本地 y=0.64（相机全局 1.64）
##   下蹲：胶囊高 1.3 → Collision 节点 y=-0.35（中心 -0.35，底部仍 -1），Head 本地 y=-0.05（相机全局 0.95）

@export_node_path("MovementController") var controller_path := NodePath("../")
@onready var controller: MovementController = get_node(controller_path)

@export_node_path("Node3D") var head_path := NodePath("../Head")
@onready var head: Node3D = get_node(head_path)

# 站立 / 下蹲 参数（相对玩家 origin 的本地值；CS 数值 2026-08-06 照搬）
@export var stand_capsule_height := 1.83
@export var crouch_capsule_height := 1.37
@export var stand_capsule_center_y := 0.0        # 胶囊中心 = 玩家 origin（底部 -0.915）
@export var crouch_capsule_center_y := -0.23     # 底部固定 -0.915 → 中心 = -0.915+0.685 = -0.23
@export var stand_head_local_y := 0.715          # 相机全局 1.63（CS 眼位 64u）
@export var crouch_head_local_y := 0.255         # 相机全局 1.17（CS 下蹲眼位 46u）
@export var stand_speed := 6.35
@export var crouch_speed := 2.59

# 过渡速度（每秒插值系数）
@export var transition_speed := 8.0

# 胶囊碰撞节点（MovementController.tscn 默认位置 y=0）
@onready var capsule_node: CollisionShape3D = controller.get_node("Collision")
# 注意：MovementController.tscn 的 CapsuleShape3D 是 SubResource（多实例共享），
# 直接改 height 会影响所有玩家/测试。复制为实例私有 shape。
@onready var capsule_shape: CapsuleShape3D = capsule_node.shape.duplicate()

var is_crouching := false
var current_speed: float = stand_speed


func _ready() -> void:
	capsule_node.shape = capsule_shape


func _physics_process(delta: float) -> void:
	var target_crouch: bool = Input.is_action_pressed(&"sprint")
	is_crouching = target_crouch

	var t := clampf(transition_speed * delta, 0.0, 1.0)

	# 1. 胶囊缩放：高度 + 中心（底部固定 y=-1）
	var target_height: float = crouch_capsule_height if target_crouch else stand_capsule_height
	var target_center: float = crouch_capsule_center_y if target_crouch else stand_capsule_center_y
	capsule_shape.height = lerpf(capsule_shape.height, target_height, t)
	capsule_node.position.y = lerpf(capsule_node.position.y, target_center, t)

	# 2. 相机高度（Head 本地 y）
	var target_head_y: float = crouch_head_local_y if target_crouch else stand_head_local_y
	head.position.y = lerpf(head.position.y, target_head_y, t)

	# 3. 移速（用连续变量避免整数 round 粘滞；speed 已是 float 类型）
	var target_speed: float = crouch_speed if target_crouch else stand_speed
	current_speed = lerpf(current_speed, target_speed, t)
	controller.speed = current_speed
