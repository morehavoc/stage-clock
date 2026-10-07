# Stage Clock

Giant click-through countdown overlay for live talks (menu bar app, macOS 13+, universal).
Build: `./build.sh` → `build/StageClock.zip`. Ad-hoc signed (no Developer ID cert on jaws-mini),
so first launch on another Mac: right-click → Open, or `xattr -cr "/Applications/Stage Clock.app"`.

Settings: minutes, start now or at a set time (a slot already underway joins in progress and still
ends on time), display, corner, typeface + style (any installed family), size, color, halo
(None/Fine/Medium/Bold), optional dark plate, chime at 0:00.

Rendering (1.1): digits are Core Text glyph outlines drawn as vector paths, figures centred in
fixed cells (tabular in any face), colon/plus optically centred on the figure height, baseline
snapped to the pixel grid, halo = round-joined stroke under the fill. 1.0 used a text field with
a blurred shadow, a centred stroke (miter spikes) and a fractional offset, which read as fuzzy.
`StageClock --specimen out.png` renders the typeface sheet; `--test-seconds N` starts at N s. Overtime counts up
as `+0:12`, flashing. Hotkeys (any app): ⌃⌥⌘S start/pause, ⌃⌥⌘R reset, ⌃⌥⌘H hide, ⌃⌥⌘= / ⌃⌥⌘- ±1 min.
