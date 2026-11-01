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
func test_refresh_item() -> void:
	var list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	list.item_template = load("res://tests/test_item.tscn")
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	list.size = Vector2(320, 125)
	list.set_data(range(10000))
	list.refresh_item(0)
	list.refresh_item(-1)
	list.refresh_item(10000)
	check(list.item_pool.is_empty() and list._assigned.is_empty() and list.has_pending_data, "refresh_item before initialization does nothing")
	root.add_child(list)
	await list.fully_ready
	await frames()
	list.scroll_to_index(500)
	list.scroll_bar.value += 10
	list.focus_item_at_data_index(501)
	await frames()
	var scroll_position := list.scroll_bar.value
	var focus_owner := root.gui_get_focus_owner()
	var focused_index := list.get_virtual_focused_index()
	var pool := list.item_pool.duplicate()
	var assignments := list._assigned.duplicate()
	var positions: Dictionary = {}
	var counts: Dictionary = {}
	for item in pool:
		counts[item] = item.configurations
		positions[item] = item.position
	var visible_index := list.get_visible_range().x + 1
	var buffer_index := list.get_visible_range().x - 1
	check(list._assigned.has(buffer_index), "refresh_item test has an assigned buffer row")
	for index in [visible_index, buffer_index]:
		list.data[index] = "updated " + str(index)
		list.refresh_item(index)
		var refreshed: LazyListItem = list._assigned[index]
		check(refreshed.item_data == list.data[index] and refreshed.get_node("Button").text == list.data[index], "refresh_item updates displayed data at " + str(index))
		for item in pool:
			check(item.configurations == counts[item] + (1 if item == refreshed else 0), "refresh_item configures only the target once")
			counts[item] = item.configurations
	var outside_index := 9000
	check(not list._assigned.has(outside_index), "refresh_item test entry is outside pool")
	list.data[outside_index] = "updated outside pool"
	list.refresh_item(outside_index)
	list.refresh_item(-1)
	list.refresh_item(list.data_size)
	list.refresh_item(list.data_size + 100)
	for item in pool:
		check(item.configurations == counts[item], "unassigned and invalid refresh_item do not configure")
		check(item.position == positions[item], "refresh_item preserves row layout")
	check(list.item_pool == pool and list._assigned == assignments, "refresh_item preserves pool and assignments")
	check(list.scroll_bar.value == scroll_position, "refresh_item preserves pixel scroll position")
	check(root.gui_get_focus_owner() == focus_owner and list.get_virtual_focused_index() == focused_index, "refresh_item preserves real and virtual focus")
	await frames()
	for item in pool:
		check(item.configurations == counts[item], "refresh_item does not defer extra configurations")
	list.scroll_to_index(outside_index)
	var revealed: LazyListItem = list._assigned[outside_index]
	check(revealed.item_data == list.data[outside_index] and revealed.get_node("Button").text == list.data[outside_index], "later assignment uses current data after unassigned refresh_item")
	list.set_data([])
	list.refresh_item(0)
	list.refresh_item(-1)
	check(list.item_pool.is_empty() and list._assigned.is_empty(), "refresh_item on empty list does nothing")
	list.queue_free()
	await frames()
func check_scroll(list: LazyListBox, index: int, alignment: LazyListBox.ScrollAlignment, expected: float, context: String) -> void:
	list.scroll_to_index(index, alignment)
	check(is_equal_approx(list.scroll_bar.value, expected), context + ": expected " + str(expected) + ", got " + str(list.scroll_bar.value))
	check_visible_rows(list, context)
	var counts: Dictionary = {}
	for item in list.item_pool:
		counts[item] = item.configurations
	list.scroll_to_index(index, alignment)
	await frames()
	for item in list.item_pool:
		check(counts.has(item) and item.configurations == counts[item], context + ": repeated alignment does not configure rows")

func test_scroll_alignment() -> void:
	var list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	list.item_template = load("res://tests/test_item.tscn")
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	list.size = Vector2(320, 120)
	var custom_theme := Theme.new()
	custom_theme.set_constant("separation", "VBoxContainer", 20)
	list.theme = custom_theme
	list.set_data(range(100))
	var alignments := [LazyListBox.ALIGN_TOP, LazyListBox.ALIGN_CENTER, LazyListBox.ALIGN_BOTTOM, LazyListBox.ALIGN_NEAREST]
	for alignment in alignments:
		list.scroll_to_index(10, alignment)
	check(list.scroll_bar == null and list.item_pool.is_empty() and list.has_pending_data, "scroll alignment before initialization does nothing")
	root.add_child(list)
	await list.fully_ready
	await frames()
	check(list.item_height == 50 and list._viewport_height() == 120 and list._stride() == 70, "alignment fixture has row spacing and known viewport")
	for entry in [[LazyListBox.ALIGN_TOP, 700.0], [LazyListBox.ALIGN_CENTER, 665.0], [LazyListBox.ALIGN_BOTTOM, 630.0], [LazyListBox.ALIGN_NEAREST, 630.0]]:
		list.scroll_bar.value = 0
		await check_scroll(list, 10, entry[0], entry[1], "middle row alignment " + str(entry[0]))
	list.scroll_to_index(10)
	check(list.scroll_bar.value == 700, "omitted alignment still aligns at top")
	for entry in [[690, 690], [710, 700], [620, 630], [900, 700], [500, 630], [700, 700], [630, 630], [750, 700]]:
		list.scroll_bar.value = entry[0]
		await check_scroll(list, 10, LazyListBox.ALIGN_NEAREST, entry[1], "nearest from " + str(entry[0]))
	for alignment in alignments:
		for index in [0, -100]:
			list.scroll_bar.value = 700
			await check_scroll(list, index, alignment, 0, "first/clamped negative index " + str(alignment))
		for index in [99, 1000]:
			list.scroll_bar.value = 0
			await check_scroll(list, index, alignment, 6860, "last/clamped excessive index " + str(alignment))
	check(list.get_virtual_focused_index() == -1, "scroll alignment does not select or focus an entry")
	list.set_data([0])
	for height in [50, 120, 200]:
		list.set_manual_item_height(height)
		await frames()
		var maximum := maxf(0, height - 120)
		for alignment in alignments:
			var expected := 0.0
			if alignment == LazyListBox.ALIGN_CENTER:
				expected = maximum / 2.0
			elif alignment == LazyListBox.ALIGN_BOTTOM or alignment == LazyListBox.ALIGN_NEAREST:
				expected = maximum
			for index in [-100, 0, 100]:
				list.scroll_bar.value = maximum
				await check_scroll(list, index, alignment, expected, "single row height " + str(height) + ", index " + str(index) + ", alignment " + str(alignment))
		list.scroll_bar.value = maximum
		list.scroll_to_index(0)
		check(list.scroll_bar.value == 0, "single row default alignment at height " + str(height))
		check(list.item_pool.size() == 1 and list.get_visible_range() == Vector2i(0, 0), "single row stays visible with exactly one pooled item")
	list.set_manual_item_height(50)
	list.set_data([0, 1])
	await frames()
	for alignment in alignments:
		await check_scroll(list, 1, alignment, 0, "short list " + str(alignment))
	list.set_data(range(100))
	list.set_manual_item_height(200)
	await frames()
	for entry in [[LazyListBox.ALIGN_TOP, 2200.0], [LazyListBox.ALIGN_CENTER, 2240.0], [LazyListBox.ALIGN_BOTTOM, 2280.0]]:
		await check_scroll(list, 10, entry[0], entry[1], "tall row alignment " + str(entry[0]))
	for entry in [[2240, 2240], [2200, 2200], [2280, 2280], [2180, 2200], [2300, 2280], [1900, 2200], [2600, 2280]]:
		list.scroll_bar.value = entry[0]
		await check_scroll(list, 10, LazyListBox.ALIGN_NEAREST, entry[1], "nearest tall row from " + str(entry[0]))
	# Inspect the zero-height guard before native deferred layout can change the range.
	list.scroll_container.size.y = 0
	check(list._viewport_height() == 0, "alignment fixture has a zero-height viewport")
	var position := list.scroll_bar.value
	var assignments := list._assigned.duplicate()
	for alignment in alignments:
		list.scroll_to_index(50, alignment)
	check(list.scroll_bar.value == position and list._assigned == assignments, "zero viewport alignment does nothing")
	list.size.y = 120
	list.scroll_container.size.y = 120
	list.set_data([])
	await frames()
	for alignment in alignments:
		list.scroll_to_index(10, alignment)
	check(list.scroll_bar.value == 0 and list.item_pool.is_empty(), "empty list alignment does nothing")
	list.queue_free()
	await frames()

func run() -> void:
	await test_scroll_alignment()
	await test_refresh_item()
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
