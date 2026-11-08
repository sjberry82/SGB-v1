extends Camera2D


var intensity : float = 0

func _ready():
	get_parent().OnUpdateHealth.connect(_damage_shake)
	
func _damage_shake(_health):
	intensity = 3
	
func _process(delta):
	if intensity > 0:
		intensity = lerpf(intensity, 0, delta * 10)
		offset = _get_random_offset()
	
func _get_random_offset():
	var x = randf_range(-intensity, intensity)
	var y = randf_range(-intensity, intensity)
	return Vector2(x, y)
