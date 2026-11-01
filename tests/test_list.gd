extends SceneTree
var failures: int = 0
var events: Array = []
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func check_visible_rows(list: LazyListBox, context: String) -> void:
	var visible_range := list.get_visible_range()
	for index in range(visible_range.x, visible_range.y + 1):
		check(list._assigned.has(index), context + ": visible row assigned " + str(index))
		if list._assigned.has(index):
			var item: LazyListItem = list._assigned[index]
			check(item.visible and item in list.active_items and item.item_index == index and item.item_data == list.data[index], context + ": visible row displays correct data " + str(index))
func frames() -> void:
	await process_frame
	await process_frame
	await process_frame
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	list.item_template = load("res://tests/test_item.tscn")
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	list.size = Vector2(320, 125)
	list.set_data([1])
	list.set_data([])
	root.add_child(list)
	await list.fully_ready
	await frames()
	check(list.get_visible_range() == Vector2i(0, -1), "pending empty data")
	check(not list.has_pending_data, "pending flag cleared")
	list.set_data([0, 1])
	await frames()
	check(list.get_visible_range() == Vector2i(0, 1), "short list")
	check(list.scroll_bar.value == 0, "short list does not scroll")
	list.set_data(range(10000))
	await frames()
	check(list.item_pool.size() <= 6, "large list bounded pool")
	check(list.get_visible_range() == Vector2i(0, 2), "partly visible bottom row")
	var counts: Dictionary = {}
	for item in list.item_pool:
		counts[item] = item.configurations
	list.scroll_bar.value = 10
	check(list.get_visible_range() == Vector2i(0, 2), "partly visible top and bottom")
	for item in list.item_pool:
		check(counts[item] == item.configurations, "pixel movement does not configure")
	var retained: Control = list._assigned[2]
	list.scroll_bar.value = 60
	check(list._assigned[2] == retained, "overlapping assignments keep their nodes")
	check(list.scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "horizontal scrolling disabled")
	list.scroll_to_index(500)
	check(list.scroll_bar.value == 500 * 54, "index aligns at top")
	list.scroll_to_end()
	await frames()
	check(list.scroll_bar.value == 10000 * 54 - 4 - 125, "end has no blank space")
	check(list.get_visible_range().y == 9999, "last row visible")
	list.set_data(range(20))
	await frames()
	check(list.scroll_bar.value == 20 * 54 - 4 - 125, "data shrink clamps")
	list.scroll_bar.value = 123
	list.set_data(range(30))
	await frames()
	check(list.scroll_bar.value == 123, "data change preserves pixels")
	list.force_scroll_reset = true
	list.set_data(range(30))
	check(list.scroll_bar.value == 0, "same size reset")
	list.hide_scroll_bar = true
	await frames()
	check(not list.scroll_bar.visible, "native bar hidden")
	list.scroll_to_index(4)
	check(list.scroll_bar.value == 216, "hidden scrollbar still scrolls")
	for height in [400, 125, 540, 54, 25, 125]:
		list.size.y = height
		await frames()
		check(list.item_pool.size() == ceili(height / 54.0) + 3, "resize adjusts pool at height " + str(height))
		check_visible_rows(list, "resized list")
		# A partial top row can require one more visible row than an aligned view.
		list.scroll_bar.value += 10
		check_visible_rows(list, "resized list after pixel scrolling")
	var item: LazyListItem = list.active_items[0]
	var count: int = item.configurations
	list.data[item.item_index] = "changed"
	list.refresh()
	check(item.item_data == "changed" and item.configurations == count + 1, "refresh reconfigures")
	list.focus_item_at_data_index(5)
	check(list.get_virtual_focused_index() == 5, "focus index")
	list.scroll_to_index(20)
	check(list.get_virtual_focused_index() == 5, "recycling preserves virtual index")
	check(root.gui_get_focus_owner() == list, "recycled real focus parked")
	var down := InputEventAction.new()
	down.action = "ui_down"
	down.pressed = true
	list._input(down)
	check(list.get_virtual_focused_index() == 6, "keyboard resumes from virtual index")
	check(6 * 54 >= list.scroll_bar.value and 6 * 54 + 50 <= list.scroll_bar.value + 125, "keyboard fully reveals row")
	list.item_event.connect(func(index, entry, action): events.append([index, entry, action]))
	for iteration in range(5):
		list.set_item_template(load("res://tests/test_item.tscn"))
		await frames()
		check(list.content_container.get_child_count() == list.item_pool.size(), "template cleanup")
	list.scroll_to_index(15)
	item = list._assigned[15]
	item.get_node("Button").pressed.emit()
	check(events.size() == 1 and events[0][0] == 15 and events[0][1] == 15, "recycled events connected once with correct data")
	list.set_data([])
	await frames()
	check(list.item_pool.is_empty(), "empty list releases pool")
	var spaced_list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	spaced_list.item_template = load("res://tests/test_item.tscn")
	spaced_list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	spaced_list.size = Vector2(320, 125)
	spaced_list.set_data(range(100))
	root.add_child(spaced_list)
	await spaced_list.fully_ready
	await frames()
	check(spaced_list.item_height == 50, "template height measured at startup")
	check(spaced_list.get_visible_range() == Vector2i(0, 2), "automatic sizing fills viewport at startup")
	var custom_theme := Theme.new()
	custom_theme.set_constant("separation", "VBoxContainer", 20)
	spaced_list.theme = custom_theme
	await frames()
	spaced_list.scroll_bar.value = 55
	check(spaced_list.get_visible_range() == Vector2i(1, 2), "gap at top excludes preceding row")
	var outside := Button.new()
	outside.name = "Outside"
	root.add_child(outside)
	for action in ["ui_home", "ui_page_down", "ui_page_up", "ui_end"]:
		spaced_list.focus_item_at_data_index(5)
		var key := InputEventAction.new()
		key.action = action
		key.pressed = true
		spaced_list._input(key)
		var expected: int = {"ui_home": 0, "ui_page_down": 6, "ui_page_up": 4, "ui_end": 99}[action]
		check(spaced_list.get_virtual_focused_index() == expected, "keyboard action " + action)
	spaced_list.focus_neighbor_bottom = spaced_list.get_path_to(outside)
	spaced_list.focus_item_at_data_index(99)
	spaced_list._input(down)
	check(root.gui_get_focus_owner() == outside, "external bottom focus neighbor")
	check(spaced_list.get_virtual_focused_index() == -1, "external focus clears virtual focus")
	var empty_signals: Array = []
	spaced_list.list_became_empty.connect(func(): empty_signals.append(true))
	spaced_list.set_data([])
	spaced_list.set_data([])
	check(empty_signals.size() == 1, "empty transition emitted once")
	spaced_list.queue_free()
	outside.queue_free()
	list.queue_free()
	await frames()
	print("LazyListBox tests: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(0 if failures == 0 else 1)
