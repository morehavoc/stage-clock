# Stage Clock

Giant click-through countdown overlay for live talks (menu bar app, macOS 13+, universal).
Build: `./build.sh` → `build/StageClock.zip`. Ad-hoc signed (no Developer ID cert on jaws-mini),
so first launch on another Mac: right-click → Open, or `xattr -cr "/Applications/Stage Clock.app"`.

Settings: minutes, start now or at a set time (a slot already underway joins in progress and still
ends on time), display, corner, color, size, optional dark plate, chime at 0:00. Overtime counts up
as `+0:12`, flashing. Hotkeys (any app): ⌃⌥⌘S start/pause, ⌃⌥⌘R reset, ⌃⌥⌘H hide, ⌃⌥⌘= / ⌃⌥⌘- ±1 min.
