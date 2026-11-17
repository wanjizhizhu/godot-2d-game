
extends Node2D

# 准星移动速度
@export var move_speed: float = 420.0

# 准星摇晃幅度
@export var wobble_amplitude: float = 7.0

# 准星摇晃频率
@export var wobble_frequency: float = 6.0

# 玩家希望瞄准的位置
var aim_position: Vector2

# 摇晃计时器
var wobble_time: float = 0.0

var shooting_enabled: bool = false

# 开枪信号
signal shot_fired(shot_position: Vector2)


func _ready() -> void:
	# 初始位置设为屏幕中央
	aim_position = get_viewport_rect().size / 2.0

	global_position = aim_position
	visible = false

# 每帧更新准星
func _process(delta: float) -> void:

	if not shooting_enabled:
		return
	
	var direction = Vector2.ZERO

	# WASD控制准星移动
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0

	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0

	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0

	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0

	# 防止斜向移动速度更快
	if direction.length() > 0:
		direction = direction.normalized()

	# 更新瞄准位置
	aim_position += direction * move_speed * delta

	# 限制准星不要跑出屏幕
	var screen_size = get_viewport_rect().size

	aim_position.x = clampf(aim_position.x, 25.0, screen_size.x - 25.0)
	aim_position.y = clampf(aim_position.y, 25.0, screen_size.y - 25.0)

	# 更新摇晃时间
	wobble_time += delta

	# 计算准星摇晃
	var wobble = Vector2(
		sin(wobble_time * wobble_frequency),
		cos(wobble_time * wobble_frequency * 1.37) * 0.65
	) * wobble_amplitude

	# 最终显示位置
	global_position = aim_position + wobble


# 绘制准星
func _draw() -> void:

	var black = Color(0, 0, 0, 0.85)
	var white = Color(1, 1, 1, 0.95)

	# 外圈
	draw_arc(
		Vector2.ZERO,
		9.0,
		0.0,
		TAU,
		32,
		black,
		4.0,
		true
	)

	draw_arc(
		Vector2.ZERO,
		9.0,
		0.0,
		TAU,
		32,
		white,
		1.5,
		true
	)

	# 左侧
	draw_line(Vector2(-20, 0), Vector2(-11, 0), black, 4.0)
	draw_line(Vector2(-20, 0), Vector2(-11, 0), white, 2.0)

	# 右侧
	draw_line(Vector2(11, 0), Vector2(20, 0), black, 4.0)
	draw_line(Vector2(11, 0), Vector2(20, 0), white, 2.0)

	# 上侧
	draw_line(Vector2(0, -20), Vector2(0, -11), black, 4.0)
	draw_line(Vector2(0, -20), Vector2(0, -11), white, 2.0)

	# 下侧
	draw_line(Vector2(0, 11), Vector2(0, 20), black, 4.0)
	draw_line(Vector2(0, 11), Vector2(0, 20), white, 2.0)

	# 中心点
	draw_circle(Vector2.ZERO, 2.5, black)
	draw_circle(Vector2.ZERO, 1.0, white)


# 开枪输入
func _unhandled_input(event: InputEvent) -> void:
	if not shooting_enabled:
		return
	# Enter开枪
	if event is InputEventKey and event.pressed and not event.echo:

		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			shot_fired.emit(global_position)
			print("开枪位置：", global_position)

	# 鼠标左键开枪
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			shot_fired.emit(global_position)
			print("开枪位置：", global_position)

# 开启或关闭准星
func set_active(active: bool) -> void:

	shooting_enabled = active
	visible = active
