# Lazy ListBox for Godot 4

A high-performance List-Box control that can handle thousands of items. 
Works with a data template.

## Features
- Virtual scrolling for optimal performance
- Auto-calculation of visible items
- Synchronized scrollbar
- Focus management with keyboard navigation!
- Recycling items /Caching system

## Installation
1. Download
2. Enable in Project Settings > Plugins

## Usage
- Use the `lazy_list_box.tscn` on your prefered `CanvasLayer`.
- Create an `item_template.tscn` which should represent your item in the `LazyListBox`.
- Open your `item_template.tscn` and attach this script on it:

```gdscript
extends Control # Change this to your preferend control type.

# Store the original data and index for later use
var item_data
var item_index: int = -1

func _ready():
	# EXAMPLE: Access data
	# some_control_event.connect(_on_some_control_event)
	pass

# EXAMPLE: Access data
#func _on_some_control_event():
# 	# Print both the displayed text and original data
# 	print("Button clicked - Index: ", item_index, " Data: ", item_data, " Text: ", text)

# This is called by LazyListBox: to configure the item
func configure_item(index: int, data):
	item_index = index
	item_data = data
	text = str(data)  # Display the data as button text

# This is called by LazyListBox: data setter
func set_data(data):
	item_data = data
	text = str(data)
```
# Simple Test with Fake Data
Following Script will generate `500` objects. But you can also do `10000`.
Create a node and attach this Script and assign the LazyListBox Control:

```gdscript
extends Node

@export var lazy_list: LazyListBox

func _ready():
	assert(lazy_list != null, "Assign the lazy_list control! It's usally the lazy_list_box.tscn you dropped in your scene.")
	# Create simple test data with 100 items
	var test_data = []
	for i in range(500):
		test_data.append("Item " + str(i))
	# Set the data
	lazy_list.set_data(test_data)
```
