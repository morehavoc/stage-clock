# Stage Clock

Giant click-through countdown overlay for live talks (Dock app + menu bar timer, macOS 13+, universal).
Build: `./build.sh` → `build/StageClock.zip` (icon: `make-icon.swift` → `AppIcon.icns`, committed).
Ad-hoc signed (no Developer ID cert on jaws-mini), so a browser download is quarantined and macOS 15+
blocks it (right-click → Open no longer bypasses; System Settings → Privacy & Security → Open Anyway).
Install that avoids it (curl sets no quarantine):
`pkill -x StageClock; curl -fsSL https://jaws-mini.daggertooth-uaru.ts.net/public/StageClock-1.2.zip -o /tmp/StageClock.zip && rm -rf "/Applications/Stage Clock.app" && ditto -xk /tmp/StageClock.zip /Applications && open "/Applications/Stage Clock.app"`

1.2: Dock app (1.1 was menu-bar-only; its menu bar item can sit behind a MacBook notch), newest
launch quits any older running copy (two copies drew two stacked clocks), panel opens on the
pointer's display and the current Space (incl. over full-screen apps — not verified), overlay
survives "Hide Others" (`canHide = false`).

Control panel (shows at launch; click the Dock icon, open the app again, or use the menu bar clock to get it back;
Start/Pause/Resume, Reset, ±1 min). Settings: minutes, start now or at a set time (a slot already underway joins in progress and still
ends on time), display, corner, typeface + style (any installed family), size, color, halo
(None/Fine/Medium/Bold), optional dark plate, chime at 0:00.

Rendering (1.1): digits are Core Text glyph outlines drawn as vector paths, figures centred in
fixed cells (tabular in any face), colon/plus optically centred on the figure height, baseline
snapped to the pixel grid, halo = round-joined stroke under the fill. 1.0 used a text field with
a blurred shadow, a centred stroke (miter spikes) and a fractional offset, which read as fuzzy.
`StageClock --specimen out.png` renders the typeface sheet; `--test-seconds N` starts at N s. Overtime counts up
as `+0:12`, flashing. Hotkeys (any app): ⌃⌥⌘S start/pause, ⌃⌥⌘R reset, ⌃⌥⌘H hide, ⌃⌥⌘= / ⌃⌥⌘- ±1 min.
