
extends Control

# 判定结果
enum Result {
	DODGED,
	BODY_HIT,
	HEAD_HIT
}

signal judged(result: int)
signal sequence_finished

# 判定条基础参数
@export var base_marker_speed: float = 360.0
@export var speed_per_gun_skill: float = 65.0

# 判定区域
@export var green_base_width: float = 85.0
@export var green_reduction: float = 7.0

@export var yellow_base_width: float = 195.0
@export var yellow_increase: float = 5.0

# 普通敌人攻击间隔
@export var normal_gap_min: float = 0.2
@export var normal_gap_max: float = 0.65

# Boss攻击间隔
@export var boss_gap_min: float = 0.08
@export var boss_gap_max: float = 0.95

# Boss速度变化倍率
@export var boss_speed_min_multiplier: float = 0.8
@export var boss_speed_max_multiplier: float = 1.5

# Boss安全区域缩小倍率
@export var boss_green_width_multiplier: float = 0.65

# 当前状态
var is_active: bool = false
var sequence_active: bool = false
var marker_waiting: bool = false

var marker_x: float = 0.0
var marker_speed: float = 360.0

var green_half_width: float = 85.0
var yellow_half_width: float = 195.0

var bar_left: float = 32.0
var bar_right: float = 0.0

# 连续攻击数据
var sequence_gun_skill: float = 1.0
var sequence_is_boss: bool = false

var sequence_total: int = 0
var sequence_index: int = 0

var normal_sequence_speed: float = 360.0

# 攻击间隔计时器
var gap_timer: Timer


func _ready() -> void:

	anchor_left = 0.1
	anchor_right = 0.9
	anchor_top = 0.5
	anchor_bottom = 0.5

	offset_top = -65.0
	offset_bottom = 65.0

	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	gap_timer = Timer.new()
	gap_timer.one_shot = true
	add_child(gap_timer)

	gap_timer.timeout.connect(_on_gap_timeout)

	set_process(false)


# 兼容原来的单次判定接口
func start_judgement(gun_skill: float) -> void:

	start_sequence(gun_skill, false, 1)


# 开始连续判定
func start_sequence(
	gun_skill: float,
	is_boss: bool = false,
	hit_count: int = 3
) -> void:

	if sequence_active:
		return

	if hit_count <= 0:
		return

	sequence_gun_skill = maxf(gun_skill, 1.0)
	sequence_is_boss = is_boss

	sequence_total = hit_count
	sequence_index = 0

	normal_sequence_speed = _calculate_marker_speed(
		sequence_gun_skill
	)

	bar_right = size.x - bar_left

	sequence_active = true
	is_active = false
	marker_waiting = false

	visible = true
	set_process(true)

	_start_next_judgement()


# 计算普通敌人的判定线速度
func _calculate_marker_speed(skill: float) -> float:

	return clampf(
		base_marker_speed
		+ (skill - 1.0) * speed_per_gun_skill,
		360.0,
		1200.0
	)


# 开始下一次判定
func _start_next_judgement() -> void:

	if not sequence_active:
		return

	# 所有攻击完成
	if sequence_index >= sequence_total:
		_finish_sequence()
		return

	# 第一发立即开始，后续攻击先等待
	if sequence_index > 0:

		marker_waiting = true

		var gap = _get_attack_gap()

		gap_timer.start(gap)

		queue_redraw()

		return

	_begin_single_judgement()


# 获取攻击间隔
func _get_attack_gap() -> float:

	if sequence_is_boss:

		return randf_range(
			boss_gap_min,
			boss_gap_max
		)

	return randf_range(
		normal_gap_min,
		normal_gap_max
	)


# 间隔结束
func _on_gap_timeout() -> void:

	if not sequence_active:
		return

	marker_waiting = false

	_begin_single_judgement()


# 开始单次判定
func _begin_single_judgement() -> void:

	bar_right = size.x - bar_left

	# 普通敌人保持速度不变
	if not sequence_is_boss:

		marker_speed = normal_sequence_speed

	# Boss每一发都可能改变速度
	else:

		marker_speed = clampf(
			normal_sequence_speed
			* randf_range(
				boss_speed_min_multiplier,
				boss_speed_max_multiplier
			),
			420.0,
			1600.0
		)

	# 计算绿色区域
	green_half_width = clampf(
		green_base_width
		- (sequence_gun_skill - 1.0) * green_reduction,
		20.0,
		green_base_width
	)

	# Boss安全区域更窄
	if sequence_is_boss:

		green_half_width *= boss_green_width_multiplier

		green_half_width = maxf(
			green_half_width,
			12.0
		)

	# 计算黄色区域
	var max_yellow = maxf(
		green_half_width + 30.0,
		size.x * 0.46
	)

	yellow_half_width = clampf(
		yellow_base_width
		+ (sequence_gun_skill - 1.0) * yellow_increase,
		green_half_width + 30.0,
		max_yellow
	)

	# 判定线从右侧重新出发
	marker_x = bar_right

	is_active = true

	queue_redraw()


# 每帧移动判定线
func _process(delta: float) -> void:

	if not is_active:
		return

	marker_x -= marker_speed * delta

	# 到达最左侧，判定为爆头
	if marker_x <= bar_left:

		_finish_judgement(Result.HEAD_HIT)

		return

	queue_redraw()


# 玩家输入
func _input(event: InputEvent) -> void:

	if not (event is InputEventKey):
		return

	var key_event = event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return

	# 临时测试：F启动三连判定
	if key_event.keycode == KEY_F:

		if not sequence_active:
			start_sequence(1.0, false, 3)

		get_viewport().set_input_as_handled()

		return

	# Enter确认
	if key_event.keycode == KEY_ENTER \
	or key_event.keycode == KEY_KP_ENTER:

		if sequence_active:

			if is_active:
				_judge_position()

			get_viewport().set_input_as_handled()


# 鼠标判定
func _gui_input(event: InputEvent) -> void:

	if not is_active:
		return

	if event is InputEventMouseButton:

		if event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT:

			_judge_position()
			accept_event()


# 判断当前位置
func _judge_position() -> void:

	var center_x = size.x * 0.5
	var distance = absf(marker_x - center_x)

	if distance <= green_half_width:

		_finish_judgement(Result.DODGED)

	elif distance <= yellow_half_width:

		_finish_judgement(Result.BODY_HIT)

	else:

		_finish_judgement(Result.HEAD_HIT)


# 完成单次判定
func _finish_judgement(result: int) -> void:

	if not is_active:
		return

	is_active = false

	print(
		"第",
		sequence_index + 1,
		"发判定：",
		Result.keys()[result]
	)

	judged.emit(result)

	sequence_index += 1

	queue_redraw()

	# 自动准备下一发
	_start_next_judgement()


# 完成整个连续攻击
func _finish_sequence() -> void:

	if not sequence_active:
		return

	sequence_active = false
	is_active = false
	marker_waiting = false

	gap_timer.stop()

	visible = false
	set_process(false)

	queue_redraw()

	print("连续攻击结束！")

	sequence_finished.emit()


# 绘制判定条
func _draw() -> void:

	var center_x = size.x * 0.5
	var bar_y = 42.0
	var bar_height = 26.0

	var green_left = center_x - green_half_width
	var green_right = center_x + green_half_width

	var yellow_left = center_x - yellow_half_width
	var yellow_right = center_x + yellow_half_width

	# 背景
	draw_rect(
		Rect2(
			bar_left,
			bar_y - 7,
			bar_right - bar_left,
			bar_height + 14
		),
		Color(0.08, 0.08, 0.08, 0.95)
	)

	# 左侧红色
	draw_rect(
		Rect2(
			bar_left,
			bar_y,
			maxf(yellow_left - bar_left, 0.0),
			bar_height
		),
		Color(0.82, 0.19, 0.19)
	)

	# 左侧黄色
	draw_rect(
		Rect2(
			yellow_left,
			bar_y,
			maxf(green_left - yellow_left, 0.0),
			bar_height
		),
		Color(0.91, 0.65, 0.17)
	)

	# 绿色区域
	draw_rect(
		Rect2(
			green_left,
			bar_y,
			green_right - green_left,
			bar_height
		),
		Color(0.18, 0.72, 0.39)
	)

	# 右侧黄色
	draw_rect(
		Rect2(
			green_right,
			bar_y,
			maxf(yellow_right - green_right, 0.0),
			bar_height
		),
		Color(0.91, 0.65, 0.17)
	)

	# 右侧红色
	draw_rect(
		Rect2(
			yellow_right,
			bar_y,
			maxf(bar_right - yellow_right, 0.0),
			bar_height
		),
		Color(0.82, 0.19, 0.19)
	)

	# 判定线
	if is_active:

		draw_line(
			Vector2(marker_x, bar_y - 13),
			Vector2(marker_x, bar_y + bar_height + 13),
			Color.WHITE,
			3.0
		)

		draw_string(
			ThemeDB.fallback_font,
			Vector2(center_x, 20),
			"ENTER / 鼠标左键：判定",
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			16,
			Color.WHITE
		)

	# 等待下一发
	elif sequence_active and marker_waiting:

		draw_string(
			ThemeDB.fallback_font,
			Vector2(center_x, 20),
			"下一发即将到来……",
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			16,
			Color.WHITE
		)
