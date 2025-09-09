extends Control
class_name LazyListBox

# Configuration properties
@export var item_template: PackedScene
@export var debug_mode: bool = false  # Enable/disable debug prints

# NEW: Item height for intelligent calculation
var item_height: float = 0.0
## Calculates automatically the ammount of items that fits in the container
@export var auto_calculate_visible_count: bool = true
## Will be calculated automatically if `auto_calculate_visible_count` is false
@export var visible_item_count: int = 10  

# Internal references
@onready var scroll_bar: VScrollBar = %VScrollBar
@onready var overlay_scroll_bar: VScrollBar = %VOverlayScrollBar
@onready var content_container: VBoxContainer = %VBoxContainer
@onready var scroll_container: ScrollContainer = %ScrollContainer

# Data management
var data: Array = []
var item_pool: Array[Control] = []
var active_items: Array[Control] = []

# OPTIMIZATION: HashSet for O(1) lookup instead of O(n) Array.has()
var active_items_set: Dictionary = {}  # key = item, value = true

# Scroll tracking
var current_scroll_index: int = 0
var max_scroll_index: int = 0

# Synchronized scroll management - prevent recursive updates
var is_updating_scrollbars: bool = false

# Enhanced focus management
var virtual_focused_data_index: int = -1
var has_virtual_focus: bool = false
var current_real_focused_item: Control = null
var preserve_focus: bool = true

# Focus monitoring - optimized
var focus_check_timer: Timer
var last_known_focused_owner: Control = null

# Optimized cooldown system
var cooldown_timer: float = 0.0
const COOLDOWN_TIME: float = 0.1

# Cache frequently used values
var data_size: int = 0
var viewport_cache: Viewport = null

# OPTIMIZATION: Method caching to avoid repeated has_method() calls
var method_cache: Dictionary = {}  # key: item_script/class, value: method_name

func _ready():
	assert(item_template != null, "Item Template is missing.")
	
	# Create a temporary instance to check methods
	var temp_instance = item_template.instantiate()
	# Check if required methods exist
	assert(temp_instance.has_method("configure_item"), "Your Item Template needs `func configure_item(index: int, data):`")
	assert(temp_instance.has_method("set_data"), "Your Item Template needs `func set_data(data):`")
	
	# Clean up the temporary instance
	temp_instance.queue_free()
	
	# Cache viewport reference
	viewport_cache = get_viewport()
	
	# Setup focus monitoring timer with longer interval for better performance
	_setup_focus_monitoring()
	
	# Connect scroll bar signals for synchronized scrolling
	_setup_synchronized_scrollbars()
	
	# Connect resize signal for intelligent visible count calculation
	resized.connect(_on_control_resized)
	
	# Initialize the list
	_setup_initial_state()

func _on_control_resized():
	"""Handle control resize to recalculate visible_item_count"""
	if auto_calculate_visible_count:
		_calculate_visible_item_count()

func _calculate_visible_item_count():
	"""Calculate visible_item_count based on control size and item height"""
	if item_height <= 0.0:
		_determine_item_height()
	
	if item_height > 0.0:
		var available_height = size.y
		var new_visible_count = max(1, int(available_height / item_height))
		
		if new_visible_count != visible_item_count:
			visible_item_count = new_visible_count
			# Recreate item pool with new size
			_create_item_pool()
			_update_scroll_range()
			_refresh_visible_items()

func _determine_item_height():
	"""Determine item height by creating a temporary item IN THE ACTUAL CONTAINER"""
	if not item_template:
		return
	
	var temp_item = item_template.instantiate()
	content_container.add_child(temp_item)  # <- In den VBoxContainer!
	
	# Configure with dummy data
	if data.size() > 0:
		_configure_item(temp_item, 0, data[0])
	
	# Wait for proper layout
	temp_item.force_update_transform()
	await get_tree().process_frame
	await get_tree().process_frame  # Manchmal braucht es 2 Frames
	
	item_height = temp_item.size.y
	
	temp_item.queue_free()
	
	if item_height <= 0.0:
		item_height = 32.0

func _setup_synchronized_scrollbars():
	"""Setup synchronized scrollbar connections"""
	if scroll_bar:
		scroll_bar.value_changed.connect(_on_main_scroll_changed)
		_configure_scrollbar(scroll_bar)
	
	if overlay_scroll_bar:
		overlay_scroll_bar.value_changed.connect(_on_overlay_scroll_changed)
		_configure_scrollbar(overlay_scroll_bar)

func _configure_scrollbar(scrollbar: VScrollBar):
	"""Configure a scrollbar with consistent settings"""
	scrollbar.step = 1.0
	scrollbar.allow_greater = false
	scrollbar.allow_lesser = false

func _on_main_scroll_changed(value: float):
	"""Handle main scroll bar value changes"""
	if is_updating_scrollbars:
		return
	
	_handle_scroll_change(value, scroll_bar)

func _on_overlay_scroll_changed(value: float):
	"""Handle overlay scroll bar value changes"""
	if is_updating_scrollbars:
		return
	
	_handle_scroll_change(value, overlay_scroll_bar)

func _handle_scroll_change(value: float, source_scrollbar: VScrollBar):
	"""Handle scroll changes and synchronize both scrollbars"""
	var new_scroll_index = roundi(value)  # Use roundi for better performance
	new_scroll_index = clampi(new_scroll_index, 0, max_scroll_index)  # Use clampi for integers
	
	if new_scroll_index != current_scroll_index:
		current_scroll_index = new_scroll_index
		
		# Synchronize the other scrollbar without triggering events
		_sync_scrollbars(value, source_scrollbar)
		
		# Refresh visible items
		_refresh_visible_items()

func _sync_scrollbars(value: float, source_scrollbar: VScrollBar):
	"""Synchronize both scrollbars to the same value without triggering events"""
	is_updating_scrollbars = true
	
	# Update the scrollbar that wasn't the source of the change
	if source_scrollbar == scroll_bar and overlay_scroll_bar:
		overlay_scroll_bar.value = value
	elif source_scrollbar == overlay_scroll_bar and scroll_bar:
		scroll_bar.value = value
	
	is_updating_scrollbars = false

func _setup_focus_monitoring():
	"""Setup timer for monitoring external focus changes - optimized interval"""
	focus_check_timer = Timer.new()
	focus_check_timer.wait_time = 0.2  # Reduced frequency for better performance
	focus_check_timer.timeout.connect(_check_external_focus_loss)
	focus_check_timer.one_shot = false
	add_child(focus_check_timer)

func _check_external_focus_loss():
	"""Check if focus has moved outside the LazyListBox - optimized with HashSet"""
	if not has_virtual_focus:
		focus_check_timer.stop()  # Stop monitoring when no virtual focus
		return
	
	var current_focused = viewport_cache.gui_get_focus_owner()
	
	# Early exit if no focus change
	if current_focused == last_known_focused_owner:
		return
	
	last_known_focused_owner = current_focused
	
	# OPTIMIZATION: O(1) lookup instead of O(n) Array.has()
	if current_focused and active_items_set.has(current_focused):
		current_real_focused_item = current_focused
		return
	
	# If focus moved outside our list, clear virtual focus
	if current_focused != null and not _is_descendant_of_listbox(current_focused):
		_clear_virtual_focus()

func _is_descendant_of_listbox(node: Node) -> bool:
	"""Check if a node is a descendant of this LazyListBox - optimized with engine method"""
	if not node:
		return false
	# OPTIMIZATION: Use engine-optimized is_ancestor_of() instead of manual loop
	return self.is_ancestor_of(node)

func _input(event):
	if not preserve_focus or cooldown_timer > 0.0:
		return

	if event.is_action("ui_down"):
		_handle_arrow_down()
		accept_event()
		cooldown_timer = COOLDOWN_TIME
		
	elif event.is_action("ui_up"):
		_handle_arrow_up()
		accept_event()
		cooldown_timer = COOLDOWN_TIME

func _process(delta):
	# Optimized cooldown system - only process when needed
	if cooldown_timer > 0.0:
		cooldown_timer -= delta

func _handle_arrow_down():
	"""Handle down arrow with virtual focus logic"""
	# If no virtual focus exists, establish it on current item or first visible
	if not has_virtual_focus:
		var current_focused = _get_currently_focused_item()
		if current_focused:
			_establish_virtual_focus_from_item(current_focused)
		else:
			_establish_virtual_focus_at_index(current_scroll_index)
		return
	
	# Move virtual focus down
	var next_virtual_index = virtual_focused_data_index + 1
	if next_virtual_index >= data_size:
		return  # Already at end - use cached size
	
	_set_virtual_focus(next_virtual_index)
	
	# Handle scrolling if needed
	var max_visible_index = current_scroll_index + visible_item_count
	if next_virtual_index >= max_visible_index:
		# Need to scroll down to show the virtually focused item
		scroll_to_index(current_scroll_index + 1)
	
	# Apply real focus if item is visible
	_apply_real_focus_if_visible()

func _handle_arrow_up():
	"""Handle up arrow with virtual focus logic"""
	# If no virtual focus exists, establish it on current item or last visible
	if not has_virtual_focus:
		var current_focused = _get_currently_focused_item()
		if current_focused:
			_establish_virtual_focus_from_item(current_focused)
		else:
			var visible_range = get_visible_range()
			_establish_virtual_focus_at_index(visible_range.y)
		return
	
	# Move virtual focus up
	var prev_virtual_index = virtual_focused_data_index - 1
	if prev_virtual_index < 0:
		return  # Already at beginning
	
	_set_virtual_focus(prev_virtual_index)
	
	# Handle scrolling if needed
	if prev_virtual_index < current_scroll_index:
		# Need to scroll up to show the virtually focused item
		scroll_to_index(current_scroll_index - 1)
	
	# Apply real focus if item is visible
	_apply_real_focus_if_visible()

func _establish_virtual_focus_from_item(item: Control):
	"""Establish virtual focus based on currently focused item"""
	var data_index = _get_data_index_for_item(item)
	if data_index != -1:
		_set_virtual_focus(data_index)

func _establish_virtual_focus_at_index(data_index: int):
	"""Establish virtual focus at specific data index"""
	if data_index >= 0 and data_index < data_size:  # Use cached size
		_set_virtual_focus(data_index)
		_apply_real_focus_if_visible()

func _set_virtual_focus(data_index: int):
	"""Set virtual focus to specific data index"""
	virtual_focused_data_index = data_index
	has_virtual_focus = true
	
	# Start monitoring for external focus loss
	if not focus_check_timer.is_stopped():
		focus_check_timer.stop()
	focus_check_timer.start()

func _clear_virtual_focus():
	"""Clear virtual focus state"""
	virtual_focused_data_index = -1
	has_virtual_focus = false
	current_real_focused_item = null
	
	# Stop focus monitoring
	if not focus_check_timer.is_stopped():
		focus_check_timer.stop()

func _apply_real_focus_if_visible():
	"""Apply real UI focus if virtually focused item is visible - optimized"""
	if not has_virtual_focus:
		return
		
	# Check if virtually focused item is currently visible - optimized range check
	var visual_index = virtual_focused_data_index - current_scroll_index
	if visual_index >= 0 and visual_index < active_items.size():
		var item = active_items[visual_index]
		if item and item.can_process():
			item.grab_focus()
			current_real_focused_item = item

func _get_currently_focused_item() -> Control:
	"""Find which item currently has real UI focus - optimized O(1) instead of O(n)"""
	var focused = viewport_cache.gui_get_focus_owner()
	# OPTIMIZATION: Use HashSet lookup O(1) instead of Array search O(n)
	if focused and active_items_set.has(focused):
		current_real_focused_item = focused
		return focused
	current_real_focused_item = null
	return null

func _get_data_index_for_item(item: Control) -> int:
	"""Find the data index for a given item control - optimized"""
	var visual_index = active_items.find(item)
	return current_scroll_index + visual_index if visual_index != -1 else -1

func set_data(new_data: Array):
	"""Set the data array for the list"""
	data = new_data
	data_size = new_data.size()  # Cache size for performance
	_clear_virtual_focus()  # Reset all focus state
	
	# Calculate visible count if we haven't determined item height yet
	if auto_calculate_visible_count and item_height <= 0.0:
		await _determine_item_height()
		_calculate_visible_item_count()
	
	_update_scroll_range()
	_refresh_visible_items()

func set_item_template(template: PackedScene):
	"""Set the item template scene"""
	item_template = template
	item_height = 0.0  # Reset item height to recalculate
	_clear_all_items()
	
	if auto_calculate_visible_count:
		await _determine_item_height()
		_calculate_visible_item_count()
	else:
		_create_item_pool()

func _setup_initial_state():
	"""Initialize the list with default values"""
	_clear_all_items()
	
	if item_template:
		if auto_calculate_visible_count:
			await _determine_item_height()
			_calculate_visible_item_count()
		else:
			_create_item_pool()
	
	_update_scroll_range()
	_refresh_visible_items()

func _create_item_pool():
	"""Create a pool of reusable item instances - optimized"""
	var pool_size = visible_item_count + 2  # +2 for buffer items
	
	# Clear existing pool
	for item in item_pool:
		if is_instance_valid(item):
			item.queue_free()
	
	# Resize arrays for optimal performance
	item_pool.clear()
	item_pool.resize(pool_size)
	
	# Create new pool items
	if item_template:
		for i in pool_size:
			var item = item_template.instantiate()
			item.visible = false
			item.focus_mode = Control.FOCUS_NONE  # Start without focus capability
			# Connect focus signals for virtual focus management
			item.focus_entered.connect(_on_item_focus_entered.bind(item))
			item.focus_exited.connect(_on_item_focus_exited.bind(item))
			content_container.add_child(item)
			item_pool[i] = item

func _on_item_focus_entered(item: Control):
	"""Handle when an item gains focus - establish virtual focus"""
	if preserve_focus:
		var data_index = _get_data_index_for_item(item)
		if data_index != -1:
			_set_virtual_focus(data_index)
			current_real_focused_item = item

func _on_item_focus_exited(item: Control):
	"""Handle when an item loses focus"""
	# Don't immediately clear virtual focus - let the monitoring system handle it
	# This allows for focus to move between our items without losing virtual focus
	if current_real_focused_item == item:
		current_real_focused_item = null

func _update_scroll_range():
	"""Update scroll bar range based on data size - synchronized for both scrollbars"""
	if not scroll_bar and not overlay_scroll_bar:
		return
	
	max_scroll_index = maxi(0, data_size - visible_item_count)  # Use maxi for integers
	
	var max_value = float(max_scroll_index + visible_item_count)
	var page_size = float(visible_item_count)
	
	# Prevent recursive updates during synchronization
	is_updating_scrollbars = true
	
	# Configure both scrollbars with identical settings
	var scrollbars = [scroll_bar, overlay_scroll_bar]
	for scrollbar in scrollbars:
		if scrollbar:
			scrollbar.min_value = 0.0
			scrollbar.max_value = max_value
			scrollbar.step = 1.0
			scrollbar.page = page_size
			scrollbar.value = 0.0
	
	is_updating_scrollbars = false
	current_scroll_index = 0

func _refresh_visible_items():
	"""Refresh the visible items based on current scroll position - optimized"""
	
	# Clear current real focused item reference if it's about to become invisible
	if current_real_focused_item:
		current_real_focused_item = null
	
	# OPTIMIZATION: Clear HashSet when hiding items
	active_items_set.clear()
	
	# Hide all active items first - optimized loop
	var active_count = active_items.size()
	for i in active_count:
		var item = active_items[i]
		if is_instance_valid(item):
			item.visible = false
			# OPTIMIZATION: Don't set focus_mode when hiding - unnecessary
	active_items.clear()
	
	# Calculate how many items we can actually show
	var remaining_data = data_size - current_scroll_index
	var items_to_show = mini(visible_item_count, remaining_data)
	
	# Pre-resize active_items for optimal performance
	active_items.resize(items_to_show)
	
	# Show items for current scroll position - optimized loop
	for i in items_to_show:
		var data_index = current_scroll_index + i
		var item = item_pool[i]  # Direct access instead of function call
		
		if item and data_index < data_size:
			_configure_item(item, data_index, data[data_index])
			item.visible = true
			item.focus_mode = Control.FOCUS_ALL  # Re-enable focus
			active_items[i] = item
			# OPTIMIZATION: Add to HashSet for O(1) lookups
			active_items_set[item] = true
	
	# OPTIMIZATION: Only call deferred if virtual focus exists
	if has_virtual_focus:
		call_deferred("_apply_real_focus_if_visible")

func _configure_item(item: Control, index: int, item_data):
	"""Configure an item with data - optimized with method caching"""
	# OPTIMIZATION: Cache method names per item type to avoid repeated has_method() calls
	var key = item.get_script() if item.get_script() else item.get_class()
	
	if not method_cache.has(key):
		if item.has_method("configure_item"):
			method_cache[key] = "configure_item"
		elif item.has_method("set_data"):
			method_cache[key] = "set_data"
		else:
			method_cache[key] = null
	
	var method_name = method_cache[key]
	if method_name:
		item.call(method_name, index, item_data)

func _clear_all_items():
	"""Clear all items from the container - optimized to avoid get_children() allocation"""
	active_items.clear()
	active_items_set.clear()  # OPTIMIZATION: Clear HashSet too
	_clear_virtual_focus()
	
	if content_container:
		# OPTIMIZATION: Avoid get_children() array allocation
		while content_container.get_child_count() > 0:
			content_container.get_child(0).queue_free()
	
	item_pool.clear()
	method_cache.clear()  # Clear method cache when clearing items

# Public API methods - now with synchronized scrolling
func scroll_to_index(index: int):
	"""Scroll to a specific data index - synchronized across both scrollbars"""
	var target_value = float(clampi(index, 0, max_scroll_index))
	
	# Prevent recursive updates
	is_updating_scrollbars = true
	
	# Update both scrollbars to the same value
	if scroll_bar:
		scroll_bar.value = target_value
	if overlay_scroll_bar:
		overlay_scroll_bar.value = target_value
	
	is_updating_scrollbars = false
	
	# Update internal state and refresh
	current_scroll_index = int(target_value)
	_refresh_visible_items()

func scroll_to_end():
	"""Scroll to the very end of the list"""
	if data_size > 0:
		scroll_to_index(max_scroll_index)

func get_visible_range() -> Vector2i:
	"""Get the range of currently visible data indices - optimized"""
	var start_index = current_scroll_index
	var end_index = mini(current_scroll_index + visible_item_count - 1, data_size - 1)
	return Vector2i(start_index, end_index)

func refresh():
	"""Force refresh the entire list"""
	_update_scroll_range()
	_refresh_visible_items()

func set_focus_preservation(enabled: bool):
	"""Enable or disable focus preservation during scrolling"""
	preserve_focus = enabled
	if not enabled:
		_clear_virtual_focus()

func focus_item_at_data_index(data_index: int):
	"""Manually focus an item at the given data index - optimized"""
	if data_index < 0 or data_index >= data_size:
		return
	
	# Set virtual focus
	_set_virtual_focus(data_index)
	
	# Scroll to make the item visible if needed - optimized range checks
	if data_index < current_scroll_index:
		scroll_to_index(data_index)
	elif data_index >= current_scroll_index + visible_item_count:
		scroll_to_index(data_index - visible_item_count + 1)
	else:
		# Item is already visible, apply real focus immediately
		_apply_real_focus_if_visible()

func get_virtual_focused_index() -> int:
	"""Get the currently virtually focused data index (-1 if none)"""
	return virtual_focused_data_index if has_virtual_focus else -1

func is_list_focused() -> bool:
	"""Check if this LazyListBox has any kind of focus (virtual or real)"""
	return has_virtual_focus

# NEW: Public API for manual control of visible count calculation
func set_auto_calculate_visible_count(enabled: bool):
	"""Enable or disable automatic calculation of visible_item_count"""
	auto_calculate_visible_count = enabled
	if enabled:
		_calculate_visible_item_count()

func set_manual_item_height(height: float):
	"""Manually set item height for calculation"""
	item_height = height
	if auto_calculate_visible_count:
		_calculate_visible_item_count()

func get_item_height() -> float:
	"""Get the current item height"""
	return item_height

func get_calculated_visible_count() -> int:
	"""Get the current calculated visible item count"""
	return visible_item_count

# Debug method - kept empty as requested
func _debug_print(message: String):
	"""Debug printing - intentionally empty"""
	pass
