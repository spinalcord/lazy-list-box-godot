extends VScrollBar

@export var debug_enabled: bool = false  # Debug toggle in the inspector
var touch_in_area: bool = false

func _ready() -> void:
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # All clicks pass through

func debug_print(message: String) -> void:
	if debug_enabled:
		print(message)

func _input(event: InputEvent) -> void:
	var rect = Rect2(global_position, size)
	
	# Handle touch events globally
	if event is InputEventScreenTouch:
		debug_print("Global touch event detected")
		if event.pressed and rect.has_point(event.position):
			touch_in_area = true
			debug_print("Touch started in scroll area")
		elif not event.pressed:
			touch_in_area = false
			debug_print("Touch ended")
	
	elif event is InputEventScreenDrag and touch_in_area:
		debug_print("Dragging in scroll area")
		# Only scroll if drag is within our area
		if rect.has_point(event.position):
			value -= event.relative.y * 0.5
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse wheel
	if event is InputEventMouseButton:
		var mouse_pos = get_global_mouse_position()
		var rect = Rect2(global_position, size)
		
		if rect.has_point(mouse_pos):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				debug_print("Mouse wheel up")
				value -= 1
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				debug_print("Mouse wheel down")
				value += 1
				accept_event()
