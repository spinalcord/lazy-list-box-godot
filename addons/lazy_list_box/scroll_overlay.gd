extends VScrollBar

@export var content_container: VBoxContainer  

func _ready() -> void:
	modulate.a = 0.0

	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _unhandled_input(event: InputEvent) -> void:
	var mouse_pos = get_global_mouse_position()
	var rect = Rect2(global_position, size)
	
	if !rect.has_point(mouse_pos):
		return
	
	if event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton
		
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			value -= 1
			accept_event()
		
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			value += 1
			accept_event()
