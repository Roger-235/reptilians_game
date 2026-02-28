## 掛在 Area2D 上，玩家進入後切換到指定鏡頭
extends Area2D

## 在 Inspector 填入目標 Camera2D 的節點名稱（字串）
@export var target_camera_name: String = ""

## 觸發方向：只有玩家速度與此方向同向才切換
## 下穿用 Vector2(0,1)，上穿用 Vector2(0,-1)，右穿用 Vector2(1,0)，左穿用 Vector2(-1,0)
## 留 Vector2.ZERO 則不限方向
@export var trigger_direction: Vector2 = Vector2.ZERO

const COOLDOWN = 0.4  # 切換後鎖定秒數，防止來回抖動
var _cooldown_timer: float = 0.0

func _physics_process(delta):
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		return

	for body in get_overlapping_bodies():
		if _try_switch(body):
			break

func _try_switch(body: Node2D) -> bool:
	if not body is CharacterBody2D:
		return false

	if trigger_direction != Vector2.ZERO:
		if body.velocity.dot(trigger_direction) <= 0:
			return false

	if target_camera_name == "":
		push_warning("[Portal] ", name, ": target_camera_name is empty!")
		return false

	var target_camera = get_parent().get_node_or_null(target_camera_name)
	if not target_camera:
		push_warning("[Portal] ", name, ": cannot find node '", target_camera_name, "'")
		return false

	# 已經在目標鏡頭就不重複切換
	if target_camera.enabled:
		return false

	for child in get_parent().get_children():
		if child is Camera2D:
			child.enabled = false

	target_camera.enabled = true
	_cooldown_timer = COOLDOWN
	return true
