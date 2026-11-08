extends Area2D

@export var move_direction : Vector2
@export var move_speed : float = 20

@onready var start_pos : Vector2 = global_position
@onready var target_pos : Vector2 = global_position + move_direction

#func _ready():
	#$AnimationPlayer.play()
	
func _physics_process(delta):
	global_position = global_position.move_toward(target_pos, move_speed * delta)
	# Turns the Enemy around to move back to its starting position.
	if global_position == target_pos:
		if target_pos == start_pos:
			target_pos = start_pos + move_direction
		else:
			target_pos = start_pos
			
func _on_body_entered(body):
	if not body.is_in_group("Player"):
		return
		
	body.take_damage(1)
