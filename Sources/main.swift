import Cocoa
import IOKit.pwr_mgt

// DisplayOff: blank the display without sleeping it, so macOS never locks the screen.
// Sets backlight brightness to 0 (DisplayServices, works for Apple/Thunderbolt displays)
// and blanks the gamma table (works on any display, invisible to screen capture).

typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32

final class DisplayServices {
    private let get: GetBrightnessFn?
    private let set: SetBrightnessFn?
    init() {
        let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        get = h.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightnessFn.self) }
        set = h.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightnessFn.self) }
    }
    func brightness(_ id: CGDirectDisplayID) -> Float? {
        guard let get = get else { return nil }
        var v: Float = 0
        return get(id, &v) == 0 ? v : nil
    }
    func setBrightness(_ id: CGDirectDisplayID, _ v: Float) {
        _ = set?(id, v)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let ds = DisplayServices()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var saved: [CGDirectDisplayID: Float] = [:]
    var assertions: [IOPMAssertionID] = []
    var monitor: Any?
    var isOff = false
    var offAt = Date.distantPast
    var includeBuiltIn = UserDefaults.standard.bool(forKey: "includeBuiltIn")
    var powerMode = UserDefaults.standard.object(forKey: "powerMode") as? Bool ?? true
    var pollTimer: Timer?
    var wakeOnInput = UserDefaults.standard.object(forKey: "wakeOnInput") as? Bool ?? true

    func applicationDidFinishLaunching(_ n: Notification) {
        updateUI()
        if CommandLine.arguments.contains("--off") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.turnOff() }
        }
        // Re-apply if displays are reconfigured (e.g. Thunderbolt re-plug) while off.
        CGDisplayRegisterReconfigurationCallback({ _, flags, info in
            guard flags.contains(.setModeFlag) || flags.contains(.addFlag) else { return }
            let d = Unmanaged<AppDelegate>.fromOpaque(info!).takeUnretainedValue()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if d.isOff { d.blank() } }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func targets() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).filter { includeBuiltIn || CGDisplayIsBuiltin($0) == 0 }
    }

    func blank() {
        for id in targets() {
            if saved[id] == nil, let b = ds.brightness(id) { saved[id] = b }
            ds.setBrightness(id, 0)
            CGSetDisplayTransferByFormula(id, 0, 0, 1, 0, 0, 1, 0, 0, 1)
        }
    }

    func turnOff() {
        guard !isOff else { return }
        isOff = true
        offAt = Date()
        // Keep the Mac (and display "awake" state) from idling, so no lock is triggered.
        for type in [kIOPMAssertPreventUserIdleSystemSleep, kIOPMAssertPreventUserIdleDisplaySleep] {
            var a: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "DisplayOff: display blanked" as CFString, &a)
            assertions.append(a)
        }
        if powerMode {
            powerOff()
            updateUI()
            return
        }
        blank()
        if wakeOnInput {
            // Only real hardware input (source pid 0) wakes; synthetic events from automation don't.
            monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] e in
                guard let self = self, Date().timeIntervalSince(self.offAt) > 1.5 else { return }
                if e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) == 0 { self.turnOn() }
            }
        }
        updateUI()
    }

    // Real power-off: keep a virtual display so macOS (and screen capture) still has a screen,
    // then put the physical display into DDC standby. It is woken with its own power button.
    func powerOff() {
        guard DOBridge.startVirtualDisplay() else {
            NSLog("DisplayOff: virtual display failed, falling back to blanking")
            powerMode = false
            blank()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isOff else { return }
            let n = DOBridge.standbyAllExternal()
            NSLog("DisplayOff: DDC standby sent to %d display(s)", n)
            self.offAt = Date()
            // The physical display reappears (external DDC service returns) when its button is pressed.
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self = self, Date().timeIntervalSince(self.offAt) > 5 else { return }
                if DOBridge.externalDDCCount() > 0 { self.turnOn() }
            }
        }
    }

    func turnOn() {
        guard isOff else { return }
        isOff = false
        pollTimer?.invalidate(); pollTimer = nil
        DOBridge.stopVirtualDisplay()
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        CGDisplayRestoreColorSyncSettings()
        for (id, b) in saved { ds.setBrightness(id, b) }
        saved.removeAll()
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        updateUI()
    }

    @objc func toggle() { isOff ? turnOn() : turnOff() }
    @objc func togglePower() {
        let wasOff = isOff; turnOn()
        powerMode.toggle(); UserDefaults.standard.set(powerMode, forKey: "powerMode")
        if wasOff { turnOff() } else { updateUI() }
    }
    @objc func toggleBuiltIn() {
        let wasOff = isOff; turnOn()
        includeBuiltIn.toggle(); UserDefaults.standard.set(includeBuiltIn, forKey: "includeBuiltIn")
        if wasOff { turnOff() } else { updateUI() }
    }
    @objc func toggleWake() {
        let wasOff = isOff; turnOn()
        wakeOnInput.toggle(); UserDefaults.standard.set(wakeOnInput, forKey: "wakeOnInput")
        if wasOff { turnOff() } else { updateUI() }
    }
    @objc func quit() { turnOn(); NSApp.terminate(nil) }

    func updateUI() {
        statusItem.button?.title = isOff ? "◼︎" : "◻︎"
        let menu = NSMenu()
        menu.addItem(withTitle: isOff ? "Display On" : "Display Off (no lock)", action: #selector(toggle), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let p = menu.addItem(withTitle: "Power off via DDC + virtual display", action: #selector(togglePower), keyEquivalent: "")
        p.target = self; p.state = powerMode ? .on : .off
        let b = menu.addItem(withTitle: "Include built-in display", action: #selector(toggleBuiltIn), keyEquivalent: "")
        b.target = self; b.state = includeBuiltIn ? .on : .off
        let w = menu.addItem(withTitle: "Wake on physical mouse/keyboard", action: #selector(toggleWake), keyEquivalent: "")
        w.target = self; w.state = wakeOnInput ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
