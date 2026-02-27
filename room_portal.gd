## 掛在 Area2D 上，玩家進入後切換到指定鏡頭
extends Area2D

## 在 Inspector 填入目標 Camera2D 的節點名稱（字串）
@export var target_camera_name: String = ""

## 觸發方向：只有玩家速度與此方向同向才切換
## 下穿用 Vector2(0,1)，上穿用 Vector2(0,-1)，右穿用 Vector2(1,0)，左穿用 Vector2(-1,0)
## 留 Vector2.ZERO 則不限方向
@export var trigger_direction: Vector2 = Vector2.ZERO

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if not body is CharacterBody2D:
		return

	if trigger_direction != Vector2.ZERO:
		if body.velocity.dot(trigger_direction) <= 0:
			return

	if target_camera_name == "":
		push_warning("[Portal] ", name, ": target_camera_name is empty!")
		return

	var target_camera = get_parent().get_node_or_null(target_camera_name)
	if not target_camera:
		push_warning("[Portal] ", name, ": cannot find node '", target_camera_name, "'")
		return

	for child in get_parent().get_children():
		if child is Camera2D:
			child.enabled = false

	target_camera.enabled = true
