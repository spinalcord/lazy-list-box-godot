extends Control

@export var simulated_delay: float = 0.4

const PAGE_SIZE := 50
const TOTAL_ITEMS := 250
var entries: Array = []
var loading: bool = false
var second_page_failed: bool = false

@onready var list: LazyListBox = %LazyListBox
@onready var count_label: Label = %CountLabel
@onready var status_label: Label = %StatusLabel
@onready var retry_button: Button = %RetryButton

func _ready() -> void:
	list.load_more_requested.connect(_load_next_page)
	retry_button.pressed.connect(func():
		retry_button.hide()
		status_label.text = "Retrying..."
		list.reset_load_more_request()
	)
	list.item_event.connect(func(index: int, _data: Variant, _action: LazyAction.Emit):
		%SelectionLabel.text = "Selected item: %d" % (index + 1)
	)
	list.set_data(entries)

func _load_next_page() -> void:
	if loading:
		return
	loading = true
	retry_button.hide()
	status_label.text = "Loading next 50 items..."
	if simulated_delay > 0.0:
		await get_tree().create_timer(simulated_delay).timeout
	if entries.size() == PAGE_SIZE and not second_page_failed:
		second_page_failed = true
		loading = false
		status_label.text = "Simulated error on page 2. Click Retry to continue."
		retry_button.show()
		return
	var next_size := mini(entries.size() + PAGE_SIZE, TOTAL_ITEMS)
	for index in range(entries.size(), next_size):
		entries.append("Item %03d" % (index + 1))
	list.has_more_data = entries.size() < TOTAL_ITEMS
	loading = false
	count_label.text = "Items: %d / %d" % [entries.size(), TOTAL_ITEMS]
	status_label.text = "Scroll down to load more." if list.has_more_data else "All 250 items loaded. End of data."
	list.set_data(entries)
