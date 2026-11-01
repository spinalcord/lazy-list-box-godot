# LazyListBox regression checks

Use Godot 4.5 or newer from the repository root:

```sh
godot --headless --path . --script tests/test_initialization.gd
godot --headless --path . --script tests/test_list.gd
godot --headless --path . --script tests/test_load_more.gd
godot --path . --rendering-method gl_compatibility --script tests/test_pointer.gd
```

The initialization suite checks direct construction with pending data, scene
reuse, missing content and existing children without scene ownership. It also
checks layout, recycling and focus. Expect exactly two runtime-fallback warnings:
one in `direct` and one in `missing_content`, with no further warnings during
scrolling or refresh and none in `scene` or `existing_children`.

The pointer suite opens a real window and injects events through its Viewport.
It enables touch emulation only in that test process. It checks taps, wheel,
scrollbar dragging, drags over recycled buttons, inertia and interruption,
with both visible and hidden scrollbars. It also checks native hover after
wheel/programmatic scrolling, recycling and settled inertia, including unchanged
scroll positions and no extra clicks. For hover checks it positions the system
pointer in the test window, then leaves it stationary while scrolling; avoid
moving the mouse during the suite. It does not change project settings.

Validated locally with Godot 4.7 stable. A separate Godot 4.5 runtime was not
available. Physical mobile-device and human gesture acceptance remain pending;
use the demo and the checklist in the main README.

The load more suite checks default-disabled loading, empty startup after
`fully_ready`, partial rows, threshold zero, resize and zero-sized viewports.
It checks count-based request locking, equal-size updates, refresh, synchronous
short-page chaining, retry, and suppression when disabled or at the data end.
It instantiates both demo scenes and runs the load more demo with
`simulated_delay = 0.0` through its intentional page-2 error, Retry and all 250
entries, checking preserved scroll position and bounded pool size.

Open each scene for window acceptance:

```sh
godot --path . --rendering-method gl_compatibility res://addons/lazy_list_box/demos/basic_example/demo.tscn
godot --path . --rendering-method gl_compatibility res://addons/lazy_list_box/demos/load_more_example/demo.tscn
```

In the basic demo, check the 500 entries, wheel/keyboard scrolling and item event
output after resizing. In the load more demo, observe the initial empty state,
loading status, 50-entry pages, the error on page 2 and the Retry button. Click
Retry, keep scrolling, and confirm the count reaches 250 and the end status
appears. Resize both windows and confirm labels remain readable and the list
fills the remaining space. The basic scene remains the project main scene.
