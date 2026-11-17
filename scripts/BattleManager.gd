
extends Node

signal battle_phase_changed(phase: int)
signal enemy_attack_resolved(enemy: Node, result: int)

# 敌人攻击结果
enum AttackResult {
	DODGED,
	BODY_HIT,
	HEAD_HIT
}
# 玩家伤势
enum PlayerInjuryState {
	NORMAL,
	INJURED,
	HEAVY,
	DEAD
}
enum BattlePhase {
	PLAYER_SELECT,
	PLAYER_ATTACK,
	ENEMY_TURN
}

enum ActionChoice {
	ATTACK,
	DODGE
}

# 玩家速度等级
@export_range(1, 99, 1) var player_speed_level: int = 1
# 当前玩家伤势
var player_injury_state: PlayerInjuryState = PlayerInjuryState.NORMAL

# 临时保护：抵消同一敌人接下来的子弹
var protected_shots_remaining: int = 0

# 当前敌人还剩多少发子弹
var current_enemy_shots_remaining: int = 0

# 玩家本轮是否受到伤害
var player_was_hit_this_enemy_turn: bool = false

# 敌人攻击参数
@export_range(1, 5, 1) var max_shots_per_enemy: int = 3

# 每增加多少级速度，增加一次射击
@export_range(1.0, 10.0, 0.5) var speed_levels_per_extra_shot: float = 3.0
# 行动力
var max_action_points: int = 2
var current_action_points: int = 2

# 行动记录
var planned_attacks: int = 0
var remaining_attacks: int = 0
var dodge_selected: bool = false

# 当前选项
var selected_action: ActionChoice = ActionChoice.ATTACK

# 当前阶段
var battle_phase: BattlePhase = BattlePhase.PLAYER_SELECT

# HUD
@onready var hud: CanvasLayer = $"../HUD"
# 敌人容器
@onready var enemy_container: Node2D = $"../EnemyContainer"

# 闪避判定条
@onready var dodge_bar = $"../HUD/DodgeBar"
# 当前正在攻击的敌人
var current_attacking_enemy: Node = null
# UI节点
var panel: PanelContainer
var phase_label: Label
var ap_label: Label
var plan_label: Label
var status_label: Label
# 四颗心
var heart_labels: Array[Label] = []
var attack_button: Button
var dodge_button: Button


func _ready() -> void:

	_build_ui()

	# 接收判定条每一发子弹的结果
	dodge_bar.judged.connect(_on_dodge_bar_judged)

	_start_player_turn()

# 创建全宽行动栏
func _build_ui() -> void:

	panel = PanelContainer.new()
	panel.name = "BattlePanel"

	# 锚定屏幕底部，横向铺满
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0

	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = -165.0
	panel.offset_bottom = 0.0

	panel.custom_minimum_size = Vector2(0, 165)
	panel.z_index = 20
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	hud.add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 7)
	margin.add_child(layout)

	
# 顶部信息栏
	var top_row = HBoxContainer.new()
	layout.add_child(top_row)

	phase_label = Label.new()
	phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(phase_label)

	# 玩家生命状态
	var hearts_container = HBoxContainer.new()
	hearts_container.add_theme_constant_override("separation", 4)
	top_row.add_child(hearts_container)

	# 创建四颗心
	for i in range(3):

		var heart = Label.new()

		heart.text = "♥"

		heart.add_theme_font_size_override(
			"font_size",
			25
		)

		heart.add_theme_color_override(
			"font_color",
			Color(1.0, 0.2, 0.3)
		)

		heart_labels.append(heart)

		hearts_container.add_child(heart)

	ap_label = Label.new()
	top_row.add_child(ap_label)


	# 行动计划
	plan_label = Label.new()
	layout.add_child(plan_label)

	# 两个行动选项
	var action_row = HBoxContainer.new()
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_theme_constant_override("separation", 12)
	layout.add_child(action_row)

	attack_button = Button.new()
	attack_button.text = "攻击\n消耗 1 AP"
	attack_button.custom_minimum_size = Vector2(0, 65)
	attack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack_button.focus_mode = Control.FOCUS_NONE
	attack_button.pressed.connect(_on_attack_pressed)
	action_row.add_child(attack_button)

	dodge_button = Button.new()
	dodge_button.text = "闪避\n消耗 1 AP"
	dodge_button.custom_minimum_size = Vector2(0, 65)
	dodge_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dodge_button.focus_mode = Control.FOCUS_NONE
	dodge_button.pressed.connect(_on_dodge_pressed)
	action_row.add_child(dodge_button)

	# 操作提示
	status_label = Label.new()
	layout.add_child(status_label)


# 开始玩家回合
func _start_player_turn() -> void:
	# 玩家死亡后，不再开始新回合
	if player_injury_state == PlayerInjuryState.DEAD:
		return
		
	# 根据基础速度计算行动力
	var base_action_points = 2 + int(
		(player_speed_level - 1) / 2
	)

	# 伤势越重，行动力越少
	max_action_points = maxi(
		1,
		base_action_points - int(player_injury_state)
	)
	current_action_points = max_action_points

	planned_attacks = 0
	remaining_attacks = 0
	dodge_selected = false

	selected_action = ActionChoice.ATTACK

	battle_phase = BattlePhase.PLAYER_SELECT

	status_label.text = "WASD切换选项，Enter确认。"

	battle_phase_changed.emit(battle_phase)
	_update_ui()


# 键盘操作
func _input(event: InputEvent) -> void:

	if battle_phase != BattlePhase.PLAYER_SELECT:
		return

	if event is InputEventKey and event.pressed and not event.echo:

		match event.keycode:

			KEY_W, KEY_A, KEY_S, KEY_D:

				# 在攻击和闪避之间切换
				if selected_action == ActionChoice.ATTACK:
					selected_action = ActionChoice.DODGE
				else:
					selected_action = ActionChoice.ATTACK

				_update_ui()
				get_viewport().set_input_as_handled()

			KEY_ENTER, KEY_KP_ENTER:

				_confirm_selected_action()
				get_viewport().set_input_as_handled()


# 确认当前选项
func _confirm_selected_action() -> void:

	if selected_action == ActionChoice.ATTACK:
		_commit_action(ActionChoice.ATTACK)

	else:
		_commit_action(ActionChoice.DODGE)


# 鼠标点击攻击
func _on_attack_pressed() -> void:
	_commit_action(ActionChoice.ATTACK)


# 鼠标点击闪避
func _on_dodge_pressed() -> void:
	_commit_action(ActionChoice.DODGE)


# 记录行动
func _commit_action(action: ActionChoice) -> void:

	if battle_phase != BattlePhase.PLAYER_SELECT:
		return

	if current_action_points <= 0:
		return

	if action == ActionChoice.DODGE and dodge_selected:
		return

	selected_action = action

	if action == ActionChoice.ATTACK:
		planned_attacks += 1

	elif action == ActionChoice.DODGE:
		dodge_selected = true

	current_action_points -= 1

	_update_ui()

	# 行动力用完，自动结束选择阶段
	if current_action_points <= 0:
		_finish_action_selection()


# 结束行动选择
func _finish_action_selection() -> void:

	if battle_phase != BattlePhase.PLAYER_SELECT:
		return

	# 有攻击次数，先进入攻击阶段
	if planned_attacks > 0:

		remaining_attacks = planned_attacks

		battle_phase = BattlePhase.PLAYER_ATTACK

		status_label.text = "攻击阶段：还可以开枪 %d 次。" % remaining_attacks

		battle_phase_changed.emit(battle_phase)
		_update_ui()

	# 没有攻击，直接进入敌人回合
	else:
		_enter_enemy_turn()


# 一枪执行完毕后由Main调用
func register_attack_shot() -> void:

	if battle_phase != BattlePhase.PLAYER_ATTACK:
		return

	remaining_attacks -= 1
	remaining_attacks = maxi(remaining_attacks, 0)

	print("剩余射击次数：", remaining_attacks)

	# 所有攻击执行完毕
	if remaining_attacks <= 0:
		_enter_enemy_turn()

	else:
		status_label.text = "攻击阶段：还可以开枪 %d 次。" % remaining_attacks
		_update_ui()



# 进入敌人回合

# 进入敌人回合
func _enter_enemy_turn() -> void:

	# 防止重复进入
	if battle_phase == BattlePhase.ENEMY_TURN:
		return

	# 每次敌人回合开始，重置本轮受伤记录
	player_was_hit_this_enemy_turn = false

	battle_phase = BattlePhase.ENEMY_TURN

	if dodge_selected:
		status_label.text = "敌人回合：准备闪避！"
	else:
		status_label.text = "敌人回合：未选择闪避。"

	battle_phase_changed.emit(battle_phase)
	_update_ui()

	print("进入敌人回合")

	# 开始敌人攻击流程
	_run_enemy_turn()


# 执行敌人攻击流程
func _run_enemy_turn() -> void:

	await get_tree().create_timer(0.5).timeout

	if not is_inside_tree():
		return

	# 获取当前所有敌人
	var enemies = enemy_container.get_children()

	# 逐个敌人攻击
	for enemy in enemies:

		if not is_instance_valid(enemy):
			continue

		if not enemy.has_method("get_effective_gun_skill"):
			continue

		if bool(enemy.get("is_dying")):
			continue

		# 记录当前攻击者
		current_attacking_enemy = enemy

		# 当前敌人开始摇晃
		_set_enemy_attacking(enemy, true)

		# 获取有效属性
		var effective_speed = float(
			enemy.call("get_effective_speed")
		)

		var effective_gun_skill = maxf(
			float(enemy.call("get_effective_gun_skill")),
			1.0
		)

		# 判断是否为Boss
		var is_boss = bool(enemy.get("is_boss"))

		# 根据速度计算攻击次数
		var shot_count = 1 + int(
			maxf(effective_speed - 1.0, 0.0)
			/ speed_levels_per_extra_shot
		)
		
		
		# 确定最终攻击次数
		shot_count = maxi(shot_count, 1)

		# 普通敌人限制最多攻击次数
		if not is_boss:
			shot_count = mini(
				shot_count,
				max_shots_per_enemy
			)

		# 初始化当前敌人的实际子弹数量
		current_enemy_shots_remaining = shot_count
		protected_shots_remaining = 0


		print(
			enemy.name,
			" 开始攻击，枪法：",
			effective_gun_skill,
			" 速度：",
			effective_speed,
			" 攻击次数：",
			shot_count
		)

		# 玩家选择了闪避
		if dodge_selected:

			status_label.text = "%s 正在连续攻击！" % enemy.name
			_update_ui()

			# 整个敌人只启动一次连续判定
			dodge_bar.start_sequence(
				effective_gun_skill,
				is_boss,
				shot_count
			)

			# 等待这个敌人的所有攻击结束
			await dodge_bar.sequence_finished

		# 玩家没有选择闪避
		else:

			for shot_index in range(shot_count):

				if not is_inside_tree():
					return

				if not is_instance_valid(enemy):
					break

				if bool(enemy.get("is_dying")):
					break

				status_label.text = "%s 攻击：第 %d / %d 发" % [
					enemy.name,
					shot_index + 1,
					shot_count
				]

				_process_enemy_bullet(
					enemy,
					AttackResult.BODY_HIT
				)

				# 两发之间稍作停顿
				if shot_index < shot_count - 1:
					await get_tree().create_timer(0.35).timeout

		if not is_inside_tree():
			return

		# 当前敌人攻击结束
		if is_instance_valid(enemy):
			_set_enemy_attacking(enemy, false)

		current_attacking_enemy = null

		# 下一个敌人稍后行动
		await get_tree().create_timer(0.3).timeout

	# 所有敌人攻击结束
	if not is_inside_tree():
		return

	current_attacking_enemy = null

	print("敌人回合结束！")

# 检查是否满足伤势恢复条件
# 本回合没有受到伤害，恢复一级伤势
	if not player_was_hit_this_enemy_turn:

		if player_injury_state != PlayerInjuryState.NORMAL:

			_recover_player_injury()

			print("本回合未受伤，恢复一级伤势！")

# 玩家死亡，不再开始新回合
	if player_injury_state == PlayerInjuryState.DEAD:

		status_label.text = "你已倒下，战斗结束。"

		_update_ui()

		return

	_start_player_turn()


# 控制敌人攻击动画
func _set_enemy_attacking(enemy: Node, enabled: bool) -> void:

	if enemy.has_method("set_swaying_enabled"):
		enemy.call("set_swaying_enabled", enabled)

	elif enemy.has_method("set_attacking"):
		enemy.call("set_attacking", enabled)


# 接收判定条每一发的结果
func _on_dodge_bar_judged(result: int) -> void:

	if not is_instance_valid(current_attacking_enemy):
		return

	_process_enemy_bullet(
		current_attacking_enemy,
		result
	)

func _resolve_enemy_attack(enemy: Node, result: int) -> void:
# 结算玩家伤势
	_apply_player_injury(result)
	
	match result:

		AttackResult.DODGED:
			print(enemy.name, "：玩家成功闪避！")
			status_label.text = "成功闪避！"

		AttackResult.BODY_HIT:
			print(enemy.name, "：玩家身体中弹！")
			status_label.text = "身体中弹！"

		AttackResult.HEAD_HIT:
			print(enemy.name, "：玩家头部中弹！")
			status_label.text = "头部中弹！"

	# 发送攻击结果，供后续玩家生命值系统使用
	enemy_attack_resolved.emit(enemy, result)

	_update_ui()



# 判断当前是否为攻击阶段
func is_player_attack_phase() -> bool:

	return battle_phase == BattlePhase.PLAYER_ATTACK


# 更新UI
func _update_ui() -> void:

	if not is_instance_valid(panel):
		return
		
	# 更新玩家生命状态
	_update_hearts()
	
	match battle_phase:

		BattlePhase.PLAYER_SELECT:
			phase_label.text = "玩家回合 | 选择行动"

		BattlePhase.PLAYER_ATTACK:
			phase_label.text = "玩家回合 | 攻击阶段"

		BattlePhase.ENEMY_TURN:
			phase_label.text = "敌人回合"

	ap_label.text = "行动力 AP：%d / %d" % [
		current_action_points,
		max_action_points
	]

	var dodge_text = "已选择" if dodge_selected else "未选择"

	plan_label.text = "已安排攻击：%d 次    闪避：%s" % [
		planned_attacks,
		dodge_text
	]

	attack_button.text = "攻击\n消耗 1 AP\n已安排 %d 次" % planned_attacks

	if dodge_selected:
		dodge_button.text = "闪避\n已选择"
	else:
		dodge_button.text = "闪避\n消耗 1 AP"

	var selecting = battle_phase == BattlePhase.PLAYER_SELECT

	attack_button.disabled = not selecting or current_action_points <= 0

	dodge_button.disabled = (
		not selecting
		or current_action_points <= 0
		or dodge_selected
	)

	# 当前选中的选项使用金色边框
	_style_button(
		attack_button,
		selected_action == ActionChoice.ATTACK
	)

	_style_button(
		dodge_button,
		selected_action == ActionChoice.DODGE
	)


# 行动选项样式
func _style_button(button: Button, selected: bool) -> void:

	var style = StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.35, 0.27, 0.18)
		style.border_color = Color(0.9, 0.68, 0.35)
		style.set_border_width_all(3)

	else:
		style.bg_color = Color(0.16, 0.16, 0.16)
		style.border_color = Color(0.38, 0.38, 0.38)
		style.set_border_width_all(1)

	style.set_corner_radius_all(8)

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)

	button.add_theme_color_override(
		"font_color",
		Color(1.0, 0.95, 0.85)
	)


# 玩家受到伤害
func _apply_player_injury(result: int) -> void:

	if player_injury_state == PlayerInjuryState.DEAD:
		return

	if result == AttackResult.DODGED:
		return

	player_was_hit_this_enemy_turn = true

	var damage = 1

	if result == AttackResult.HEAD_HIT:
		damage = 2

	player_injury_state = clampi(
		int(player_injury_state) + damage,
		PlayerInjuryState.NORMAL,
		PlayerInjuryState.DEAD
	)

	print("玩家伤势：", _get_player_injury_name())

	if player_injury_state == PlayerInjuryState.DEAD:
		print("玩家死亡！")


# 获取玩家伤势名称
func _get_player_injury_name() -> String:

	match player_injury_state:

		PlayerInjuryState.NORMAL:
			return "正常"

		PlayerInjuryState.INJURED:
			return "轻伤"

		PlayerInjuryState.HEAVY:
			return "重伤"

		PlayerInjuryState.DEAD:
			return "死亡"

	return "未知"


# 恢复一级伤势
func _recover_player_injury() -> void:

	if player_injury_state == PlayerInjuryState.NORMAL:
		return

	if player_injury_state == PlayerInjuryState.DEAD:
		return

	player_injury_state = max(
		int(player_injury_state) - 1,
		PlayerInjuryState.NORMAL
	)

	print("玩家恢复一级伤势：", _get_player_injury_name())


# 处理敌人的单发子弹
func _process_enemy_bullet(enemy: Node, result: int) -> void:

	# 当前敌人的剩余子弹减少
	current_enemy_shots_remaining = maxi(
		current_enemy_shots_remaining - 1,
		0
	)

	# 检查临时保护
	if protected_shots_remaining > 0:

		protected_shots_remaining -= 1

		print(
			"临时保护抵消子弹！剩余保护次数：",
			protected_shots_remaining
		)

		status_label.text = "子弹被临时保护抵消！"

		_update_ui()

		return

	# 正常结算伤害
	_resolve_enemy_attack(enemy, result)

	# 玩家被击中，而且当前敌人至少还有两发子弹
	if result != AttackResult.DODGED \
	and current_enemy_shots_remaining >= 2:

		protected_shots_remaining = 2

		print("触发临时保护！接下来两发子弹无效。")

# 更新玩家三颗心
func _update_hearts() -> void:

	var full_hearts = 3

	match player_injury_state:

		PlayerInjuryState.NORMAL:
			full_hearts = 3

		PlayerInjuryState.INJURED:
			full_hearts = 2

		PlayerInjuryState.HEAVY:
			full_hearts = 1

		PlayerInjuryState.DEAD:
			full_hearts = 0

	for i in range(heart_labels.size()):

		if i < full_hearts:
			heart_labels[i].text = "♥"
			heart_labels[i].add_theme_color_override(
				"font_color",
				Color(1.0, 0.2, 0.3)
			)
		else:
			heart_labels[i].text = "♡"
			heart_labels[i].add_theme_color_override(
				"font_color",
				Color(0.45, 0.45, 0.45)
			)

# 获取玩家伤势倍率
func _get_player_injury_multiplier() -> float:

	match player_injury_state:

		PlayerInjuryState.NORMAL:
			return 1.0

		PlayerInjuryState.INJURED:
			return 0.75

		PlayerInjuryState.HEAVY:
			return 0.5

		PlayerInjuryState.DEAD:
			return 0.0

	return 1.0


# 获取玩家有效速度
func get_effective_player_speed() -> float:

	return player_speed_level * _get_player_injury_multiplier()
