class_name LazyListBox
extends Control

## A virtualized list of fixed-height items with pooled controls and keyboard navigation.
## Instantiate lazy_list_box.tscn and assign a scene extending [LazyListItem].

#region Signals and Alignment

## Alignment used by [method scroll_to_index].
enum ScrollAlignment { ALIGN_TOP, ALIGN_CENTER, ALIGN_BOTTOM, ALIGN_NEAREST }

## Align the item's top edge with the viewport's top edge.
const ALIGN_TOP = ScrollAlignment.ALIGN_TOP
## Center the item vertically in the viewport.
const ALIGN_CENTER = ScrollAlignment.ALIGN_CENTER
## Align the item's bottom edge with the viewport's bottom edge.
const ALIGN_BOTTOM = ScrollAlignment.ALIGN_BOTTOM
## Scroll the shortest distance needed to reveal the item.
const ALIGN_NEAREST = ScrollAlignment.ALIGN_NEAREST

## Emitted after pending data and the initial container layout have been applied.
signal fully_ready
## Requests more data. Supply the extended array via [method set_data].
signal load_more_requested()
## Emitted once per newly created pooled control, before data is assigned.
signal item_created(item: Control)
## Forwards an item's event with its current data index, data, and action.
signal item_event(index: int, data: Variant, action: LazyAction.Emit)
## Emitted when [method set_data] changes a populated list to an empty list.
signal list_became_empty
## Emitted when [method set_data] changes an empty list to a populated list.
signal list_became_populated

#endregion

#region Configuration

## Scene whose root extends [LazyListItem]. Use [method set_item_template] at runtime.
@export var item_template: PackedScene
## Hide the vertical scrollbar while keeping scrolling enabled.
@export var hide_scroll_bar: bool = false:
	set(value):
		hide_scroll_bar = value
		if is_node_ready():
			_update_scroll_mode()
## Reset the scroll position whenever [method set_data] is called.
@export var force_scroll_reset: bool = false

@export_group("Advanced/Network/Load More")
## Request more data when the visible range approaches the end of the list.
## E.g. YouTube: You scroll down => more videos appear
@export var load_more_enabled: bool = false:
	set(value):
		load_more_enabled = value
		_queue_load_more_check()
## Number of entries remaining below the visible range that triggers a request.
@export_range(0, 2147483647, 1) var load_more_threshold: int = 10:
	set(value):
		load_more_threshold = maxi(0, value)
		_queue_load_more_check()
## Set to false when the data source has no further entries.
@export var has_more_data: bool = true:
	set(value):
		has_more_data = value
		_queue_load_more_check()

#endregion

#region Input Actions

const INPUT_UP: StringName = &"ui_up"
const INPUT_DOWN: StringName = &"ui_down"
const INPUT_LEFT: StringName = &"ui_left"
const INPUT_RIGHT: StringName = &"ui_right"
const INPUT_HOME: StringName = &"ui_home"
const INPUT_END: StringName = &"ui_end"
const INPUT_PAGE_UP: StringName = &"ui_page_up"
const INPUT_PAGE_DOWN: StringName = &"ui_page_down"

#endregion

#region Runtime State

## Uniform item height in pixels, measured from the template or set manually.
var item_height: float = 0.0
## Current data array. Call [method set_data] after changing its size.
var data: Array = []
## Cached number of entries, updated by [method set_data].
var data_size: int = 0
## All pooled item controls, including currently unused controls.
var item_pool: Array[Control] = []
## Assigned controls in data order, including buffered rows around the viewport.
var active_items: Array[Control] = []
## Whether internal nodes and item measurements are ready to accept data directly.
var is_fully_initialized: bool = false
## Data queued by [method set_data] before initialization.
var pending_data: Array = []
## Whether a data update is waiting for initialization.
var has_pending_data: bool = false
## First visible data index, or zero for an empty list.
var current_scroll_index: int = 0
## Maximum scroll offset expressed as an item index, rounded up.
var max_scroll_index: int = 0
## Data index tracked by virtual focus, or -1 when no virtual focus is stored.
var virtual_focused_data_index: int = -1
## Whether the list currently tracks virtual item focus.
var has_virtual_focus: bool = false
## Keep virtual focus when the focused item control is recycled.
## Use [method set_focus_preservation] to also clear existing focus when disabling it.
var preserve_focus: bool = true
var _assigned: Dictionary = {}
var _updating: bool = false
var _parking_focus: bool = false
var _hover_update_pending: bool = false
var _load_more_ready: bool = false
var _load_more_check_pending: bool = false
var _load_more_request_locked: bool = false

## Internal container providing native scrolling and touch dragging.
var scroll_container: ScrollContainer
## Internal control providing the virtual content height and holding pooled items.
var content_container: Control
## Native vertical scrollbar used for the pixel scroll offset.
var scroll_bar: VScrollBar

#endregion

#region Initialization and Measurement

func _ready() -> void:
	if item_template == null:
		push_error("LazyListBox: Assign an item_template extending LazyListItem. If one is assigned, check resource loading errors and rescan the project in the editor.")
		return
	_resolve_internal_nodes()
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
	_load_more_ready = true
	_queue_load_more_check()

func _resolve_internal_nodes() -> void:
	var created := false
	scroll_container = get_node_or_null("ScrollContainer") as ScrollContainer
	if scroll_container == null:
		scroll_container = ScrollContainer.new()
		scroll_container.name = &"ScrollContainer"
		scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(scroll_container)
		scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scroll_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		scroll_container.grow_vertical = Control.GROW_DIRECTION_BOTH
		created = true
	content_container = scroll_container.get_node_or_null("Content") as Control
	if content_container == null:
		content_container = Control.new()
		content_container.name = &"Content"
		content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_container.mouse_filter = Control.MOUSE_FILTER_PASS
		scroll_container.add_child(content_container)
		created = true
	scroll_bar = scroll_container.get_v_scroll_bar()
	if created:
		push_warning("LazyListBox: Internal nodes were created at runtime. Prefer instantiating res://addons/lazy_list_box/lazy_list_box.tscn instead of using Add Child Node or LazyListBox.new().")

func _update_scroll_mode() -> void:
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if hide_scroll_bar else ScrollContainer.SCROLL_MODE_AUTO

func _separation() -> float:
	return maxf(0.0, get_theme_constant(&"separation", &"VBoxContainer"))

func _stride() -> float:
	return item_height + _separation()

func _viewport_height() -> float:
	var panel := scroll_container.get_theme_stylebox(&"panel")
	return maxf(0.0, scroll_container.size.y - panel.get_margin(SIDE_TOP) - panel.get_margin(SIDE_BOTTOM))

func _content_height() -> float:
	return maxf(0.0, data_size * _stride() - _separation())

func _measure_height() -> void:
	assert(item_template != null, "Assign an item_template extending LazyListItem.")
	var sample := item_template.instantiate() as LazyListItem
	assert(sample != null, "The template must extend LazyListItem.")
	sample.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	content_container.add_child(sample)
	sample.size.x = content_container.size.x
	item_height = maxf(1.0, sample.get_combined_minimum_size().y)
	content_container.remove_child(sample)
	sample.queue_free()

#endregion

#region Data and Item Template

## Replace the data array and reconfigure assigned items.
## Before initialization, queue a shallow copy of [param new_data].
## After initialization, retain the supplied array and reset scrolling only if
## [member force_scroll_reset] is enabled. A size change unlocks load-more requests.
func set_data(new_data: Array) -> void:
	if not is_fully_initialized:
		pending_data = new_data.duplicate()
		has_pending_data = true
		return
	var old_size := data_size
	data = new_data
	data_size = data.size()
	if old_size != data_size:
		_load_more_request_locked = false
	if virtual_focused_data_index >= data_size:
		_clear_virtual_focus()
	_layout(force_scroll_reset)
	_update_items(true)
	if old_size > 0 and data_size == 0:
		list_became_empty.emit()
	elif old_size == 0 and data_size > 0:
		list_became_populated.emit()

## Replace the item scene, rebuild the pool, and remeasure the uniform item height.
## The root of [param template] must extend [LazyListItem].
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

#endregion

#region Layout and Item Pool

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
	_updating = false
	_update_items()

## Return the inclusive first and last visible data indices, including partial rows.
## Return [code]Vector2i(0, -1)[/code] for empty data or a viewport without height.
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
	var capacity := mini(data_size, ceili(_viewport_height() / _stride()) + 3)
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
	_queue_hover_update()
	_queue_load_more_check()

#endregion

#region Load More

## Unlock load-more requests and schedule another threshold check.
## Use this to retry after a failed request or a response that did not change the data size.
## The application manages loading and supplies the extended array via [method set_data].
func reset_load_more_request() -> void:
	_load_more_request_locked = false
	_queue_load_more_check()

func _queue_load_more_check() -> void:
	if not _load_more_ready or not is_inside_tree() or _load_more_check_pending:
		return
	if not load_more_enabled or not has_more_data or _load_more_request_locked:
		return
	_load_more_check_pending = true
	# Native container sorting must settle before inspecting partial visible rows.
	get_tree().process_frame.connect(_check_load_more, CONNECT_DEFERRED | CONNECT_ONE_SHOT)

func _check_load_more() -> void:
	_load_more_check_pending = false
	if not is_inside_tree() or not _load_more_ready or _updating:
		return
	if not load_more_enabled or not has_more_data or _load_more_request_locked:
		return
	if _viewport_height() <= 0.0 or scroll_container.size.x <= 0.0:
		return
	var visible_range := get_visible_range()
	if data_size > 0 and (visible_range.y < visible_range.x or data_size - 1 - visible_range.y > load_more_threshold):
		return
	# Lock before emitting: a synchronous handler may set_data() and queue again.
	_load_more_request_locked = true
	load_more_requested.emit()

#endregion

#region Pointer Hover

func _queue_hover_update() -> void:
	if _hover_update_pending:
		return
	_hover_update_pending = true
	# Wait for native scrolling and deferred container layout to settle.
	get_tree().process_frame.connect(_update_hover, CONNECT_DEFERRED | CONNECT_ONE_SHOT)

func _update_hover() -> void:
	_hover_update_pending = false
	if is_inside_tree():
		get_viewport().update_mouse_cursor_state()

#endregion

#region Refresh and Scrolling

## Update the layout and reconfigure all assigned items from the current data.
func refresh() -> void:
	if is_fully_initialized:
		_layout()
		_update_items(true)

## Reconfigure the assigned item at [param index] from the current data.
## Do nothing before initialization or if the index is invalid or has no assigned control.
func refresh_item(index: int) -> void:
	if not is_fully_initialized or index < 0 or index >= data_size:
		return
	var item: LazyListItem = _assigned.get(index)
	if item != null:
		item.item_data = data[index]
		item.configure_item(index, data[index])

## Scroll to [param index], clamped to the data bounds, using [param alignment].
## Do nothing before initialization, for empty data, or without viewport height.
func scroll_to_index(index: int, alignment: ScrollAlignment = ALIGN_TOP) -> void:
	if not is_fully_initialized or data_size == 0:
		return
	var viewport_height := _viewport_height()
	if viewport_height <= 0.0:
		return
	var top := clampi(index, 0, data_size - 1) * _stride()
	var bottom := top + item_height
	var target := top
	match alignment:
		ALIGN_CENTER:
			target = top + (item_height - viewport_height) / 2.0
		ALIGN_BOTTOM:
			target = bottom - viewport_height
		ALIGN_NEAREST:
			var current := scroll_bar.value
			var viewport_bottom := current + viewport_height
			# Keep fully visible rows, and tall rows covering the viewport, in place.
			if (top >= current and bottom <= viewport_bottom) or (top <= current and bottom >= viewport_bottom):
				return
			var bottom_target := bottom - viewport_height
			if absf(bottom_target - current) < absf(top - current):
				target = bottom_target
	scroll_bar.value = clampf(target, 0.0, maxf(0.0, _content_height() - viewport_height))

## Scroll to the maximum pixel offset once initialized.
func scroll_to_end() -> void:
	if is_fully_initialized:
		scroll_bar.value = maxf(0.0, _content_height() - _viewport_height())

#endregion

#region Focus and Keyboard Navigation

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

## Reveal [param index] and focus its first focusable control, if available.
## Track the data index as virtual focus. Ignore indices outside the data bounds.
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
	if event.is_action_pressed(INPUT_DOWN, true):
		if index == data_size - 1:
			neighbor = focus_neighbor_bottom
		target += 1
	elif event.is_action_pressed(INPUT_UP, true):
		if index == 0:
			neighbor = focus_neighbor_top
		target -= 1
	elif event.is_action_pressed(INPUT_LEFT, true):
		neighbor = focus_neighbor_left
	elif event.is_action_pressed(INPUT_RIGHT, true):
		neighbor = focus_neighbor_right
	elif event.is_action_pressed(INPUT_HOME, true):
		target = 0
	elif event.is_action_pressed(INPUT_END, true):
		target = data_size - 1
	elif event.is_action_pressed(INPUT_PAGE_DOWN, true):
		target += maxi(1, int(_viewport_height() / _stride()))
	elif event.is_action_pressed(INPUT_PAGE_UP, true):
		target -= maxi(1, int(_viewport_height() / _stride()))
	else:
		return
	if not neighbor.is_empty():
		var control := get_node_or_null(neighbor) as Control
		if control and control.is_visible_in_tree() and control.can_process():
			control.grab_focus()
	elif target == index and (event.is_action_pressed(INPUT_LEFT, true) or event.is_action_pressed(INPUT_RIGHT, true)):
		return
	else:
		focus_item_at_data_index(clampi(target, 0, data_size - 1))
	get_viewport().set_input_as_handled()

## Set whether virtual focus survives item recycling; clear it when disabled.
func set_focus_preservation(enabled: bool) -> void:
	preserve_focus = enabled
	if not enabled:
		_clear_virtual_focus()

## Return the virtually focused data index, or -1 when no virtual focus is stored.
func get_virtual_focused_index() -> int:
	return virtual_focused_data_index if has_virtual_focus else -1

## Focus the item at the first visible data index.
func grab_initial_focus() -> void:
	focus_item_at_data_index(current_scroll_index)

## Return whether virtual item focus is currently stored.
func is_list_focused() -> bool:
	return has_virtual_focus

#endregion

#region Initialization Status and Item Height

## Return whether data can be applied immediately instead of queued.
## The [signal fully_ready] signal additionally waits for the initial container layout.
func is_ready_for_data() -> bool:
	return is_fully_initialized

## Return a human-readable description of the current initialization state.
func get_initialization_status() -> String:
	if is_fully_initialized:
		return "Fully Initialized"
	return "Initializing with Pending Data" if has_pending_data else "Initializing"

## Set the uniform item height in pixels, clamped to at least one, and update layout.
func set_manual_item_height(height: float) -> void:
	item_height = maxf(1.0, height)
	_layout()

## Return the current uniform item height in pixels.
func get_item_height() -> float:
	return item_height

#endregion
