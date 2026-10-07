// Stage Clock — a giant, click-through countdown overlay for live talks.
// Menu bar app (no Dock icon). Build: ./build.sh
//
// The digits are drawn as vector glyph outlines (Core Text paths), not through a text field:
// figures sit in fixed-width cells so nothing shifts as they change, the colon and plus are
// optically centred on the figure height, the baseline is snapped to the pixel grid, and the
// halo is a crisp round-joined stroke laid UNDER the fill (the cartographic halo) — never a
// blurred shadow, which is what made v1.0 look fuzzy.
import Cocoa
import Carbon.HIToolbox
import CoreText

// MARK: - Settings

enum Corner: Int, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft
    var title: String { ["Top right", "Top left", "Bottom right", "Bottom left"][rawValue] }
}

enum Halo: Int, CaseIterable {
    case none, fine, medium, bold
    var title: String { ["None", "Fine", "Medium", "Bold"][rawValue] }
    /// Visible halo width outside the glyph outline, as a fraction of the font size.
    var fraction: CGFloat { [0, 0.018, 0.03, 0.045][rawValue] }
}

let haloColor = CGColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 0.9)

let systemFamilies: [(name: String, design: NSFontDescriptor.SystemDesign)] = [
    ("SF Pro", .default), ("SF Pro Rounded", .rounded), ("SF Mono", .monospaced), ("New York", .serif),
]
let systemWeights: [(name: String, weight: NSFont.Weight)] = [
    ("Light", .light), ("Regular", .regular), ("Medium", .medium), ("Semibold", .semibold),
    ("Bold", .bold), ("Heavy", .heavy), ("Black", .black),
]

func styles(ofFamily family: String) -> [String] {
    if systemFamilies.contains(where: { $0.name == family }) { return systemWeights.map(\.name) }
    return (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { $0[1] as? String }
}

func isInstalled(family: String) -> Bool {
    systemFamilies.contains(where: { $0.name == family }) || NSFontManager.shared.availableFontFamilies.contains(family)
}

func makeFont(family: String, style: String, size: CGFloat) -> NSFont {
    if let sys = systemFamilies.first(where: { $0.name == family }) {
        let weight = systemWeights.first(where: { $0.name == style })?.weight ?? .bold
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(sys.design), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }
    let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
    if let m = members.first(where: { ($0[1] as? String) == style }) ?? members.first,
       let ps = m[0] as? String, let f = NSFont(name: ps, size: size) { return f }
    return NSFont.systemFont(ofSize: size, weight: .bold)
}

func color(hex: String) -> NSColor? {
    guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                   blue: CGFloat(v & 255) / 255, alpha: 1)
}

func hex(of c: NSColor) -> String? {
    guard let s = c.usingColorSpace(.sRGB) else { return nil }
    func b(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "%02X%02X%02X", b(s.redComponent), b(s.greenComponent), b(s.blueComponent))
}

struct Prefs {
    static let d = UserDefaults.standard
    /// Bumped on every settings change so the overlay knows to re-render.
    static var stamp = 0
    static func register() {
        d.register(defaults: [
            "minutes": 30, "startAtTime": false, "startMinuteOfDay": 9 * 60,
            "corner": Corner.topRight.rawValue, "textColorHex": "FF3B30",
            "fontFamily": "SF Pro", "fontStyle": "Bold", "halo": Halo.fine.rawValue,
            "fontSize": 160.0, "backing": false, "chime": true, "displayID": 0,
        ])
    }
    static var minutes: Int { get { max(1, d.integer(forKey: "minutes")) } set { d.set(newValue, forKey: "minutes") } }
    static var startAtTime: Bool { get { d.bool(forKey: "startAtTime") } set { d.set(newValue, forKey: "startAtTime") } }
    static var startMinuteOfDay: Int { get { d.integer(forKey: "startMinuteOfDay") } set { d.set(newValue, forKey: "startMinuteOfDay") } }
    static var corner: Corner { get { Corner(rawValue: d.integer(forKey: "corner")) ?? .topRight } set { d.set(newValue.rawValue, forKey: "corner") } }
    static var textColor: NSColor {
        get { color(hex: d.string(forKey: "textColorHex") ?? "") ?? color(hex: "FF3B30")! }
        set { if let h = hex(of: newValue) { d.set(h, forKey: "textColorHex") } }
    }
    static var fontFamily: String { get { d.string(forKey: "fontFamily") ?? "SF Pro" } set { d.set(newValue, forKey: "fontFamily") } }
    static var fontStyle: String { get { d.string(forKey: "fontStyle") ?? "Bold" } set { d.set(newValue, forKey: "fontStyle") } }
    static var halo: Halo { get { Halo(rawValue: d.integer(forKey: "halo")) ?? .fine } set { d.set(newValue.rawValue, forKey: "halo") } }
    static var fontSize: CGFloat { get { CGFloat(d.double(forKey: "fontSize")) } set { d.set(Double(newValue), forKey: "fontSize") } }
    static var backing: Bool { get { d.bool(forKey: "backing") } set { d.set(newValue, forKey: "backing") } }
    static var chime: Bool { get { d.bool(forKey: "chime") } set { d.set(newValue, forKey: "chime") } }
    static var displayID: UInt32 { get { UInt32(d.integer(forKey: "displayID")) } set { d.set(Int(newValue), forKey: "displayID") } }
}

func displayID(of screen: NSScreen) -> UInt32 {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

func chosenScreen() -> NSScreen {
    let want = Prefs.displayID
    return NSScreen.screens.first { displayID(of: $0) == want } ?? NSScreen.main ?? NSScreen.screens[0]
}

func formatClock(_ secs: Int) -> String {
    let s = abs(secs), h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

// MARK: - Clock artwork (vector glyph outlines)

struct ClockArt {
    let path: CGPath
    let width: CGFloat      // total advance: figures in fixed cells, so it only changes with the pattern
    let minY: CGFloat       // figure ink extent, relative to the baseline
    let maxY: CGFloat
    var height: CGFloat { maxY - minY }

    init(_ text: String, font: NSFont) {
        let ct = font as CTFont
        func glyph(_ c: Character) -> CGGlyph {
            var units = Array(String(c).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            CTFontGetGlyphsForCharacters(ct, &units, &glyphs, units.count)
            return glyphs[0]
        }
        func advance(_ g: CGGlyph) -> CGFloat {
            var g = g, a = CGSize.zero
            CTFontGetAdvancesForGlyphs(ct, .horizontal, &g, &a, 1)
            return a.width
        }
        func bounds(_ g: CGGlyph) -> CGRect {
            var g = g, r = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ct, .horizontal, &g, &r, 1)
            return r
        }
        let figures = "0123456789".map(glyph)
        let cell = figures.map(advance).max() ?? font.pointSize * 0.6
        let figBox = figures.map(bounds).reduce(CGRect.null) { $0.union($1) }
        minY = figBox.minY
        maxY = figBox.maxY
        let p = CGMutablePath()
        var x: CGFloat = 0
        for c in text {
            let g = glyph(c)
            var t: CGAffineTransform
            if c.isNumber {
                // Tabular by construction: every figure centred in the widest figure's cell.
                t = CGAffineTransform(translationX: x + (cell - advance(g)) / 2, y: 0)
                x += cell
            } else {
                // ':' and '+' sit on the x-height / maths axis in most faces; lift them to the figure centre.
                t = CGAffineTransform(translationX: x, y: figBox.midY - bounds(g).midY)
                x += advance(g)
            }
            if let gp = CTFontCreatePathForGlyph(ct, g, &t) { p.addPath(gp) }
        }
        path = p
        width = x
    }

    /// `baseline` is where the text baseline starts; snap it to the pixel grid before calling.
    func draw(in ctx: CGContext, baseline: CGPoint, color: CGColor, halo: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: baseline.x, y: baseline.y)
        if halo > 0 {
            ctx.addPath(path)
            ctx.setLineWidth(halo * 2)        // the inner half is covered by the fill
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.setStrokeColor(haloColor)
            ctx.strokePath()
        }
        ctx.addPath(path)
        ctx.setFillColor(color)
        ctx.fillPath()                         // non-zero winding: overlapping contours stay solid
        ctx.restoreGState()
    }
}

/// Lays the clock out in a box: returns the box size and the (pixel-snapped) baseline origin.
func layoutClock(_ art: ClockArt, size: CGFloat, halo: CGFloat, plate: Bool, scale: CGFloat) -> (CGSize, CGPoint) {
    func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
    let padX = plate ? size * 0.2 : ceil(halo) + 2
    let padY = plate ? size * 0.14 : ceil(halo) + 2
    let box = CGSize(width: ceil(art.width + padX * 2), height: ceil(art.height + padY * 2))
    let baseline = CGPoint(x: snap((box.width - art.width) / 2), y: snap((box.height - art.height) / 2 - art.minY))
    return (box, baseline)
}

func drawPlate(in ctx: CGContext, rect: CGRect, size: CGFloat) {
    let r = size * 0.14
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6))
    ctx.fillPath()
}

// MARK: - Overlay window

final class ClockView: NSView {
    var art: ClockArt?
    var baseline = CGPoint.zero
    var fill = NSColor.red.cgColor
    var halo: CGFloat = 0
    var plate = false
    var fontSize: CGFloat = 160
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let art = art else { return }
        ctx.clear(bounds)
        if plate { drawPlate(in: ctx, rect: bounds, size: fontSize) }
        art.draw(in: ctx, baseline: baseline, color: fill, halo: halo)
    }
}

final class OverlayWindow: NSPanel {
    let clock = ClockView()
    private var lastKey = ""
    private var pulsePeriod: Double?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // clicks go straight through to whatever is underneath
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        canHide = false                    // "Hide Others" in another app must not take the clock with it
        // Above full-screen apps, Keynote/PowerPoint slideshows and screen savers.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        clock.wantsLayer = true
        clock.layerContentsRedrawPolicy = .onSetNeedsDisplay
        contentView = clock
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func render(_ text: String) {
        let key = "\(text)|\(Prefs.stamp)"
        guard key != lastKey else { return }
        lastKey = key
        let screen = chosenScreen()
        let size = Prefs.fontSize
        let art = ClockArt(text, font: makeFont(family: Prefs.fontFamily, style: Prefs.fontStyle, size: size))
        let halo = Prefs.halo.fraction * size
        let (box, baseline) = layoutClock(art, size: size, halo: halo, plate: Prefs.backing,
                                          scale: screen.backingScaleFactor)
        clock.art = art
        clock.baseline = baseline
        clock.fill = Prefs.textColor.cgColor
        clock.halo = halo
        clock.plate = Prefs.backing
        clock.fontSize = size

        let vf = screen.visibleFrame
        let m = max(16, (size * 0.15).rounded())
        let o: NSPoint
        switch Prefs.corner {
        case .topRight: o = NSPoint(x: vf.maxX - box.width - m, y: vf.maxY - box.height - m)
        case .topLeft: o = NSPoint(x: vf.minX + m, y: vf.maxY - box.height - m)
        case .bottomRight: o = NSPoint(x: vf.maxX - box.width - m, y: vf.minY + m)
        case .bottomLeft: o = NSPoint(x: vf.minX + m, y: vf.minY + m)
        }
        // Whole points = whole pixels at 1x and 2x, so the backing store is never resampled.
        let f = NSRect(x: o.x.rounded(), y: o.y.rounded(), width: box.width, height: box.height)
        if f != frame { setFrame(f, display: false) }
        clock.needsDisplay = true
    }

    /// Static opacity, plus an optional smooth pulse (Core Animation, so it runs at display rate).
    func setLook(alpha: CGFloat, pulse: Double?) {
        if clock.alphaValue != alpha { clock.alphaValue = alpha }
        guard pulse != pulsePeriod, let layer = clock.layer else { return }
        pulsePeriod = pulse
        layer.removeAnimation(forKey: "pulse")
        if let p = pulse {
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 1.0
            a.toValue = 0.25
            a.duration = p / 2
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(a, forKey: "pulse")
        }
    }
}

// MARK: - Global hotkeys (Carbon: no Accessibility permission needed)

var hotKeyHandlers: [UInt32: () -> Void] = [:]

func installHotKeys(_ keys: [(Int, () -> Void)]) {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
        var id = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        DispatchQueue.main.async { hotKeyHandlers[id.id]?() }
        return noErr
    }, 1, &spec, nil, nil)
    for (i, (key, handler)) in keys.enumerated() {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5354_434B), id: UInt32(i + 1))
        RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey | controlKey), id,
                            GetApplicationEventTarget(), 0, &ref)
        hotKeyHandlers[UInt32(i + 1)] = handler
    }
}

// MARK: - Clock state

enum ClockState {
    case idle
    case scheduled(start: Date, duration: TimeInterval)
    case running(end: Date)
    case paused(remaining: TimeInterval)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let overlay = OverlayWindow()
    var statusItem: NSStatusItem!
    var state = ClockState.idle
    var hidden = false
    var chimed = false
    var ticker: Timer?
    var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ n: Notification) {
        Prefs.register()
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--specimen"), i + 1 < args.count {
            renderSpecimen(to: args[i + 1])
            exit(0)
        }
        // Newest launch wins: an older copy (or another version) still running would draw a second clock.
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        others.forEach { $0.terminate() }
        if !others.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() } }
        }
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        installHotKeys([
            (kVK_ANSI_S, { [weak self] in self?.startPauseResume() }),
            (kVK_ANSI_R, { [weak self] in self?.reset() }),
            (kVK_ANSI_H, { [weak self] in self?.toggleHidden() }),
            (kVK_ANSI_Equal, { [weak self] in self?.adjust(by: 60) }),
            (kVK_ANSI_Minus, { [weak self] in self?.adjust(by: -60) }),
        ])

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Prefs.stamp += 1
            self?.tick()
        }
        ticker = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)

        if let i = args.firstIndex(of: "--test-seconds"), i + 1 < args.count, let s = Double(args[i + 1]) {
            state = .running(end: Date().addingTimeInterval(s))
        } else if args.contains("--start-now") {
            start(atTime: false)
        } else {
            openSettings()
        }
        tick()
    }

    /// Clicking the Dock icon, or opening the app again (Spotlight, Finder, Launchpad), brings the panel back.
    /// (1.1 was a menu-bar-only app: on a notched MacBook its menu bar item can sit behind the notch.)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// Standard app menus: Control Panel (⌘,), Quit, ⌘W and copy/paste in the panel.
    func installMainMenu() {
        let main = NSMenu()
        func sub(_ title: String, _ items: [(String, Selector, String)]) {
            let item = NSMenuItem(), menu = NSMenu(title: title)
            for (t, sel, key) in items { menu.addItem(withTitle: t, action: sel, keyEquivalent: key).target = sel == #selector(openSettings) ? self : nil }
            item.submenu = menu
            main.addItem(item)
        }
        sub("Stage Clock", [("Control Panel…", #selector(openSettings), ","),
                            ("Quit Stage Clock", #selector(NSApplication.terminate(_:)), "q")])
        sub("Edit", [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])
        sub("Window", [("Close", #selector(NSWindow.performClose(_:)), "w")])
        NSApp.mainMenu = main
    }

    // MARK: actions

    /// The panel's big button: Start → Pause → Resume. Starting or resuming tucks the panel away.
    @objc func panelPrimary() {
        switch state {
        case .idle: start(atTime: Prefs.startAtTime)
        case .scheduled: start(atTime: false)
        case .running(let end): state = .paused(remaining: end.timeIntervalSinceNow)
        case .paused(let rem):
            state = .running(end: Date().addingTimeInterval(rem))
            settings?.window?.close()
        }
        tick()
    }

    func start(atTime: Bool) {
        let duration = TimeInterval(Prefs.minutes * 60)
        chimed = false
        hidden = false
        if atTime {
            let cal = Calendar.current
            var start = cal.startOfDay(for: Date()).addingTimeInterval(TimeInterval(Prefs.startMinuteOfDay * 60))
            // Slot already over today → it means tomorrow. Slot already underway → join it in progress,
            // so the clock still ends when the slot ends.
            if start.addingTimeInterval(duration) <= Date() { start = cal.date(byAdding: .day, value: 1, to: start)! }
            state = start <= Date() ? .running(end: start.addingTimeInterval(duration))
                                    : .scheduled(start: start, duration: duration)
        } else {
            state = .running(end: Date().addingTimeInterval(duration))
        }
        settings?.window?.close()
        tick()
    }

    @objc func startPauseResume() {
        switch state {
        case .idle, .scheduled: start(atTime: false)
        case .running(let end): state = .paused(remaining: end.timeIntervalSinceNow)
        case .paused(let rem): state = .running(end: Date().addingTimeInterval(rem))
        }
        tick()
    }

    @objc func reset() { state = .idle; chimed = false; tick() }
    @objc func toggleHidden() { hidden.toggle(); tick() }
    @objc func addMinute() { adjust(by: 60) }
    @objc func subMinute() { adjust(by: -60) }

    func adjust(by secs: TimeInterval) {
        switch state {
        case .running(let end): state = .running(end: end.addingTimeInterval(secs))
        case .paused(let rem): state = .paused(remaining: rem + secs)
        case .scheduled(let s, let d): state = .scheduled(start: s, duration: max(60, d + secs))
        case .idle: Prefs.minutes = max(1, Prefs.minutes + Int(secs / 60))
        }
        if remaining > 0 { chimed = false }
        tick()
    }

    @objc func openSettings() {
        if settings == nil { settings = SettingsWindowController(app: self) }
        guard let w = settings?.window else { return }
        w.delegate = self
        if !w.isVisible {
            // Open on the display the pointer is on (laptop vs projector), in the upper middle.
            w.layoutIfNeeded()
            let mouse = NSEvent.mouseLocation
            if let vf = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
                w.setFrameOrigin(NSPoint(x: (vf.midX - w.frame.width / 2).rounded(),
                                         y: (vf.minY + vf.height * 0.6 - w.frame.height / 2).rounded()))
            }
        }
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()      // even if macOS declines to activate us, the panel comes to the front
        tick()
    }

    func windowWillClose(_ n: Notification) {
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
        DispatchQueue.main.async { self.tick() }
    }

    var settingsOpen: Bool { settings?.window?.isVisible ?? false }

    var remaining: TimeInterval {
        switch state {
        case .idle: return TimeInterval(Prefs.minutes * 60)
        case .scheduled(_, let d): return d
        case .running(let end): return end.timeIntervalSinceNow
        case .paused(let rem): return rem
        }
    }

    // MARK: render

    func clockText() -> String {
        let r = remaining
        if r > 0 { return formatClock(Int(ceil(r))) }
        let over = Int(-r)
        return over == 0 ? "0:00" : "+" + formatClock(over)
    }

    func tick() {
        if case .scheduled(let start, let d) = state, start <= Date() {
            state = .running(end: start.addingTimeInterval(d))
        }
        let text = clockText()
        let r = remaining
        var alpha: CGFloat = 1
        var pulse: Double?
        var show = !hidden
        switch state {
        case .idle: show = show && settingsOpen          // live preview while setting up
        case .scheduled: alpha = 0.45
        case .paused: pulse = 2.4
        case .running:
            if r <= 10 { pulse = 1.0 }                    // last 10 s and overtime
            if r <= 0, !chimed { chimed = true; if Prefs.chime { NSSound(named: "Glass")?.play() } }
        }
        if show {
            overlay.render(text)
            overlay.setLook(alpha: alpha, pulse: pulse)
            if !overlay.isVisible { overlay.orderFrontRegardless() }
        } else if overlay.isVisible {
            overlay.orderOut(nil)
        }

        var title: String
        switch state {
        case .idle: title = "⏱"
        case .scheduled(let s, _):
            let f = DateFormatter(); f.timeStyle = .short
            title = "⏱ at \(f.string(from: s))"
        case .paused: title = "⏸ \(text)"
        case .running: title = "⏱ \(text)"
        }
        if hidden, case .idle = state {} else if hidden { title += " (hidden)" }
        if statusItem.button?.title != title { statusItem.button?.title = title }
        if settingsOpen { settings?.refresh(state) }
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ t: String, _ sel: Selector?, _ key: String = "", enabled: Bool = true) {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key)
            i.keyEquivalentModifierMask = [.control, .option, .command]
            i.target = self
            i.isEnabled = enabled
            menu.addItem(i)
        }
        let primary: String
        switch state {
        case .idle: primary = "Start \(Prefs.minutes) min now"
        case .scheduled: primary = "Start now instead"
        case .running: primary = "Pause"
        case .paused: primary = "Resume"
        }
        add(primary, #selector(startPauseResume), "s")
        menu.addItem(.separator())
        for m in [5, 10, 15, 20, 30, 45, 60] {
            let i = NSMenuItem(title: "Start \(m) min", action: #selector(quickStart(_:)), keyEquivalent: "")
            i.target = self; i.tag = m
            menu.addItem(i)
        }
        menu.addItem(.separator())
        add("Add 1 minute", #selector(addMinute), "=")
        add("Remove 1 minute", #selector(subMinute), "-")
        add(hidden ? "Show clock" : "Hide clock", #selector(toggleHidden), "h")
        add("Reset", #selector(reset), "r")
        menu.addItem(.separator())
        let s = NSMenuItem(title: "Control Panel…", action: #selector(openSettings), keyEquivalent: "")
        s.target = self
        menu.addItem(s)
        menu.addItem(NSMenuItem(title: "Quit Stage Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func quickStart(_ sender: NSMenuItem) {
        Prefs.minutes = sender.tag
        start(atTime: false)
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController {
    weak var app: AppDelegate?
    let minutesField = NSTextField()
    let minutesStepper = NSStepper()
    let startMode = NSPopUpButton()
    let timePicker = NSDatePicker()
    let displayPopup = NSPopUpButton()
    let cornerPopup = NSPopUpButton()
    let familyPopup = NSPopUpButton()
    let stylePopup = NSPopUpButton()
    let colorWell = NSColorWell(style: .minimal)
    let haloPopup = NSPopUpButton()
    let sizeSlider = NSSlider()
    let backingBox = NSButton(checkboxWithTitle: "Dark plate behind the numbers", target: nil, action: nil)
    let chimeBox = NSButton(checkboxWithTitle: "Chime at 0:00", target: nil, action: nil)
    let primaryButton = NSButton(title: "Start", target: nil, action: nil)

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Stage Clock " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        w.isReleasedWhenClosed = false
        // Follow him to whichever Space he is on, including over a full-screen app.
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: w)
        build()
        w.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s); l.alignment = .right; return l
    }

    func build() {
        let fmt = NumberFormatter(); fmt.minimum = 1; fmt.maximum = 600; fmt.allowsFloats = false
        minutesField.formatter = fmt
        minutesField.integerValue = Prefs.minutes
        minutesField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        minutesField.target = self; minutesField.action = #selector(changed)
        minutesStepper.minValue = 1; minutesStepper.maxValue = 600; minutesStepper.increment = 1
        minutesStepper.integerValue = Prefs.minutes
        minutesStepper.target = self; minutesStepper.action = #selector(stepped)
        let minutesRow = NSStackView(views: [minutesField, minutesStepper, NSTextField(labelWithString: "minutes")])

        startMode.addItems(withTitles: ["Now, when I press Start", "At a set time"])
        startMode.selectItem(at: Prefs.startAtTime ? 1 : 0)
        startMode.target = self; startMode.action = #selector(changed)
        timePicker.datePickerElements = .hourMinute
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.dateValue = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(TimeInterval(Prefs.startMinuteOfDay * 60))
        timePicker.target = self; timePicker.action = #selector(changed)
        let startRow = NSStackView(views: [startMode, timePicker])

        for s in NSScreen.screens { displayPopup.addItem(withTitle: s.localizedName); displayPopup.lastItem?.tag = Int(displayID(of: s)) }
        displayPopup.selectItem(withTag: Int(displayID(of: chosenScreen())))
        displayPopup.target = self; displayPopup.action = #selector(changed)

        cornerPopup.addItems(withTitles: Corner.allCases.map(\.title))
        cornerPopup.selectItem(at: Prefs.corner.rawValue)
        cornerPopup.target = self; cornerPopup.action = #selector(changed)

        for f in systemFamilies { familyPopup.addItem(withTitle: f.name) }
        familyPopup.menu?.addItem(.separator())
        for fam in NSFontManager.shared.availableFontFamilies.sorted()
        where !fam.hasPrefix(".") && !systemFamilies.contains(where: { $0.name == fam }) {
            familyPopup.addItem(withTitle: fam)
        }
        familyPopup.selectItem(withTitle: isInstalled(family: Prefs.fontFamily) ? Prefs.fontFamily : "SF Pro")
        familyPopup.target = self; familyPopup.action = #selector(familyChanged)
        familyPopup.widthAnchor.constraint(equalToConstant: 170).isActive = true
        reloadStyles(preferring: Prefs.fontStyle)
        stylePopup.target = self; stylePopup.action = #selector(changed)
        let typeRow = NSStackView(views: [familyPopup, stylePopup])

        sizeSlider.minValue = 48; sizeSlider.maxValue = 400
        sizeSlider.doubleValue = Double(Prefs.fontSize)
        sizeSlider.isContinuous = true
        sizeSlider.target = self; sizeSlider.action = #selector(changed)

        colorWell.color = Prefs.textColor
        colorWell.target = self; colorWell.action = #selector(changed)
        haloPopup.addItems(withTitles: Halo.allCases.map(\.title))
        haloPopup.selectItem(at: Prefs.halo.rawValue)
        haloPopup.target = self; haloPopup.action = #selector(changed)
        let colorRow = NSStackView(views: [colorWell, NSTextField(labelWithString: "   Halo:"), haloPopup])

        backingBox.state = Prefs.backing ? .on : .off
        backingBox.target = self; backingBox.action = #selector(changed)
        chimeBox.state = Prefs.chime ? .on : .off
        chimeBox.target = self; chimeBox.action = #selector(changed)

        let grid = NSGridView(views: [
            [label("Countdown:"), minutesRow],
            [label("Start:"), startRow],
            [label("Display:"), displayPopup],
            [label("Corner:"), cornerPopup],
            [label("Typeface:"), typeRow],
            [label("Size:"), sizeSlider],
            [label("Color:"), colorRow],
            [NSGridCell.emptyContentView, backingBox],
            [NSGridCell.emptyContentView, chimeBox],
        ])
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        sizeSlider.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let hint = NSTextField(wrappingLabelWithString:
            "Panel gone? Click Stage Clock in the Dock. "
            + "Optional hotkeys: ⌃⌥⌘S start/pause, ⌃⌥⌘H hide clock.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        primaryButton.target = app; primaryButton.action = #selector(AppDelegate.panelPrimary)
        primaryButton.keyEquivalent = "\r"
        let reset = NSButton(title: "Reset", target: app, action: #selector(AppDelegate.reset))
        let minus = NSButton(title: "−1 min", target: app, action: #selector(AppDelegate.subMinute))
        let plus = NSButton(title: "+1 min", target: app, action: #selector(AppDelegate.addMinute))
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let buttons = NSStackView(views: [quit, NSView(), reset, minus, plus, primaryButton])

        let stack = NSStackView(views: [grid, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        hint.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        window!.contentView = stack
        sync()
    }

    func reloadStyles(preferring wanted: String) {
        let list = styles(ofFamily: familyPopup.titleOfSelectedItem ?? "SF Pro")
        stylePopup.removeAllItems()
        stylePopup.addItems(withTitles: list)
        if list.contains(wanted) { stylePopup.selectItem(withTitle: wanted) }
        else if let b = list.first(where: { $0 == "Bold" }) ?? list.first(where: { $0.localizedCaseInsensitiveContains("bold") }) {
            stylePopup.selectItem(withTitle: b)
        } else { stylePopup.selectItem(at: 0) }
    }

    @objc func familyChanged() { reloadStyles(preferring: stylePopup.titleOfSelectedItem ?? "Bold"); changed() }
    @objc func stepped() { minutesField.integerValue = minutesStepper.integerValue; changed() }

    @objc func changed() {
        Prefs.minutes = max(1, minutesField.integerValue)
        minutesStepper.integerValue = Prefs.minutes
        Prefs.startAtTime = startMode.indexOfSelectedItem == 1
        let comps = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        Prefs.startMinuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if let t = displayPopup.selectedItem?.tag { Prefs.displayID = UInt32(t) }
        Prefs.corner = Corner(rawValue: cornerPopup.indexOfSelectedItem) ?? .topRight
        Prefs.fontFamily = familyPopup.titleOfSelectedItem ?? "SF Pro"
        Prefs.fontStyle = stylePopup.titleOfSelectedItem ?? "Bold"
        Prefs.textColor = colorWell.color
        Prefs.halo = Halo(rawValue: haloPopup.indexOfSelectedItem) ?? .fine
        Prefs.fontSize = CGFloat(sizeSlider.doubleValue)
        Prefs.backing = backingBox.state == .on
        Prefs.chime = chimeBox.state == .on
        Prefs.stamp += 1
        sync()
        app?.tick()
    }

    func sync() { timePicker.isEnabled = startMode.indexOfSelectedItem == 1 }

    /// Called on every tick while the panel is open.
    func refresh(_ state: ClockState) {
        let t: String
        switch state {
        case .idle: t = Prefs.startAtTime ? "Start at set time" : "Start"
        case .scheduled: t = "Start now"
        case .running: t = "Pause"
        case .paused: t = "Resume"
        }
        if primaryButton.title != t { primaryButton.title = t }
        // ±1 min while idle changes the countdown length; keep the field in step unless he is typing in it.
        if case .idle = state, minutesField.currentEditor() == nil, minutesField.integerValue != Prefs.minutes {
            minutesField.integerValue = Prefs.minutes
            minutesStepper.integerValue = Prefs.minutes
        }
    }
}

// MARK: - Specimen sheet (`StageClock --specimen out.png`): every typeface on three backdrops, 2x

func renderSpecimen(to path: String) {
    let samples: [(String, String)] = [
        ("SF Pro", "Bold"), ("SF Pro", "Heavy"), ("SF Pro Rounded", "Bold"), ("SF Mono", "Bold"),
        ("DIN Alternate", "Bold"), ("Avenir Next", "Bold"), ("Helvetica Neue", "Bold"), ("Futura", "Bold"),
    ].filter { isInstalled(family: $0.0) }
    let tileW: CGFloat = 470, tileH: CGFloat = 150, labelW: CGFloat = 190, gap: CGFloat = 14, head: CGFloat = 34
    let rows = samples.count + 1
    let W = labelW + 3 * (tileW + gap) + gap
    let H = head + CGFloat(rows) * (tileH + gap) + gap
    let scale: CGFloat = 2
    guard let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let ink = NSColor(white: 0.15, alpha: 1)
    ("Stage Clock 1.1 — specimen. Halo: Fine. Columns: dark editor · light editor · map." as NSString)
        .draw(at: NSPoint(x: gap, y: H - 24), withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink])

    let size: CGFloat = 84
    for row in 0..<rows {
        let y = H - head - CGFloat(row + 1) * (tileH + gap)
        let name = row == 0 ? "v1.0 (what you saw)" : "\(samples[row - 1].0) \(samples[row - 1].1)"
        (name as NSString).draw(in: NSRect(x: gap, y: y + tileH / 2 - 20, width: labelW - gap, height: 40),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: ink])
        for k in 0..<3 {
            let rect = CGRect(x: labelW + gap + CGFloat(k) * (tileW + gap), y: y, width: tileW, height: tileH)
            ctx.saveGState()
            ctx.clip(to: rect)
            drawBackdrop(k, in: rect, ctx: ctx)
            let m = (size * 0.15).rounded()
            if row == 0 {
                drawOldStyle("24:59", size: size, topRight: CGPoint(x: rect.maxX - m, y: rect.maxY - m))
            } else {
                let font = makeFont(family: samples[row - 1].0, style: samples[row - 1].1, size: size)
                let art = ClockArt("24:59", font: font)
                let halo = Halo.fine.fraction * size
                let (box, baseline) = layoutClock(art, size: size, halo: halo, plate: false, scale: scale)
                let origin = CGPoint(x: rect.maxX - m - box.width, y: rect.maxY - m - box.height)
                art.draw(in: ctx, baseline: CGPoint(x: origin.x + baseline.x, y: origin.y + baseline.y),
                         color: color(hex: "FF3B30")!.cgColor, halo: halo)
            }
            ctx.restoreGState()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let img = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
    print("specimen: \(path) (\(samples.map { "\($0.0) \($0.1)" }.joined(separator: ", ")))")
}

/// v1.0's styling, for the before/after row: centred black stroke + blurred shadow.
func drawOldStyle(_ text: String, size: CGFloat, topRight: CGPoint) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
    shadow.shadowBlurRadius = size * 0.06
    shadow.shadowOffset = .zero
    let attr = NSAttributedString(string: text, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.10, alpha: 1),
        .strokeColor: NSColor.black, .strokeWidth: -3.0, .shadow: shadow,
    ])
    let s = attr.size()
    attr.draw(at: NSPoint(x: topRight.x - s.width - size * 0.06, y: topRight.y - s.height))
}

func drawBackdrop(_ kind: Int, in r: CGRect, ctx: CGContext) {
    func c(_ h: String) -> NSColor { color(hex: h)! }
    if kind == 2 {
        // A small OSM-ish map: land, lake, park, minor roads, a primary road, labels.
        ctx.setFillColor(c("F2EFE9").cgColor); ctx.fill(r)
        let lake = CGMutablePath()
        lake.move(to: CGPoint(x: r.minX, y: r.minY))
        lake.addLine(to: CGPoint(x: r.minX + 120, y: r.minY))
        lake.addCurve(to: CGPoint(x: r.minX + 150, y: r.maxY), control1: CGPoint(x: r.minX + 175, y: r.minY + 60),
                      control2: CGPoint(x: r.minX + 95, y: r.minY + 100))
        lake.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        lake.closeSubpath()
        ctx.addPath(lake); ctx.setFillColor(c("AAD3DF").cgColor); ctx.fillPath()
        ctx.setFillColor(c("CDEBB0").cgColor)
        ctx.fill(CGRect(x: r.minX + 250, y: r.minY + 12, width: 110, height: 48))
        func road(_ pts: [CGPoint], casing: String, fill: String, w: CGFloat) {
            for (col, width) in [(casing, w + 2), (fill, w)] {
                ctx.beginPath(); ctx.addLines(between: pts)
                ctx.setStrokeColor(c(col).cgColor); ctx.setLineWidth(width)
                ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
            }
        }
        for i in 0..<6 {
            let x = r.minX + 190 + CGFloat(i) * 52
            road([CGPoint(x: x, y: r.minY), CGPoint(x: x + 18, y: r.maxY)], casing: "C9C2B8", fill: "FFFFFF", w: 5)
        }
        road([CGPoint(x: r.minX + 160, y: r.minY + 34), CGPoint(x: r.maxX, y: r.minY + 30)], casing: "C9C2B8", fill: "FFFFFF", w: 5)
        road([CGPoint(x: r.minX + 140, y: r.minY + 92), CGPoint(x: r.maxX, y: r.minY + 104)], casing: "C99A55", fill: "FCD6A4", w: 9)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: c("4A4A4A")]
        ("E Genesee St" as NSString).draw(at: NSPoint(x: r.minX + 205, y: r.minY + 92), withAttributes: labelAttrs)
        ctx.saveGState()
        ctx.translateBy(x: r.minX + 52, y: r.minY + 30); ctx.rotate(by: .pi / 2.3)
        ("Skaneateles Lake" as NSString).draw(at: .zero, withAttributes: [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 11), toHaveTrait: .italicFontMask),
            .foregroundColor: c("3F6E95")])
        ctx.restoreGState()
        return
    }
    let dark = kind == 0
    let palette = dark ? ["D4D4D4", "569CD6", "CE9178", "6A9955", "9CDCFE", "DCDCAA"]
                       : ["1F1F1F", "0000FF", "A31515", "008000", "001080", "795E26"]
    ctx.setFillColor(c(dark ? "1E1E1E" : "FFFFFF").cgColor); ctx.fill(r)
    let code: [[(String, Int)]] = [
        [("import ", 1), ("FeatureLayer ", 4), ("from ", 1), ("\"@arcgis/core/layers/FeatureLayer\"", 2), (";", 0)],
        [("// symbolize parcels by land-use class", 3)],
        [("const ", 1), ("parcels ", 4), ("= ", 0), ("new ", 1), ("FeatureLayer", 5), ("({", 0)],
        [("  url: ", 4), ("\"https://services.arcgis.com/…/Parcels/FeatureServer/0\"", 2), (",", 0)],
        [("  renderer: ", 4), ("uniqueValues", 5), ("(", 0), ("\"LANDUSE\"", 2), (", palette),", 0)],
        [("  labelingInfo: ", 4), ("[{ labelExpression: ", 0), ("\"$feature.OWNER\"", 2), (" }]", 0)],
        [("});", 0)],
        [("map", 4), (".add(parcels);", 0)],
        [("await ", 1), ("view", 4), (".goTo(parcels.fullExtent);", 0)],
    ]
    let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    for (i, line) in code.enumerated() {
        let s = NSMutableAttributedString()
        for (text, k) in line { s.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: c(palette[k])])) }
        s.draw(at: NSPoint(x: r.minX + 14, y: r.maxY - 24 - CGFloat(i) * 15.5))
    }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)       // a Dock icon: the one place he can always click to get the panel
app.run()
