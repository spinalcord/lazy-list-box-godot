@tool
extends EditorPlugin

func _enter_tree():
	# Add the custom control to the editor
	add_custom_type(
		"LazyListBox",
		"Control", 
		preload("lazy_list_box.gd"),
		preload("res://addons/lazy_list_box/icon.svg"))
