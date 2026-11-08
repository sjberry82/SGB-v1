extends CanvasLayer

@onready var health_container = $HealthContainer
var healthmarkers : Array = []

@onready var score_text : Label = $ScoreText

@onready var player = get_parent()

func _ready():
	healthmarkers = health_container.get_children()
	
	player.OnUpdateHealth.connect(_update_healthmarkers)
	player.OnUpdateScore.connect(_update_score)
	
	_update_healthmarkers(player.health)
	_update_score(PlayerStats.score)
	
func _update_healthmarkers(health: int):
	for i in len(healthmarkers):
		healthmarkers[i].visible = i < health
		
func _update_score(score : int):
	score_text.text = "Score: " + str(score)
