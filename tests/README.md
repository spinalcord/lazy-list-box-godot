# LazyListBox regression checks

Use Godot 4.5 or newer from the repository root:

```sh
godot --headless --path . --script tests/test_list.gd
godot --path . --rendering-method gl_compatibility --script tests/test_pointer.gd
```

The pointer suite opens a real window and injects events through its Viewport.
It enables touch emulation only in that test process. It checks taps, wheel,
scrollbar dragging, drags over recycled buttons, inertia and interruption,
with both visible and hidden scrollbars. It does not change project settings.

Validated locally with Godot 4.7 stable. A separate Godot 4.5 runtime was not
available. Physical mobile-device and human gesture acceptance remain pending;
use the demo and the checklist in the main README.
