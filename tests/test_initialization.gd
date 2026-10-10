extends SceneTree

var failures: int = 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame
	await process_frame

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for mode in ["scene", "direct", "missing_content", "existing_children"]:
		print("Initialization case: ", mode)
		var list: LazyListBox
		if mode == "scene" or mode == "missing_content":
			list = load("res://addons/lazy_list_box/lazy_list_box.tscn").instantiate()
			if mode == "missing_content":
				list.get_node("ScrollContainer/Content").free()
		else:
			list = LazyListBox.new()
			if mode == "existing_children":
				# No scene owner or unique-name flags: named children must suffice.
				var scroll := ScrollContainer.new()
				scroll.name = "ScrollContainer"
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				list.add_child(scroll)
				scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
				scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
				var content := Control.new()
				content.name = "Content"
				content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				content.mouse_filter = Control.MOUSE_FILTER_PASS
				scroll.add_child(content)
		var original_scroll := list.get_node_or_null("ScrollContainer")
		var original_content := list.get_node_or_null("ScrollContainer/Content")
		list.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		list.position = Vector2(23, 41)
		list.size = Vector2(320, 125)
		list.item_template = load("res://tests/test_item.tscn")
		list.hide_scroll_bar = true
		list.set_data(range(1000))
		root.add_child(list)
		await list.fully_ready
		await frames()
		check(list.is_ready_for_data() and not list.has_pending_data, mode + ": initialized with pending data")
		check(list.position == Vector2(23, 41) and list.size == Vector2(320, 125), mode + ": outer layout preserved")
		check(list.get_child_count() == 1, mode + ": no duplicate scroll container")
		var content_count := 0
		for child in list.scroll_container.get_children():
			if not child is ScrollBar:
				content_count += 1
		check(content_count == 1, mode + ": no duplicate content")
		if original_scroll:
			check(list.scroll_container == original_scroll, mode + ": scroll container reused")
		if original_content:
			check(list.content_container == original_content, mode + ": content reused")
		check(list.scroll_container.position == Vector2.ZERO and list.scroll_container.size == list.size, mode + ": scroll fills list")
		check(list.scroll_container.grow_horizontal == Control.GROW_DIRECTION_BOTH and list.scroll_container.grow_vertical == Control.GROW_DIRECTION_BOTH, mode + ": scene growth defaults")
		check(list.scroll_container.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, mode + ": horizontal scroll disabled")
		check(list.content_container.mouse_filter == Control.MOUSE_FILTER_PASS, mode + ": content passes pointer input")
		check(list.content_container.size_flags_horizontal == Control.SIZE_EXPAND_FILL, mode + ": content fills width")
		check(not list.scroll_bar.visible, mode + ": startup hidden scrollbar")
		check(list.get_visible_range() == Vector2i(0, 2), mode + ": initial visible rows")
		check(list._assigned[0].item_data == 0, mode + ": pending data configured")
		var pool := list.item_pool.duplicate()
		list.focus_item_at_data_index(1)
		check(root.gui_get_focus_owner() == list._assigned[1].get_node("Button"), mode + ": item focus")
		list.scroll_to_index(500)
		await frames()
		check(list.get_visible_range().x == 500, mode + ": scroll to index")
		check(list.get_virtual_focused_index() == 1 and root.gui_get_focus_owner() == list, mode + ": recycled focus parked")
		check(list.item_pool.size() == pool.size(), mode + ": bounded pool")
		for item in list.item_pool:
			check(item in pool, mode + ": pool reused")
		var down := InputEventAction.new()
		down.action = "ui_down"
		down.pressed = true
		list._input(down)
		check(list.get_virtual_focused_index() == 2, mode + ": keyboard resumes focus")
		list.scroll_to_end()
		list.refresh()
		await frames()
		check(list.get_visible_range().y == 999, mode + ": last row visible after refresh")
		list.size = Vector2(400, 180)
		await frames()
		check(list.scroll_container.size == list.size, mode + ": internal layout follows resize")
		list.queue_free()
		await frames()
		print("Initialization case complete: ", mode)
	print("LazyListBox initialization tests: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(0 if failures == 0 else 1)
