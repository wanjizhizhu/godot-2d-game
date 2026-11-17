
extends Node2D

# 获取节点
@onready var crosshair = $HUD/Crosshair
@onready var battle_manager = $BattleManager
@onready var enemy_container: Node2D = $EnemyContainer


func _ready() -> void:

	# 连接射击信号
	crosshair.shot_fired.connect(_on_shot_fired)

	# 连接战斗阶段变化
	battle_manager.battle_phase_changed.connect(
		_on_battle_phase_changed
	)

	# 监听新生成的敌人
	enemy_container.child_entered_tree.connect(
		_on_enemy_child_entered_tree
	)

	# 初始化当前阶段的动画状态
	_on_battle_phase_changed(battle_manager.battle_phase)


# 战斗阶段变化
func _on_battle_phase_changed(_phase: int) -> void:

	var attack_active = battle_manager.is_player_attack_phase()

	# 控制准星
	crosshair.set_active(attack_active)

	# 控制所有现存敌人的摇晃
	for enemy in enemy_container.get_children():

		_set_enemy_sway(enemy, attack_active)


# 新敌人进入场景
func _on_enemy_child_entered_tree(enemy: Node) -> void:

	var attack_active = battle_manager.is_player_attack_phase()

	_set_enemy_sway(enemy, attack_active)


# 设置敌人摇晃状态
func _set_enemy_sway(enemy: Node, enabled: bool) -> void:

	if enemy.has_method("set_swaying_enabled"):

		enemy.set_swaying_enabled(enabled)


# 玩家开枪
func _on_shot_fired(screen_position: Vector2) -> void:

	# 只有攻击阶段允许开枪
	if not battle_manager.is_player_attack_phase():
		return

	# 屏幕坐标转换为世界坐标
	var world_position = (
		get_viewport().get_canvas_transform().affine_inverse()
		* screen_position
	)

	var query = PhysicsPointQueryParameters2D.new()

	query.position = world_position
	query.collision_mask = 1
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var space_state = get_world_2d().direct_space_state

	var results = space_state.intersect_point(query, 32)

	var head_hitbox: Area2D = null
	var body_hitbox: Area2D = null

	for result in results:

		var collider = result["collider"]

		if not collider is Area2D:
			continue

		var hitbox_name = collider.name.to_lower()

		if hitbox_name.contains("head"):
			head_hitbox = collider

		elif hitbox_name.contains("body"):
			body_hitbox = collider

	# 头部优先
	if head_hitbox != null:

		_apply_hit(head_hitbox, true)

	elif body_hitbox != null:

		_apply_hit(body_hitbox, false)

	else:

		print("脱靶！")

	# 无论命中还是脱靶，都消耗一发子弹
	battle_manager.register_attack_shot()


# 处理命中
func _apply_hit(hitbox: Area2D, is_head: bool) -> void:

	var current_node: Node = hitbox

	while current_node != null:

		if current_node.has_method("take_head_hit"):

			if is_head:

				current_node.take_head_hit()
				print("爆头！")

			else:

				current_node.take_body_hit()
				print("身体命中！")

			return

		current_node = current_node.get_parent()

	print("命中了碰撞箱，但没有找到敌人！")
