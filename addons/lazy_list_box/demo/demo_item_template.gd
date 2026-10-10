extends LazyListItem

@onready var button: Button = %Button

#region Lifecycle

func _ready() -> void:
	# Wire the button press to the abstract item_event signal.
	# LazyListBox listens to this signal and bubbles it up as its own item_event,
	# so the outside world never needs to know about individual item instances.
	button.pressed.connect(func() -> void: item_event.emit(item_index, item_data, LazyAction.Emit.ITEM_SELECTED))
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			item_event.emit(item_index, item_data, LazyAction.Emit.RIGHT_CLICK)
	)
#endregion

#region LazyListItem implementation
# Called by LazyListBox each time this pooled item is (re-)assigned to a data entry.
# Runs on assignment or refresh, not on every pixel of scrolling.
func configure_item(index: int, data: Variant) -> void:
	item_index = index
	item_data = data
	button.text = str(data)
#endregion
