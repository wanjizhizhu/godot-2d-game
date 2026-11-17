
extends Node

# 敌人场景
const ENEMY_SCENE = preload("res://scenes/EnemyActor.tscn")

# 获取敌人容器
@onready var enemy_container: Node2D = $"../EnemyContainer"

# 当前波次
var wave_number: int = 1

# 当前存活敌人
var alive_enemies: Array[Node] = []

# 每波最大敌人数
@export var max_enemies_per_wave: int = 5

# 是否正在切换波次
var is_transitioning: bool = false


func _ready() -> void:
	_register_existing_enemies()

	if alive_enemies.is_empty():
		_spawn_wave()


# 登记场景中已经存在的敌人
func _register_existing_enemies() -> void:

	for enemy in enemy_container.get_children():

		if enemy.has_method("configure_combat_stats"):

			# 第一波全部为1级敌人
			_configure_enemy(enemy, 1)
			_track_enemy(enemy)

	print("第一波敌人数量：", alive_enemies.size())


# 追踪敌人
func _track_enemy(enemy: Node) -> void:

	alive_enemies.append(enemy)

	enemy.tree_exited.connect(
		_on_enemy_tree_exited.bind(enemy),
		CONNECT_ONE_SHOT
	)


# 敌人退出场景树
func _on_enemy_tree_exited(enemy: Node) -> void:

	# 游戏退出保护
	if not is_inside_tree():
		return

	alive_enemies.erase(enemy)

	# 排除非死亡导致的节点退出
	if not is_instance_valid(enemy):
		return

	if not enemy.get("is_dying"):
		return

	print("敌人被消灭！剩余敌人：", alive_enemies.size())

	if alive_enemies.is_empty():
		_start_next_wave()


# 开始下一波
func _start_next_wave() -> void:

	if not is_inside_tree() or is_transitioning:
		return

	var current_tree = get_tree()

	if current_tree == null:
		return

	is_transitioning = true

	print("第", wave_number, "波结束！")

	await current_tree.create_timer(1.2).timeout

	# 游戏退出保护
	if not is_inside_tree():
		return

	wave_number += 1

	_spawn_wave()

	is_transitioning = false


# 生成当前波次的敌人等级列表
func _generate_enemy_levels(
	enemy_count: int
) -> Array[int]:

	var levels: Array[int] = []

	# 波次决定当前等级上限
	var highest_level: int = clampi(wave_number, 1, 9)

	# 普通敌人等级范围
	var normal_max: int = mini(highest_level, 6)
	var normal_min: int = maxi(1, normal_max - 2)

	# 高级敌人的位置
	var high_level_slot: int = -1

	# 第7波开始，每波最多一个高级敌人
	if highest_level >= 7:
		high_level_slot = randi_range(0, enemy_count - 1)

	for i in range(enemy_count):

		if i == high_level_slot:

			levels.append(highest_level)

		else:

			var level: int = randi_range(
				normal_min,
				normal_max
			)

			levels.append(level)

	return levels


# 给敌人分配战斗属性
func _configure_enemy(enemy: Node, level: int) -> void:

	# 每提升一级增加一个属性点
	var total_points: int = level + 1

	# 随机分配枪法和速度
	var gun_skill: int = randi_range(1, level)
	var speed: int = total_points - gun_skill

	# 当前波次只生成普通敌人
	enemy.set("is_boss", false)

	enemy.call(
		"configure_combat_stats",
		level,
		gun_skill,
		speed
	)

	# 输出属性，方便开发测试
	print(
		"敌人等级：", level,
		" | 枪法：", gun_skill,
		" | 速度：", speed
	)


# 生成一波敌人
func _spawn_wave() -> void:

	# 计算敌人数量
	var enemy_count: int = clampi(
		wave_number + 1,
		1,
		maxi(1, max_enemies_per_wave)
	)

	# 生成敌人等级列表
	var enemy_levels: Array[int] = \
		_generate_enemy_levels(enemy_count)

	print("------------------------")
	print("第", wave_number, "波开始！")
	print("敌人数：", enemy_count)

	# 获取游戏窗口尺寸
	var screen_size = get_viewport().get_visible_rect().size

	var left_margin = 150.0
	var right_margin = screen_size.x - 150.0

	for i in range(enemy_count):

		# 创建敌人实例
		var enemy = ENEMY_SCENE.instantiate() as Node2D

		# 分配敌人等级和属性
		_configure_enemy(enemy, enemy_levels[i])

		# 计算横向位置
		var ratio: float = 0.5

		if enemy_count > 1:

			ratio = float(i) / float(enemy_count - 1)

		var x = lerpf(left_margin, right_margin, ratio)

		# 纵向位置略微随机
		var y = screen_size.y * 0.56 \
			+ randf_range(-12.0, 12.0)

		enemy.position = Vector2(x, y)

		# 加入敌人容器
		enemy_container.add_child(enemy)

		# 追踪敌人
		_track_enemy(enemy)
