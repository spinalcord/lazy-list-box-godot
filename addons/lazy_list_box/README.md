![Example 1](screenshots/1.gif)
![Example 1](screenshots/2.gif)
![Example 1](screenshots/3.gif)


# LazyListBox for Godot 4.4+

A high-performance List-Box control that can handle 
thousands of items by recycling a small pool of UI 
elements and only displaying what's currently visible
on screen instead of creating individual controls for
every data entry, creating the illusion that you're scrolling
through thousands of actual items. Leave a Star if you will ⭐

## Features
- Lazy loading items
- Auto-calculation of visible items (Or use a fixed value)
- Synchronized scrollbar
- Focus management with keyboard navigation
- Recycling/Caching items

## Installation
- Download the plugin from the Asset Library or GitHub
- Extract to your project's addons/ folder

# Usage

## Step 1: Create the LazyListBox
- Open your "Main Scene" and create a `CanvasLayer`, then drop the `lazy_list_box.tscn` into it.
- You will see a `LazyListBox` control

## Step 2: Prepare your Item Template
- Create an `item_template.tscn`. Make sure you choose the `Button` type in the `New Scene` dialog. This will represent your item in the `LazyListBox` later. Add again a button to the newly created `item_template.tscn` set the `Anchor Preset` to `Full Rect` if you will. (Now we have two Buttons, like this):
```
ItemTemplate (Button-Type)
└──Button (Button-Type)
```
**Ensure: ItemTemplate is for this example a Button-Type.**

**Recommended: The root node in your ItemTemplate should be always a Button so that focus calls work properly.**


Make sure the ItemTemplate node has:
- The `Flat` property set to `true` in your inspector
- has a minimum size that is not `0` (Layout -> Custom Minimum Size -> `Y > 0` in your Inspector). For this example, use `Y=50`.


Attach the following script (`my_item_template.gd`) to `ItemTemplate`-Button in `item_template.tscn` and look at the `_on_button_down` method to understand how we access the data:


```gdscript
# my_item_template.gd
extends Button # Change this to your preferend control type.

# Store the original data and index for later use
var item_data
var item_index: int = -1

@onready var button: Button = $Button

func _ready():
	assert(button != null, "Assign the button in the  `item_template.tscn` for this example.")
	focus_mode = Control.FOCUS_ALL
	# EXAMPLE: Access data
	button.button_down.connect(_on_button_down)

# EXAMPLE: Access data
func _on_button_down():
	# Print both the displayed text and original data
	print("Button clicked - Index: ", item_index, " Data: ", item_data, " Text: ", button.text)

# This is called by LazyListBox: to configure the item
func configure_item(index: int, data):
	item_index = index
	item_data = data
	button.text = str(data)  # Display the data as button text

# This is called by LazyListBox: to set the data
func set_data(data):
	item_data = data
```
Don't forget to assign the `Button`
```
ItemTemplate <---- Make sure your button below is assigned to `my_item_template.gd` script.
└──Button 
```

## Step 3: Assign your Item Template to the LazyListBox
- Open your "Main Scene" and select the LazyListBox node
- Look at your Inspector; there is a field called `Item Template`
- Drop your `item_template.tscn` into that `<empty>` field or choose the `item_template.tscn` manually.

## Step 4: Simple Test with Fake Data
- Open your "Main Scene", create a `Node` wherever you want, and attach the following script below. This script will generate 500 objects, but you can go much higher.

```gdscript
extends Node

@export var lazy_list: LazyListBox

func _ready():
	assert(lazy_list != null, "Assign the lazy_list control! It's usually the lazy_list_box.tscn you dropped in your scene.")
	# Create simple test data with 500 items
	var test_data = []
	for i in range(500):
		test_data.append("Item " + str(i))
	# Set the data
	lazy_list.set_data(test_data)
```
## Public API Methods

### Basic Operations
- `set_data(data_array: Array)` - Set the data for the list
- `refresh()` - Force refresh the entire list
- `scroll_to_index(index: int)` - Scroll to specific data index
- `scroll_to_end()` - Scroll to the end of the list

### Focus Management  
- `focus_item_at_data_index(index: int)` - Focus item at data index
- `set_focus_preservation(enabled: bool)` - Enable/disable focus preservation
- `get_virtual_focused_index() -> int` - Get currently focused data index
- `is_list_focused() -> bool` - Check if list has focus

### Configuration
- `set_auto_calculate_visible_count(enabled: bool)` - Toggle auto-calculation
- `set_manual_item_height(height: float)` - Set manual item height
- `get_visible_range() -> Vector2i` - Get range of visible indices

## Requirements
- Godot 4.4+ 
- Your item template must implement:
  - `configure_item(index: int, data)` method
  - `set_data(data)` method

## Troubleshooting

**Problem**: Items appear too small or overlapping
- **Solution**: Set Custom Minimum Size Y > 0 in your item template's root node. Lower `Y` value will result in more displayed items.

**Problem**: Focus not working
- **Solution**: Use a Button as layout element. Activate `Flate` if you will use a layout in it

**Problem**: I see no items
- **Solution**: You propably forget to add items. Look at `Step 4`. Or it's layout problem: Then make sure you followed `Step 2`.
