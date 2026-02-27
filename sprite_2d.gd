extends CharacterBody2D

const SPEED = 200
const JUMP_VELOCITY = -300.0
const SWING_FORCE = 300.0   # 搖盪時方向鍵加速的力道
const ROPE_STIFFNESS = 900.0 # 繩子彈力係數（越大越硬）
const ROPE_DAMPING = 50.0    # 繩子阻尼係數（越大越快停止彈動）
const MOUTH_OFFSET = Vector2.ZERO  # 舌頭起點（原點）

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var anim = $AnimatedSprite2D

enum State { IDLE, START_RUN, RUN, JUMP, SWING, LAUNCH }
var state = State.IDLE

const COYOTE_FRAMES = 4
var off_floor_frames = 0

# 舌頭與繩索陣列
var tongue_anchor: Vector2 = Vector2.ZERO
var tongue_length: float = 0.0
var tongue_line: Line2D
var rope_points: Array[Vector2] = [] # 用來記錄所有轉折點的陣列
var rope_rids: Array[RID] = []      # 每個折點所在牆壁的 RID（用於排除射線）

func _ready():
	floor_snap_length = 8.0
	anim.sprite_frames.set_animation_loop("start_run", false)
	anim.animation_finished.connect(_on_animation_finished)

	# 建立舌頭的線段
	tongue_line = Line2D.new()
	tongue_line.width = 2.0
	tongue_line.default_color = Color(0.9, 0.2, 0.2)
	tongue_line.z_index = 10
	tongue_line.z_as_relative = false
	tongue_line.visible = false
	add_child(tongue_line)

func _on_animation_finished():
	if state == State.START_RUN:
		_set_state(State.RUN)

func _set_state(new_state: State):
	state = new_state
	match state:
		State.IDLE:
			anim.play("idle")
		State.START_RUN:
			anim.play("start_run")
		State.RUN:
			anim.play("run")
		State.JUMP, State.SWING, State.LAUNCH:
			if anim.sprite_frames.has_animation("jump"):
				anim.play("jump")

func _unhandled_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_shoot_tongue()
		else:
			_release_tongue()

func _shoot_tongue():
	var space_state = get_world_2d().direct_space_state
	var from = global_position
	var dir = (get_global_mouse_position() - from).normalized()
	var to = from + dir * 1000.0

	var query = PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [get_rid()]
	var result = space_state.intersect_ray(query)

	if result:
		tongue_anchor = result.position

		# 初始化繩索，把最終擊中點加入陣列
		rope_points.clear()
		rope_rids.clear()
		rope_points.append(tongue_anchor)
		rope_rids.append(result.collider.get_rid())

		tongue_length = global_position.distance_to(tongue_anchor)
		
		tongue_line.visible = true
		_set_state(State.SWING)

func _release_tongue():
	if state != State.SWING:
		return
	tongue_line.visible = false
	rope_points.clear()
	rope_rids.clear()
	_set_state(State.LAUNCH)  # 飛出去，暫時不能移動

func _physics_process(delta):
	# 這裡的 "ui_left" 和 "ui_right" 只要你在專案設定有綁定 A 和 D 就可以用
	var direction = Input.get_axis("ui_left", "ui_right")

	# 如果在搖盪狀態，把控制權交給搖盪函數，並跳過一般移動
	if state == State.SWING:
		_process_swing(delta, direction)
		return

	# 飛出狀態：只受重力，不能左右移動，落地後才恢復
	if state == State.LAUNCH:
		velocity.y += gravity * delta
		move_and_slide()
		if is_on_floor():
			if direction:
				_set_state(State.RUN)
			else:
				_set_state(State.IDLE)
		return

	# 1. 重力
	velocity.y += gravity * delta

	# 2. 跳躍
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# 3. 左右移動
	if direction:
		velocity.x = direction * SPEED
		anim.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# 4. 狀態機與土狼時間
	if is_on_floor():
		off_floor_frames = 0
	else:
		off_floor_frames += 1

	if off_floor_frames >= COYOTE_FRAMES:
		if state != State.JUMP:
			_set_state(State.JUMP)
	elif is_on_floor() and direction:
		if state == State.IDLE:
			_set_state(State.START_RUN)
		elif state == State.JUMP:
			_set_state(State.RUN)
	elif is_on_floor():
		if state in [State.RUN, State.START_RUN, State.JUMP]:
			_set_state(State.IDLE)

	move_and_slide()

# 動態折彎擺盪邏輯 
func _process_swing(delta: float, direction: float):
	if rope_points.is_empty():
		_release_tongue()
		return

	# 1. 處理重力與玩家方向鍵加速
	velocity.y += gravity * delta
	velocity.x += direction * SWING_FORCE * delta

	var space_state = get_world_2d().direct_space_state
	var current_anchor = rope_points.back()

	# 2. 檢查纏繞：碰撞點必須離當前錨點 > 8px 才算真正的新折點
	# （錨點本身就在牆面上，誤打到牆的距離幾乎為 0，真正繞過牆角才會有 8px+）
	var wrap_query = PhysicsRayQueryParameters2D.create(global_position, current_anchor)
	wrap_query.exclude = [get_rid()]
	var wrap_result = space_state.intersect_ray(wrap_query)

	if wrap_result and wrap_result.position.distance_to(current_anchor) > 8.0:
		rope_points.append(wrap_result.position + wrap_result.normal * 2.0)
		rope_rids.append(wrap_result.collider.get_rid())
		current_anchor = rope_points.back()

	# 3. 檢查解開：射線沒碰到東西，或只碰到 prev_anchor 本身的牆（距離 < 8px），就解開
	if rope_points.size() > 1:
		var prev_anchor = rope_points[rope_points.size() - 2]
		var unwrap_query = PhysicsRayQueryParameters2D.create(global_position, prev_anchor)
		unwrap_query.exclude = [get_rid()]
		var unwrap_result = space_state.intersect_ray(unwrap_query)

		if not unwrap_result or unwrap_result.position.distance_to(prev_anchor) < 8.0:
			# 視線無阻擋（或只打到 prev_anchor 的牆面），代表繞回去了
			rope_points.pop_back()
			rope_rids.pop_back()
			current_anchor = rope_points.back()

	# 4. 計算被牆壁吃掉的繩長，推算剩下可用的繩長
	var pinned_length = 0.0
	for i in range(rope_points.size() - 1):
		pinned_length += rope_points[i].distance_to(rope_points[i+1])
	var effective_length = max(tongue_length - pinned_length, 10.0) # 保底留 10px

	# 5. 彈性繩子約束：超出繩長時才施加彈簧力拉回，有伸縮感
	var to_player = global_position - current_anchor
	var dist = to_player.length()
	var rope_dir = to_player / max(dist, 0.01)

	if dist > effective_length:
		var stretch = dist - effective_length
		var radial_vel = velocity.dot(rope_dir)
		# 彈力（拉回錨點）+ 阻尼（減少反彈振動）
		velocity -= rope_dir * (stretch * ROPE_STIFFNESS + radial_vel * ROPE_DAMPING) * delta

	move_and_slide()

	# 6. 更新 Line2D 視覺
	tongue_line.clear_points()
	for p in rope_points:
		tongue_line.add_point(p - global_position)
	tongue_line.add_point(MOUTH_OFFSET) # 最後連回角色中心

	# 7. 碰到地板自動放開
	if is_on_floor():
		_release_tongue()
		if direction != 0:
			_set_state(State.RUN)
		else:
			_set_state(State.IDLE)
