extends Area2D

@export var speed : float = 15.0

var direction : float = 1.0

@onready var ray : RayCast2D = $RayCast2D

func _physics_process(delta):
	ray.target_position = Vector2(12 * direction, 0)
	ray.force_raycast_update()
	
	if ray.is_colliding():
		direction *= -1
		ray.target_position = Vector2(12 * direction, 0)
		
	position.x += direction * speed * delta
	$Sprite.flip_h = direction < 0
	
func _on_body_entered(body):
	if not body.is_in_group("Player"):
		return
		
	if not body.is_on_floor() and body.velocity.y > 0 and body.global_position.y < $CollisionShape2D.global_position.y + 20:
		body.bounce()
		body.play_sound(body.take_damage_sfx, 0.8)
		die()
	else:
		body.take_damage(1)
		
func die():
	set_physics_process(false)
	set_process(false)
	set_deferred("monitoring", false)
	$CollisionShape2D.set_deferred("disabled", true)
	
	var tween = create_tween()
	tween.tween_property($Sprite, "scale", Vector2(1.4, 0.15), 0.15)
	tween.tween_callback(queue_free)
