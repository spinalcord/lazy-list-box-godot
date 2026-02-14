extends VScrollBar

const DEBUG_WHEEL_UP: String = "Mouse wheel up"
const DEBUG_WHEEL_DOWN: String = "Mouse wheel down"
const DEBUG_TOUCH_STARTED: String = "Touch started in scroll area"
const DEBUG_TOUCH_ENDED: String = "Touch ended"

# Debug toggle in the inspector
@export var debug_enabled: bool = false

var touch_in_area: bool = false


func _ready() -> void:
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE # All clicks pass through


func _input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch:
		return

	_debug_print("Global touch event detected")
	var rect: Rect2 = Rect2(global_position, size)
	touch_in_area = event.pressed and rect.has_point(event.position)

	_debug_print(DEBUG_TOUCH_STARTED) if touch_in_area else _debug_print(DEBUG_TOUCH_ENDED)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	#Handle mouse wheel
	var rect: Rect2 = Rect2(global_position, size)
	if not rect.has_point(get_global_mouse_position()):
		return

	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			value -= 1.0
			_debug_print(DEBUG_WHEEL_UP)
			return accept_event()
		MOUSE_BUTTON_WHEEL_DOWN:
			value += 1.0
			_debug_print(DEBUG_WHEEL_DOWN)
			return accept_event()


func _debug_print(message: String) -> void:
	if debug_enabled:
		print(message)
