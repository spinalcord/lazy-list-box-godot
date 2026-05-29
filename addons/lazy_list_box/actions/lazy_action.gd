class_name LazyAction

"""
1. Use a LazyAction in your `Item Template`. Example:

```gd
button.pressed.connect(func() -> void: item_event.emit(item_index, item_data, LazyAction.Emit.ITEM_SELECTED))
```
2. then you can use the event in the same scope (where your LazyListBox is e.g. in fake data example)

```gd
func _one_item_event(index: int, data: Variant, action: LazyAction.Emit) -> void:
	if action is LazyAction.Emit.ITEM_SELECTED:
		output_label.text = "Button Pressed: %s | data: %s" % [index, data]
	elif action is LazyAction.Emit.RIGHT_CLICK:
		output_label.text = "Right Click: %s | data: %s" % [index, data]
```

3. `Emit` has a list of common events, add your own if needed
"""

enum Emit {
	# Mouse / Click
	ITEM_SELECTED,      # primary click / confirm
	LEFT_CLICK,        # context menu
	RIGHT_CLICK,        # context menu
	DOUBLE_CLICK,       # open / expand
	MIDDLE_CLICK,       # e.g. close tab / remove

	# Hover / Focus
	HOVERED,            # mouse entered item
	UNHOVERED,          # mouse exited item
	FOCUSED,            
	UNFOCUSED,          

	# Keyboard
	CONFIRMED,          # Enter key
	DELETED,            # Delete / Backspace key

	# Toggle
	FAVORITED,
	UNFAVORITED,
	MARKED,                 # flagged / bookmarked
	UNMARKED,
	CHECKED,
	UNCHECKED,
	EXPANDED,           # tree node opened
	COLLAPSED,          # tree node closed

	# Inline editing
	EDIT_STARTED,
	EDIT_CONFIRMED,
	EDIT_CANCELLED,

	# Reordering
	MOVE_UP,
	MOVE_DOWN,
	
	# Drag & Drop
	DRAG_STARTED,
	DROPPED_ON,         # another item was dropped onto this one
}
