extends SceneTree
var failures: int = 0
var clicks: int = 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	Input.emulate_touch_from_mouse = true
	run.call_deferred()
func pause() -> void:
	await create_timer(0.05).timeout
func button(position: Vector2, pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = which
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and which == MOUSE_BUTTON_LEFT else 0
	root.push_input(event, true)
func motion(position: Vector2, relative: Vector2, held: bool) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(event, true)
func run() -> void:
	root.size = Vector2i(640, 480)
	var list: LazyListBox = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
	list.item_template = load("res://tests/test_item.tscn")
	list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	list.position = Vector2(20, 20)
	list.size = Vector2(320, 300)
	list.set_data(range(1000))
	root.add_child(list)
	await list.fully_ready
	await pause()
	list.item_event.connect(func(_index, _entry, _action): clicks += 1)
	motion(Vector2(100, 40), Vector2.ZERO, false)
	button(Vector2(100, 40), true)
	button(Vector2(100, 40), false)
	check(clicks == 1, "tap activates button once")
	button(Vector2(100, 150), true, MOUSE_BUTTON_WHEEL_DOWN)
	button(Vector2(100, 150), false, MOUSE_BUTTON_WHEEL_DOWN)
	await pause()
	check(list.scroll_bar.value > 0, "wheel scrolls over button")
	list.scroll_to_index(0)
	await pause()
	var bar_point: Vector2 = list.scroll_bar.global_position + Vector2(list.scroll_bar.size.x / 2, 8)
	motion(bar_point, Vector2.ZERO, false)
	button(bar_point, true)
	motion(bar_point + Vector2(0, 100), Vector2(0, 100), true)
	button(bar_point + Vector2(0, 100), false)
	await pause()
	check(list.scroll_bar.value > 0, "scrollbar thumb drag")
	for hidden in [false, true]:
		list.hide_scroll_bar = hidden
		list.scroll_to_index(0)
		await pause()
		var before_clicks := clicks
		var point := Vector2(100, 250)
		motion(point, Vector2.ZERO, false)
		button(point, true)
		for step in range(7):
			point.y -= 20
			motion(point, Vector2(0, -20), true)
			await create_timer(0.025).timeout
		var dragged := list.scroll_bar.value
		check(dragged > 80, "touch drag over button (hidden=%s)" % hidden)
		button(point, false)
		await create_timer(0.12).timeout
		check(clicks == before_clicks, "drag does not click")
		check(list.scroll_bar.value > dragged, "native inertia after release")
		button(Vector2(100, 200), true)
		var stopped := list.scroll_bar.value
		await create_timer(0.12).timeout
		check(absf(list.scroll_bar.value - stopped) < 1, "new touch stops inertia")
		button(Vector2(100, 200), false)
	list.queue_free()
	await pause()
	print("LazyListBox pointer tests: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(0 if failures == 0 else 1)
