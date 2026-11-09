extends Control

# Called when the node enters the scene tree for the first time.
#func _ready():
	#await get_tree().create_timer(10.0).timeout
	#get_tree().change_scene_to_file("res://Scenes/menu.tscn")
	
func _on_main_menu_button_pressed():
	get_tree().change_scene_to_file("res://Scenes/menu.tscn")

func _on_quit_button_pressed():
	get_tree().quit()
