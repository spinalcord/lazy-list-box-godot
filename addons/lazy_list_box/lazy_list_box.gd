class_name LazyListBox
extends Control

signal fully_ready
signal item_created(item: Control)
signal item_event(index: int, data: Variant, action: LazyAction.Emit)
signal list_became_empty
signal list_became_populated

@export var item_template: PackedScene
@export var auto_calculate_visible_count: bool = true
## Minimum pool capacity in manual mode; the viewport can require more rows.
@export var visible_item_count: int = 10
@export var hide_scroll_bar: bool = false:
	set(value):
		hide_scroll_bar = value
		if is_node_ready():
			_update_scroll_mode()
@export var force_scroll_reset: bool = false

var item_height: float = 0.0
var data: Array = []
var data_size: int = 0
var item_pool: Array[Control] = []
var active_items: Array[Control] = []
var is_fully_initialized: bool = false
var pending_data: Array = []
var has_pending_data: bool = false
var current_scroll_index: int = 0
var max_scroll_index: int = 0
var virtual_focused_data_index: int = -1
var has_virtual_focus: bool = false
var preserve_focus: bool = true
var _assigned: Dictionary = {}
var _updating: bool = false
var _parking_focus: bool = false

@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var content_container: Control = %Content
@onready var scroll_bar: VScrollBar = scroll_container.get_v_scroll_bar()

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_update_scroll_mode()
	scroll_bar.value_changed.connect(func(_value: float): _update_items())
	scroll_container.resized.connect(_layout)
	content_container.resized.connect(_update_items)
	theme_changed.connect(_layout, CONNECT_DEFERRED)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	focus_entered.connect(func():
		if not _parking_focus and not has_virtual_focus:
			grab_initial_focus()
	)
	_measure_height()
	is_fully_initialized = true
	if has_pending_data:
		var initial_data := pending_data
		pending_data = []
		has_pending_data = false
		set_data(initial_data)
	else:
		_layout()
	# Let the native container finish its first layout before notifying clients.
	await get_tree().process_frame
	_layout()
	fully_ready.emit()

func _update_scroll_mode() -> void:
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if hide_scroll_bar else ScrollContainer.SCROLL_MODE_AUTO

func _separation() -> float:
	return maxf(0.0, get_theme_constant("separation", "VBoxContainer"))

func _stride() -> float:
	return item_height + _separation()

func _viewport_height() -> float:
	var panel := scroll_container.get_theme_stylebox("panel")
	return maxf(0.0, scroll_container.size.y - panel.get_margin(SIDE_TOP) - panel.get_margin(SIDE_BOTTOM))

func _content_height() -> float:
	return maxf(0.0, data_size * _stride() - _separation())

func _measure_height() -> void:
	assert(item_template != null, "Assign an item_template extending LazyListItem.")
	var sample := item_template.instantiate() as LazyListItem
	assert(sample != null, "The template must extend LazyListItem.")
	content_container.add_child(sample)
	sample.size.x = content_container.size.x
	item_height = maxf(1.0, sample.get_combined_minimum_size().y)
	content_container.remove_child(sample)
	sample.queue_free()

func set_data(new_data: Array) -> void:
	if not is_fully_initialized:
		pending_data = new_data.duplicate()
		has_pending_data = true
		return
	var old_size := data_size
	data = new_data
	data_size = data.size()
	if virtual_focused_data_index >= data_size:
		_clear_virtual_focus()
	_layout(force_scroll_reset)
	_update_items(true)
	if old_size > 0 and data_size == 0:
		list_became_empty.emit()
	elif old_size == 0 and data_size > 0:
		list_became_populated.emit()

func set_item_template(template: PackedScene) -> void:
	item_template = template
	if not is_fully_initialized:
		return
	_park_focus()
	_assigned.clear()
	active_items.clear()
	for item in item_pool:
		content_container.remove_child(item)
		item.queue_free()
	item_pool.clear()
	_measure_height()
	_layout()

func _layout(reset: bool = false) -> void:
	if not is_fully_initialized or _updating:
		return
	_updating = true
	var pixel_position := 0.0 if reset else scroll_bar.value
	content_container.custom_minimum_size.y = _content_height()
	# Update immediately too, so public scroll methods work before deferred sorting.
	scroll_bar.max_value = maxf(_content_height(), _viewport_height())
	scroll_bar.page = _viewport_height()
	scroll_bar.value = clampf(pixel_position, 0.0, maxf(0.0, _content_height() - _viewport_height()))
	max_scroll_index = maxi(0, ceili(maxf(0.0, _content_height() - _viewport_height()) / _stride()))
	if auto_calculate_visible_count:
		visible_item_count = maxi(1, ceili(_viewport_height() / _stride()))
	_updating = false
	_update_items()

func get_visible_range() -> Vector2i:
	if data_size == 0 or _viewport_height() <= 0.0:
		return Vector2i(0, -1)
	var top := scroll_bar.value
	var first := int(floor(top / _stride()))
	if first * _stride() + item_height <= top:
		first += 1
	var last := mini(data_size - 1, ceili((top + _viewport_height()) / _stride()) - 1)
	return Vector2i(first, last)

func _create_item() -> Control:
	var item := item_template.instantiate() as LazyListItem
	item.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	item.visible = false
	content_container.add_child(item)
	_prepare_input(item)
	item.item_event.connect(func(index: int, entry: Variant, action: LazyAction.Emit): item_event.emit(index, entry, action))
	item_pool.append(item)
	item_created.emit(item)
	return item

func _prepare_input(node: Node) -> void:
	# PASS lets native ScrollContainer receive drags through nested buttons/layouts.
	if node is Control and node.mouse_filter == Control.MOUSE_FILTER_STOP:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	if node is BaseButton:
		node.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for child in node.get_children():
		_prepare_input(child)

func _update_items(reconfigure: bool = false) -> void:
	if not is_fully_initialized or _updating:
		return
	_updating = true
	var visible_range := get_visible_range()
	current_scroll_index = maxi(0, visible_range.x)
	var first := maxi(0, visible_range.x - 1)
	var last := mini(data_size - 1, visible_range.y + 1)
	var capacity := mini(data_size, maxi(ceili(_viewport_height() / _stride()) + 3, 0 if auto_calculate_visible_count else visible_item_count))
	for index: int in _assigned.keys():
		if index < first or index > last:
			var item: Control = _assigned[index]
			_park_focus(item)
			item.hide()
			_assigned.erase(index)
	while item_pool.size() < capacity:
		_create_item()
	var available: Array[Control] = []
	for item in item_pool:
		if not item.visible:
			available.append(item)
	for index in range(first, last + 1):
		var fresh := not _assigned.has(index)
		if fresh:
			_assigned[index] = available.pop_back()
		var item: LazyListItem = _assigned[index]
		if fresh or reconfigure:
			item.item_index = index
			item.item_data = data[index]
			item.configure_item(index, data[index])
		item.position = Vector2(0, index * _stride())
		item.size = Vector2(content_container.size.x, item_height)
		item.show()
	while item_pool.size() > capacity and not available.is_empty():
		var item: Control = available.pop_back()
		item_pool.erase(item)
		content_container.remove_child(item)
		item.queue_free()
	active_items.clear()
	for index in range(first, last + 1):
		active_items.append(_assigned[index])
	_updating = false

func refresh() -> void:
	if is_fully_initialized:
		_layout()
		_update_items(true)

func scroll_to_index(index: int) -> void:
	if is_fully_initialized:
		scroll_bar.value = clampi(index, 0, maxi(0, data_size - 1)) * _stride()

func scroll_to_end() -> void:
	if is_fully_initialized:
		scroll_bar.value = maxf(0.0, _content_height() - _viewport_height())

func _park_focus(item: Control = null) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner and ((item and (owner == item or item.is_ancestor_of(owner))) or (not item and is_ancestor_of(owner))):
		_parking_focus = true
		grab_focus()
		_parking_focus = false
		if not preserve_focus:
			_clear_virtual_focus()

func _on_focus_changed(owner: Control) -> void:
	if owner == self:
		return
	for index: int in _assigned:
		var item: Control = _assigned[index]
		if owner == item or (owner and item.is_ancestor_of(owner)):
			virtual_focused_data_index = index
			has_virtual_focus = true
			return
	if owner and not is_ancestor_of(owner):
		_clear_virtual_focus()

func _clear_virtual_focus() -> void:
	has_virtual_focus = false
	virtual_focused_data_index = -1

func focus_item_at_data_index(index: int) -> void:
	if index < 0 or index >= data_size:
		return
	var top := index * _stride()
	if top < scroll_bar.value:
		scroll_bar.value = top
	elif top + item_height > scroll_bar.value + _viewport_height():
		scroll_bar.value = top + item_height - _viewport_height()
	virtual_focused_data_index = index
	has_virtual_focus = true
	if _assigned.has(index):
		var item: Control = _assigned[index]
		var target := _focus_target(item)
		if target:
			target.grab_focus()

func _focus_target(node: Control) -> Control:
	if node.focus_mode != Control.FOCUS_NONE:
		return node
	for child in node.get_children():
		if child is Control:
			var target := _focus_target(child)
			if target:
				return target
	return null

func _input(event: InputEvent) -> void:
	var owner := get_viewport().gui_get_focus_owner()
	if owner != self and (not owner or not is_ancestor_of(owner)):
		return
	var index := virtual_focused_data_index if has_virtual_focus else current_scroll_index
	var target := index
	var neighbor := NodePath()
	if event.is_action_pressed("ui_down", true):
		if index == data_size - 1:
			neighbor = focus_neighbor_bottom
		target += 1
	elif event.is_action_pressed("ui_up", true):
		if index == 0:
			neighbor = focus_neighbor_top
		target -= 1
	elif event.is_action_pressed("ui_left", true):
		neighbor = focus_neighbor_left
	elif event.is_action_pressed("ui_right", true):
		neighbor = focus_neighbor_right
	elif event.is_action_pressed("ui_home", true):
		target = 0
	elif event.is_action_pressed("ui_end", true):
		target = data_size - 1
	elif event.is_action_pressed("ui_page_down", true):
		target += maxi(1, int(_viewport_height() / _stride()))
	elif event.is_action_pressed("ui_page_up", true):
		target -= maxi(1, int(_viewport_height() / _stride()))
	else:
		return
	if not neighbor.is_empty():
		var control := get_node_or_null(neighbor) as Control
		if control and control.is_visible_in_tree() and control.can_process():
			control.grab_focus()
	elif target == index and (event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true)):
		return
	else:
		focus_item_at_data_index(clampi(target, 0, data_size - 1))
	get_viewport().set_input_as_handled()

func set_focus_preservation(enabled: bool) -> void:
	preserve_focus = enabled
	if not enabled:
		_clear_virtual_focus()

func get_virtual_focused_index() -> int:
	return virtual_focused_data_index if has_virtual_focus else -1

func grab_initial_focus() -> void:
	focus_item_at_data_index(current_scroll_index)

func is_list_focused() -> bool:
	return has_virtual_focus

func is_ready_for_data() -> bool:
	return is_fully_initialized

func get_initialization_status() -> String:
	if is_fully_initialized:
		return "Fully Initialized"
	return "Initializing with Pending Data" if has_pending_data else "Initializing"

func set_auto_calculate_visible_count(enabled: bool) -> void:
	auto_calculate_visible_count = enabled
	_layout()

func set_manual_item_height(height: float) -> void:
	item_height = maxf(1.0, height)
	_layout()

func get_item_height() -> float:
	return item_height

func get_calculated_visible_count() -> int:
	return visible_item_count
