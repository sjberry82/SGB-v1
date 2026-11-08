extends Area2D

var rotate_speed : float = 3.0

@onready var start_pos : Vector2 = global_position
@onready var sprite : Sprite2D = $Sprite

func _physics_process(_delta):
	var time = Time.get_unix_time_from_system()
	
	# Rotation via Scaling
	sprite.scale.x = sin(time * rotate_speed)

func _on_body_entered(body):
	if not body.is_in_group("Player"):
		return
	body.increase_score(1)
	queue_free()
