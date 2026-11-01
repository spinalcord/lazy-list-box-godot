extends SceneTree

var failures := 0
var requests: Array = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int = 5) -> void:
	for index in range(count):
		await process_frame

func make_list(count: int = 0, enabled: bool = true, height: float = 125.0) -> LazyListBox:
	var list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	check(not list.load_more_enabled and list.load_more_threshold == 10 and list.has_more_data, "export defaults")
	list.item_template = load("res://tests/test_item.tscn")
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	list.size = Vector2(320, height)
	list.load_more_enabled = enabled
	list.set_data(range(count))
	list.load_more_requested.connect(func(): requests.append(list.data_size))
	return list

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(640, 480)
	var list := make_list(0, false)
	root.add_child(list)
	await list.fully_ready
	await frames()
	check(requests.is_empty(), "disabled by default")
	list.load_more_enabled = true
	check(requests.is_empty(), "request is deferred")
	await frames()
	check(requests == [0], "empty list requests initial data")
	list.refresh()
	list.set_data([])
	await frames()
	check(requests == [0], "empty same-size replacement and refresh stay locked")
	list.reset_load_more_request()
	await frames()
	check(requests == [0, 0], "retry without size change")
	list.set_data(range(20))
	await frames()
	check(requests.size() == 2, "outside default threshold")
	list.scroll_to_index(6)
	await frames()
	check(requests.size() == 2, "11 rows remaining does not request")
	list.scroll_to_index(7)
	await frames()
	check(requests.back() == 20 and requests.size() == 3, "partial bottom row counts at threshold 10")
	for index in range(4):
		list.scroll_to_end()
		list.scroll_to_index(7)
		list.refresh()
		list.set_data(range(20))
	await frames()
	check(requests.size() == 3, "scrolling, refresh and same-size data do not duplicate")
	list.set_data(range(21))
	list.scroll_to_end()
	await frames()
	check(requests.size() == 4, "changed count unlocks")
	list.load_more_threshold = 0
	list.set_data(range(30))
	await frames()
	list.scroll_to_index(26)
	await frames()
	check(requests.size() == 4, "threshold zero waits for last row")
	list.scroll_to_index(27)
	await frames()
	check(requests.size() == 5, "threshold zero includes partially visible last row")
	list.set_data(range(40))
	await frames()
	list.scroll_to_end()
	list.has_more_data = false
	await frames()
	check(requests.size() == 5, "queued request rechecks end of data")
	list.has_more_data = true
	list.load_more_enabled = false
	await frames()
	check(requests.size() == 5, "queued request rechecks enabled setting")
	list.load_more_enabled = true
	await frames()
	check(requests.size() == 6, "enabling checks current position")
	list.reset_load_more_request()
	list.has_more_data = false
	await frames()
	check(requests.size() == 6, "reset respects end of data")
	list.queue_free()
	await frames()

	requests.clear()
	list = make_list(10)
	list.load_more_threshold = -5
	check(list.load_more_threshold == 0, "negative threshold clamps")
	root.add_child(list)
	await list.fully_ready
	await frames()
	check(requests.is_empty(), "small viewport below threshold")
	list.size.y = 550
	await frames()
	check(requests == [10], "resize reveals end and requests")
	list.size.y = 125
	list.set_data(range(11))
	await frames()
	check(requests == [10], "new count outside zero threshold")
	list.load_more_threshold = 8
	await frames()
	check(requests == [10, 11], "threshold setting schedules a fresh check")
	list.queue_free()
	await frames()

	requests.clear()
	list = make_list(0, true, 0)
	root.add_child(list)
	await list.fully_ready
	await frames()
	check(requests.is_empty(), "zero viewport suppresses empty request")
	list.size.y = 125
	await frames()
	check(requests == [0], "positive viewport triggers empty request")
	list.queue_free()
	await frames()

	requests.clear()
	list = make_list()
	var ready_seen := [false]
	list.fully_ready.connect(func():
		check(requests.is_empty(), "no request before fully_ready")
		ready_seen[0] = true
	)
	list.load_more_requested.connect(func():
		check(ready_seen[0], "request follows fully_ready")
		# Synchronous short pages must chain without recursion or duplicate requests.
		if list.data_size == 4:
			list.has_more_data = false
		else:
			list.set_data(range(list.data_size + 1))
	)
	root.add_child(list)
	await frames(20)
	check(requests == [0, 1, 2, 3, 4], "synchronous short pages automatically chain once per count")
	list.queue_free()
	await frames()

	var basic: Node = load("res://addons/lazy_list_box/demos/basic_example/demo.tscn").instantiate()
	root.add_child(basic)
	await frames()
	check(basic.get_node("HBoxContainer/LazyListBox").data_size == 500, "basic demo loads preserved data")
	basic.queue_free()
	await frames()
	var demo: Node = load("res://addons/lazy_list_box/demos/load_more_example/demo.tscn").instantiate()
	demo.simulated_delay = 0.0
	check(demo.entries.is_empty(), "load more demo starts empty")
	root.add_child(demo)
	await frames(10)
	check(demo.entries.size() == 50 and not demo.loading, "demo initial page")
	demo.list.scroll_to_end()
	await frames()
	check(demo.second_page_failed and demo.retry_button.visible, "demo second page fails once")
	check(demo.entries.size() == 50 and not demo.loading, "failed page leaves data and releases loading guard")
	demo.retry_button.pressed.emit()
	await frames()
	check(demo.entries.size() == 100 and not demo.retry_button.visible, "retry loads second page")
	for expected in [150, 200, 250]:
		demo.list.scroll_to_end()
		var position: float = demo.list.scroll_bar.value
		await frames()
		check(demo.entries.size() == expected, "demo page reaches " + str(expected))
		check(demo.list.scroll_bar.value == position, "append preserves scroll position")
		check(demo.list.item_pool.size() <= ceili(demo.list._viewport_height() / demo.list._stride()) + 3, "demo pool bounded")
	check(not demo.list.has_more_data and demo.status_label.text.contains("End of data"), "demo reports end of data")
	demo.list.scroll_to_end()
	await frames()
	check(demo.entries.size() == 250 and not demo.loading, "demo stops at 250")
	demo.queue_free()
	await frames()
	print("LazyListBox load more tests: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(0 if failures == 0 else 1)
