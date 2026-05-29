extends Node

@onready var lazy_list: LazyListBox = %LazyListBox
@onready var output_label: Label = %OutputLabel

#region Lifecycle

func _ready() -> void:
	_setup_data()
	_setup_events()

#endregion

#region Setup

func _setup_data() -> void:
	# Fill the list with 500 dummy entries.
	# In a real project this would be your actual data array (resources, dictionaries, etc.).
	var test_data: Array = []
	for i: int in range(500):
		test_data.append(i)

	lazy_list.set_data(test_data)

func _setup_events() -> void:
	# Event bubbling in action:
	# The button inside each item template emits item_selected.
	# LazyListBox catches that signal and re-emits it here,
	# so we only need ONE connection for the entire list — no matter how many items exist.
	# Note: signals are wired only to the small pool of visible items, not to all 500 data entries.
	# When the pool is cleared (e.g. on template change), those nodes are freed and their
	# connections vanish with them => no manual cleanup needed.
	lazy_list.item_event.connect(_one_item_event)

#endregion

#region Event handlers

func _one_item_event(index: int, data: Variant, action: LazyAction.Emit) -> void:
	if action == LazyAction.Emit.ITEM_SELECTED:
		output_label.text = "Button Pressed: %s | data: %s" % [index, data]
	elif action == LazyAction.Emit.RIGHT_CLICK:
		output_label.text = "Right Click: %s | data: %s" % [index, data]

#endregion

