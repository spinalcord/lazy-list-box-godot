extends LazyListItem

@onready var button: Button = %Button

#region Lifecycle

func _ready() -> void:
	# Wire the button press to the abstract item_selected signal.
	# LazyListBox listens to this signal and bubbles it up as its own item_selected,
	# so the outside world never needs to know about individual item instances.
	button.pressed.connect(func() -> void: item_event.emit(item_index, item_data, LazyAction.Emit.ITEM_SELECTED))
#endregion

#region LazyListItem implementation
# Called by LazyListBox each time this pooled item is (re-)assigned to a data entry.
# Keep this fast — it runs for every visible item on every scroll step.
func configure_item(index: int, data: Variant) -> void:
	item_index = index
	item_data = data
	button.text = str(data)
#endregion

