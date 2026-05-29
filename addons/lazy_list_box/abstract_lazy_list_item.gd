@abstract class_name LazyListItem
extends Control

# Holds the raw data entry assigned to this item by LazyListBox.
var item_data: Variant
# Data index of this item in the full dataset (not the visual pool index).
var item_index: int = -1

# Emit this e.g. on selects/clicks in your template.
# This allows lazy_list_box.item_event.connect(func(index, data, action): ...).
# Use this if you want to separate design from logic rather than handling logic in the same
# scope where your lazy_list_box instance is.
signal item_event(index: int, data: Variant, action: LazyAction)

# it runs for every visible item on every scroll step. We need this to refresh displayed data
@abstract func configure_item(index: int, data: Variant) -> void
