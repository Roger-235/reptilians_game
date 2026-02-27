## 掛在 Area2D 上，玩家碰到就死亡
extends Area2D

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if body.has_method("_die"):
		body._die()
