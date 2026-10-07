// Stage Clock — a giant, click-through countdown overlay for live talks.
// Menu bar app (no Dock icon). Build: ./build.sh
import Cocoa
import Carbon.HIToolbox

// MARK: - Settings

enum Corner: Int, CaseIterable {
    case topRight, topLeft, bottomRight, bottomLeft
    var title: String { ["Top right", "Top left", "Bottom right", "Bottom left"][rawValue] }
}

enum TextColor: Int, CaseIterable {
    case red, yellow, white, green
    var title: String { ["Red", "Yellow", "White", "Green"][rawValue] }
    var color: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 1.0, green: 0.12, blue: 0.10, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.0, alpha: 1)
        case .white: return .white
        case .green: return NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.35, alpha: 1)
        }
    }
}

struct Prefs {
    static let d = UserDefaults.standard
    static func register() {
        d.register(defaults: [
            "minutes": 30, "startAtTime": false, "startMinuteOfDay": 9 * 60,
            "corner": Corner.topRight.rawValue, "color": TextColor.red.rawValue,
            "fontSize": 160.0, "backing": false, "chime": true, "displayID": 0,
        ])
    }
    static var minutes: Int { get { max(1, d.integer(forKey: "minutes")) } set { d.set(newValue, forKey: "minutes") } }
    static var startAtTime: Bool { get { d.bool(forKey: "startAtTime") } set { d.set(newValue, forKey: "startAtTime") } }
    static var startMinuteOfDay: Int { get { d.integer(forKey: "startMinuteOfDay") } set { d.set(newValue, forKey: "startMinuteOfDay") } }
    static var corner: Corner { get { Corner(rawValue: d.integer(forKey: "corner")) ?? .topRight } set { d.set(newValue.rawValue, forKey: "corner") } }
    static var color: TextColor { get { TextColor(rawValue: d.integer(forKey: "color")) ?? .red } set { d.set(newValue.rawValue, forKey: "color") } }
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

// MARK: - Overlay window

final class OverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let plate = NSView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // clicks go straight through to whatever is underneath
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Above full-screen apps, Keynote/PowerPoint slideshows and screen savers.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let cv = NSView()
        cv.wantsLayer = true
        contentView = cv
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        cv.addSubview(plate)
        label.lineBreakMode = .byClipping
        label.alignment = .center
        cv.addSubview(label)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func render(_ text: String, alpha: CGFloat) {
        let size = Prefs.fontSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = size * 0.06
        shadow.shadowOffset = .zero
        let attr = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: Prefs.color.color.withAlphaComponent(alpha),
            .strokeColor: NSColor.black.withAlphaComponent(max(alpha, 0.6)),
            .strokeWidth: -3.0,          // negative = fill AND outline, readable on any background
            .shadow: shadow,
        ])
        label.attributedStringValue = attr
        // Measure the string itself (+ room for outline and glow); NSTextField's intrinsic size clips it.
        let raw = attr.size()
        let textSize = NSSize(width: ceil(raw.width + size * 0.12), height: ceil(raw.height + size * 0.04))
        let padX = Prefs.backing ? size * 0.18 : size * 0.06
        let padY = Prefs.backing ? size * 0.06 : size * 0.02
        let w = ceil(textSize.width + padX * 2), h = ceil(textSize.height + padY * 2)
        label.frame = NSRect(x: padX, y: padY, width: textSize.width, height: textSize.height)
        plate.isHidden = !Prefs.backing
        plate.frame = NSRect(x: 0, y: 0, width: w, height: h)
        plate.layer?.cornerRadius = size * 0.12

        let vf = chosenScreen().visibleFrame
        let margin: CGFloat = 24
        var origin = NSPoint.zero
        switch Prefs.corner {
        case .topRight: origin = NSPoint(x: vf.maxX - w - margin, y: vf.maxY - h - margin)
        case .topLeft: origin = NSPoint(x: vf.minX + margin, y: vf.maxY - h - margin)
        case .bottomRight: origin = NSPoint(x: vf.maxX - w - margin, y: vf.minY + margin)
        case .bottomLeft: origin = NSPoint(x: vf.minX + margin, y: vf.minY + margin)
        }
        let f = NSRect(origin: origin, size: NSSize(width: w, height: h))
        if f != frame { setFrame(f, display: true) }
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
                                               object: nil, queue: .main) { [weak self] _ in self?.tick() }
        ticker = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker!, forMode: .common)

        let args = ProcessInfo.processInfo.arguments
        if args.contains("--start-now") { start(atTime: false) } else { openSettings() }
        tick()
    }

    // MARK: actions

    @objc func startFromSettings() { start(atTime: Prefs.startAtTime) }

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
        settings?.window?.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
        tick()
    }

    func windowWillClose(_ n: Notification) { DispatchQueue.main.async { self.tick() } }

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
        var show = !hidden
        let blink = Int(Date().timeIntervalSince1970 * 2) % 2 == 0
        switch state {
        case .idle: show = show && settingsOpen; alpha = 0.85        // live preview while setting up
        case .scheduled: alpha = 0.45
        case .paused: alpha = blink ? 1 : 0.35
        case .running:
            if r <= 10 { alpha = blink ? 1 : 0.3 }                   // last 10 s and overtime flash
            if r <= 0, !chimed { chimed = true; if Prefs.chime { NSSound(named: "Glass")?.play() } }
        }
        if show {
            overlay.render(text, alpha: alpha)
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
        let s = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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
    let colorPopup = NSPopUpButton()
    let sizeSlider = NSSlider()
    let backingBox = NSButton(checkboxWithTitle: "Dark plate behind the numbers", target: nil, action: nil)
    let chimeBox = NSButton(checkboxWithTitle: "Chime at 0:00", target: nil, action: nil)

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Stage Clock"
        w.isReleasedWhenClosed = false
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

        colorPopup.addItems(withTitles: TextColor.allCases.map(\.title))
        colorPopup.selectItem(at: Prefs.color.rawValue)
        colorPopup.target = self; colorPopup.action = #selector(changed)

        sizeSlider.minValue = 48; sizeSlider.maxValue = 400
        sizeSlider.doubleValue = Double(Prefs.fontSize)
        sizeSlider.isContinuous = true
        sizeSlider.target = self; sizeSlider.action = #selector(changed)

        backingBox.state = Prefs.backing ? .on : .off
        backingBox.target = self; backingBox.action = #selector(changed)
        chimeBox.state = Prefs.chime ? .on : .off
        chimeBox.target = self; chimeBox.action = #selector(changed)

        let grid = NSGridView(views: [
            [label("Countdown:"), minutesRow],
            [label("Start:"), startRow],
            [label("Display:"), displayPopup],
            [label("Corner:"), cornerPopup],
            [label("Color:"), colorPopup],
            [label("Size:"), sizeSlider],
            [NSGridCell.emptyContentView, backingBox],
            [NSGridCell.emptyContentView, chimeBox],
        ])
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        sizeSlider.widthAnchor.constraint(equalToConstant: 220).isActive = true

        let hint = NSTextField(wrappingLabelWithString:
            "Hotkeys work from any app: ⌃⌥⌘S start/pause · ⌃⌥⌘R reset · ⌃⌥⌘H hide · ⌃⌥⌘= / ⌃⌥⌘- add/remove a minute.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let startButton = NSButton(title: "Start", target: app, action: #selector(AppDelegate.startFromSettings))
        startButton.keyEquivalent = "\r"
        let quit = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        let buttons = NSStackView(views: [quit, NSView(), startButton])

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

    @objc func stepped() { minutesField.integerValue = minutesStepper.integerValue; changed() }

    @objc func changed() {
        Prefs.minutes = max(1, minutesField.integerValue)
        minutesStepper.integerValue = Prefs.minutes
        Prefs.startAtTime = startMode.indexOfSelectedItem == 1
        let comps = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        Prefs.startMinuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if let t = displayPopup.selectedItem?.tag { Prefs.displayID = UInt32(t) }
        Prefs.corner = Corner(rawValue: cornerPopup.indexOfSelectedItem) ?? .topRight
        Prefs.color = TextColor(rawValue: colorPopup.indexOfSelectedItem) ?? .red
        Prefs.fontSize = CGFloat(sizeSlider.doubleValue)
        Prefs.backing = backingBox.state == .on
        Prefs.chime = chimeBox.state == .on
        sync()
        app?.tick()
    }

    func sync() { timePicker.isEnabled = startMode.indexOfSelectedItem == 1 }
}

// MARK: - main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
