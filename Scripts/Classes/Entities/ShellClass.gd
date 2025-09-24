class_name Shell
extends Enemy

var moving := false

const MOVE_SPEED := 192
const AIR_MOVE_SPEED := 64

var combo := 0
@export var colour := "Green"
var flipped := false


var can_kick := false

var player: Player = null

const COMBO_VALS := [100, 200, 400, 500, 800, 1000, 2000, 4000, 5000, 8000, null]

var wake_meter := 0.0 ## SMB1R IS WOKE

var old_entity: Enemy = null

var can_update := true

var can_air_kick := false

var time_since_kicked := 0.0 ## For disabling stomp score if too close to a kick

func _ready() -> void:
	$Sprite.flip_v = flipped
	if flipped:
		$Sprite.offset.y = 1
	for i in 4:
		await get_tree().physics_frame
	can_kick = true
	$Hitbox/Collision.set_deferred("disabled", false)

func on_player_stomped_on(stomped_player: Player) -> void:
	player = stomped_player
	if can_kick == false:
		return
	if not moving:
		direction = sign(global_position.x - stomped_player.global_position.x)
		kick(stomped_player)
	else:
		DiscoLevel.combo_meter += 10
		moving = false
		AudioManager.play_sfx("enemy_stomp", global_position)
		
		stomped_player.enemy_bounce_off(true, time_since_kicked > 0.1)
		
		## TODO(jdaster64): Try to figure out a way to recreate the exact
		## anti-farm method used in Deluxe (permanently increasing the points)
		## without affecting normal scoring, and killing the Koopa only when
		## an increased kick results in 8000 points.
		if Global.current_game_mode == Global.GameMode.CHALLENGE and stomped_player.stomp_combo >= 8:
			die_from_object(stomped_player)

func block_bounced(_block: Block) -> void:
	velocity.y = -200
	wake_meter = 0

func on_player_hit(hit_player: Player) -> void:
	player = hit_player
	if can_kick == false:
		return 
	if not moving:
		direction = sign(global_position.x - hit_player.global_position.x )
		kick(hit_player)
	else:
		hit_player.damage()
		
func award_score(award_level: int) -> void:
	if award_level >= 10:
		if Global.current_game_mode == Global.GameMode.CHALLENGE or Settings.file.difficulty.inf_lives:
			$ScoreNoteSpawner.spawn_note(10000)
		else:
			AudioManager.play_global_sfx("1_up")
			Global.lives += 1
			$ScoreNoteSpawner.spawn_one_up_note()
	else:
		$ScoreNoteSpawner.spawn_note(COMBO_VALS[award_level])
		
func get_kick_award(hit_player: Player) -> int:
	var award_level = hit_player.stomp_combo + 2
	if award_level > 10:
		award_level = 10
	# Award special amounts of points if close to waking up.
	if wake_meter > 7 - 0.04:
		award_level = 9
	elif wake_meter > 7 - 0.25:
		award_level = 5
	elif wake_meter > 7 - 0.75:
		award_level = 3
	return award_level

func kick(hit_player: Player) -> void:
	update_hitbox()
	DiscoLevel.combo_meter += 25
	moving = true
	time_since_kicked = 0.0
	if can_air_kick:
		$ScoreNoteSpawner.spawn_note(8000)
	else:
		award_score(get_kick_award(hit_player))
	AudioManager.play_sfx("kick", global_position)

func _physics_process(delta: float) -> void:
	handle_movement(delta)
	handle_waking(delta)
	handle_block_collision()
	if moving:
		wake_meter = 0
		time_since_kicked += delta
		$Sprite.play("Spin")
	else:
		combo = 0
		if wake_meter > 5:
			$Sprite.play("Wake")
		else:
			$Sprite.play("Idle")

func handle_waking(delta: float) -> void:
	wake_meter += delta * (2 if Global.second_quest else 1)
	if wake_meter >= 7:
		summon_original_entity()

func summon_original_entity() -> void:
	old_entity.global_position = global_position
	add_sibling(old_entity)
	queue_free()

func handle_block_collision() -> void:
	if not moving:
		return
	for i in $Hitbox.get_overlapping_bodies():
		if i is Block and i.global_position.y < global_position.y:
			i.shell_block_hit.emit(self)

func add_combo() -> void:
	award_score(combo + 3)
	if combo < 7:
		combo += 1

func update_hitbox() -> void:
	can_kick = false
	$Hitbox.get_child(0).set_deferred("disabled", true)
	for i in 2:
		await get_tree().physics_frame
	$Hitbox.get_child(0).set_deferred("disabled", false)
	await get_tree().physics_frame
	can_kick = true

func handle_movement(delta: float) -> void:
	set_collision_layer_value(6, not moving)
	if moving:
		if is_on_wall():
			direction *= -1
			AudioManager.play_sfx("bump", global_position)
		var speed = MOVE_SPEED
		if is_on_floor() == false:
			speed = AIR_MOVE_SPEED
		velocity.x = ((speed * direction))
	elif is_on_floor():
		velocity.x = 0
	if is_on_floor() and velocity.y >= 0:
		can_air_kick = false
	velocity.y += (Global.entity_gravity / delta) * delta
	velocity.y = clamp(velocity.y, -INF, Global.entity_max_fall_speed)
	move_and_slide()
