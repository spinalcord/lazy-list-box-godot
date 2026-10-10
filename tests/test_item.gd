extends LazyListItem
var configurations: int = 0
func configure_item(index: int, entry: Variant) -> void:
	configurations += 1
	item_index = index
	item_data = entry
	$Button.text = str(entry)
func _ready() -> void:
	$Button.pressed.connect(func(): item_event.emit(item_index, item_data, LazyAction.Emit.ITEM_SELECTED))
