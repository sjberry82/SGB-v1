extends CharacterBody2D

signal OnUpdateHealth (health : int)
signal OnUpdateScore (score : int)

@export var move_speed : float = 75
@export var acceleration : float = 50
@export var braking : float = 20
@export var gravity : float = 500
@export var jump_force : float = 215
@export var health : int = 3

var move_input : float
var is_dead := false
var max_camera_x : float = 0.0
const PLAYER_HALF_WIDTH : float = 8.0

@onready var sprite : Sprite2D = $Sprite
@onready var anim : AnimationPlayer = $AnimationPlayer
@onready var audio : AudioStreamPlayer = $AudioStreamPlayer
@onready var camera : Camera2D = $Camera2D

var take_damage_sfx : AudioStream = preload("res://Audio/SFX/take_damage.wav")
var coin_sfx : AudioStream = preload("res://Audio/SFX/coin.wav")


func _ready():
	max_camera_x = camera.global_position.x
	
func _physics_process(delta):
	# Add Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
		
	# Handle movement input
	move_input = Input.get_axis("move_left", "move_right")
	
	# Movement Acceleration
	if move_input != 0:
		velocity.x = lerp(velocity.x, move_input * move_speed, acceleration * delta)
	# Movement Deceleration
	else:
		velocity.x = lerp(velocity.x, 0.0, braking * delta)
		
	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_force
		
	move_and_slide()
	
func _process(_delta):
	var half_view : int = int(get_viewport_rect().size.x / camera.zoom.x * 0.5)
	max_camera_x = max(max_camera_x, camera.global_position.x)
	camera.limit_left = floori(max_camera_x - half_view)
	
	var min_player_x : float = camera.limit_left + PLAYER_HALF_WIDTH
	if global_position.x < min_player_x and velocity.x < 0:
		global_position.x = min_player_x
		velocity.x = 0.0
		
	if velocity.x != 0:
		sprite.flip_h = velocity.x < 0
		
	# Kills Player when falling off Screen.
	if global_position.y > 30:
		#game_over()
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://Scenes/menu.tscn")
		
	_manage_animation()
	
func _manage_animation():
	if is_dead:
		return
		
	if not is_on_floor():
		anim.play("jump")
	elif move_input != 0:
		anim.play("move")
	else:
		anim.play("idle")
		
func take_damage(amount: int):
	health -= amount
	OnUpdateHealth.emit(health)
	_damage_flash()
	play_sound(take_damage_sfx)
	
	if health <= 0:
		call_deferred("game_over")
		
func game_over():
	if is_dead:
		return
	is_dead = true
	$AnimationPlayer.play("death")
# Wait and resets the scene when player dies.
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://Scenes/menu.tscn")
	
func increase_score(amount: int):
	PlayerStats.score += amount
	OnUpdateScore.emit(PlayerStats.score)
	play_sound(coin_sfx)
	
func _damage_flash():
	sprite.modulate = Color.RED
	await get_tree().create_timer(0.05).timeout
	sprite.modulate = Color.WHITE

func play_sound(sound : AudioStream, pitch : float = 1.0):
	audio.stream = sound
	audio.pitch_scale = pitch
	audio.play()
	
func bounce():
	velocity.y = -200.0
