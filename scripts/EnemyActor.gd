
extends Node2D

enum InjuryState {
	NORMAL,
	INJURED,
	HEAVY,
	DEAD
}

@export var is_boss: bool = false

# 敌人基础属性
@export_range(1, 99, 1) var enemy_level: int = 1
@export_range(1, 99, 1) var gun_skill_level: int = 1
@export_range(1, 99, 1) var speed_level: int = 1

# 摇晃动画参数
@export var sway_speed: float = 3.5
@export var sway_distance: float = 25.0
@export var body_tilt: float = 12.0
@export var head_tilt: float = 10.0

# 四种表情素材
const FACE_NORMAL = preload("res://assets/faces/face_normal.jpg")
const FACE_INJURED = preload("res://assets/faces/face_injured.jpg")
const FACE_HEAVY = preload("res://assets/faces/face_heavy.jpg")
const FACE_DEAD = preload("res://assets/faces/face_dead.jpg")

# 获取人物节点
@onready var body: Node2D = $Body
@onready var head: Node2D = $Head
@onready var head_sprite: Sprite2D = $Head/HeadSprite

# 伤势状态
var injury_state: InjuryState = InjuryState.NORMAL
var body_hit_count: int = 0
var is_dying: bool = false

# 是否正在攻击
var is_attacking: bool = false

# 敌人头顶等级标识
var level_label: Label

# 表情的统一显示尺寸
var target_face_size: Vector2

# 记录人物初始位置和角度
var body_start_position: Vector2
var head_start_position: Vector2
var body_start_rotation: float
var head_start_rotation: float

# 每个敌人的动画起始相位不同
var sway_time: float = randf_range(0.0, TAU)
# 是否允许敌人摇晃
var sway_enabled: bool = false

func _ready() -> void:
		# 普通敌人最高9级，Boss不受此限制
	var level_limit = 99 if is_boss else 9
	enemy_level = clampi(enemy_level, 1, level_limit)
	
	target_face_size = FACE_NORMAL.get_size() * head_sprite.scale

	body_start_position = body.position
	head_start_position = head.position

	body_start_rotation = body.rotation
	head_start_rotation = head.rotation

	_create_level_label()
	
	_update_face()


# 每帧更新敌人动作
func _process(delta: float) -> void:
	if is_dying or not sway_enabled:
		return

	# 暂时将玩家有效枪法设为1级
	var player_gun_skill: float = 1.0

	# 敌人有效速度与玩家枪法直接对抗
	var speed_difference: float = \
		get_effective_speed() - player_gun_skill

	# 限制动画速度，防止难度过高
	var speed_multiplier: float = clampf(
		1.0 + speed_difference * 0.12,
		0.5,
		2.0
	)

	sway_time += delta * sway_speed * speed_multiplier

	# 身体左右移动
	var offset_x = sin(sway_time) * sway_distance

	body.position = body_start_position + Vector2(offset_x, 0)

	# 身体左右倾斜
	var tilt = deg_to_rad(body_tilt) * sin(sway_time)

	body.rotation = body_start_rotation + tilt

	# 头部跟随身体移动和倾斜
	var head_offset = head_start_position - body_start_position

	head.position = body.position + head_offset.rotated(tilt)

	# 头部额外摇晃
	head.rotation = head_start_rotation + tilt \
		+ deg_to_rad(head_tilt) * sin(sway_time * 1.7)

# 控制敌人是否进入攻击状态
func set_attacking(value: bool) -> void:

	is_attacking = value

	# 停止攻击时恢复初始姿态
	if not is_attacking:

		body.position = body_start_position
		head.position = head_start_position

		body.rotation = body_start_rotation
		head.rotation = head_start_rotation
		
# 控制敌人摇晃动画
func set_swaying_enabled(enabled: bool) -> void:

	if is_dying:
		return

	var was_enabled = sway_enabled

	sway_enabled = enabled

	# 停止摇晃时恢复人物原始姿势
	if was_enabled and not enabled and is_node_ready():

		body.position = body_start_position
		head.position = head_start_position

		body.rotation = body_start_rotation
		head.rotation = head_start_rotation

# 身体中弹
func take_body_hit() -> void:
	_apply_damage(1)


# 头部中弹
func take_head_hit() -> void:
	if is_boss:
		_apply_damage(2)
	else:
		_apply_damage(3)


# 统一结算伤势
func _apply_damage(damage: int) -> void:
	if is_dying:
		return

	body_hit_count = mini(body_hit_count + damage, 3)

	match body_hit_count:
		0:
			injury_state = InjuryState.NORMAL
		1:
			injury_state = InjuryState.INJURED
		2:
			injury_state = InjuryState.HEAVY
		3:
			injury_state = InjuryState.DEAD

	_update_face()

	if injury_state == InjuryState.DEAD:
		_die()


# 统一表情图片大小
func _set_face(face_texture: Texture2D) -> void:
	head_sprite.texture = face_texture

	var texture_size = face_texture.get_size()

	head_sprite.scale = Vector2(
		target_face_size.x / texture_size.x,
		target_face_size.y / texture_size.y
	)


# 根据伤势切换表情
func _update_face() -> void:
	match injury_state:
		InjuryState.NORMAL:
			_set_face(FACE_NORMAL)
		InjuryState.INJURED:
			_set_face(FACE_INJURED)
		InjuryState.HEAVY:
			_set_face(FACE_HEAVY)
		InjuryState.DEAD:
			_set_face(FACE_DEAD)


# 根据伤势计算属性倍率
func _get_injury_multiplier() -> float:

	match injury_state:

		InjuryState.NORMAL:
			return 1.0

		InjuryState.INJURED:
			return 0.75

		InjuryState.HEAVY:
			return 0.5

		InjuryState.DEAD:
			return 0.0

	return 1.0


# 获取当前有效枪法
func get_effective_gun_skill() -> float:

	return gun_skill_level * _get_injury_multiplier()


# 获取当前有效速度
func get_effective_speed() -> float:

	return speed_level * _get_injury_multiplier()

# 死亡处理
func _die() -> void:
	is_dying = true

	var tween = create_tween()

	tween.tween_interval(0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.07)
	tween.tween_property(self, "modulate:a", 1.0, 0.07)
	tween.tween_property(self, "modulate:a", 0.0, 0.07)

	tween.tween_callback(queue_free)


# 设置敌人的等级和基础属性
func configure_combat_stats(
	level: int,
	gun_skill: int,
	speed: int
) -> void:

	var level_limit = 99 if is_boss else 9

	enemy_level = clampi(level, 1, level_limit)
	gun_skill_level = maxi(gun_skill, 1)
	speed_level = maxi(speed, 1)

	_update_level_label()
	
# 创建敌人头顶等级标识
func _create_level_label() -> void:

	level_label = Label.new()
	level_label.name = "LevelLabel"

	# 标识的位置和大小
	level_label.position = Vector2(-45, -165)
	level_label.size = Vector2(90, 30)

	# 文字居中
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 字体大小
	level_label.add_theme_font_size_override("font_size", 20)

	# 黑色描边
	level_label.add_theme_color_override(
		"font_outline_color",
		Color.BLACK
	)
	level_label.add_theme_constant_override("outline_size", 5)

	# 保证显示在人物前面
	level_label.z_index = 10

	add_child(level_label)

	_update_level_label()


# 更新头顶文字
func _update_level_label() -> void:

	if level_label == null:
		return

	if is_boss:
		level_label.text = "BOSS"

		level_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.12, 0.12)
		)

	else:
		level_label.text = "Lv. %d" % enemy_level

		level_label.add_theme_color_override(
			"font_color",
			Color(1.0, 1.0, 1.0)
		)
