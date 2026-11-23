import AppKit
import CoreBluetooth
import Foundation

// Must match the watch app.
let serviceUUID = CBUUID(string: "6B1E0001-9F4C-4C2A-9B8E-3D2A1C0F5E01")
let inputUUID = CBUUID(string: "6B1E0002-9F4C-4C2A-9B8E-3D2A1C0F5E01")
/// The watch subscribes to this; subscribing and unsubscribing tell the Mac exactly when it connects and
/// disconnects. Nothing is sent on it, so all of the Bluetooth link is left for the watch's samples.
let outputUUID = CBUUID(string: "6B1E0003-9F4C-4C2A-9B8E-3D2A1C0F5E01")

/// Tapping the watch jolts it, so clicks land where the pointer was at the moment the thumb touched down
/// (the watch sends that time). Older watch builds don't, so then it's this long before the click arrived.
let fallbackRewind = 0.1

/// Packets from the watch: [kind, Int16 LE a, Int16 LE b].
/// `.aim`: hundredths of a degree from "Center" (a = turned left, b = tipped up), then UInt16 LE: when the watch
/// measured it, in ms on its own clock (wraps). Older watch builds send no time; arrival time is used then.
/// `.pause`: a = 1 paused, 0 resumed.
/// `.info`: [kind, JSON] describing the watch (see WatchInfo), not the fixed 5 bytes.
/// `.drag`: a = 1 grab (mouse down), 0 drop (mouse up).
/// Clicks and drags may add the same UInt16 ms time as `.aim`: when the thumb touched down (or lifted, for a drop).
enum Kind: UInt8 { case aim = 0, leftClick = 1, rightClick = 2, scroll = 3, center = 4, pause = 5, info = 6, drag = 7 }

/// 1€ filter (Casiez et al. 2012): heavy smoothing when the hand is nearly still (no jitter),
/// almost none when it moves fast (no lag). The standard choice for pointing devices.
/// Needs the real time between samples; feeding it bursty arrival times makes it shake and lag.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff = 1.0
    private var value: Double?
    private var velocity = 0.0

    init(minCutoff: Double = 0.8, beta: Double = 0.01) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func callAsFunction(_ x: Double, dt: Double) -> Double {
        guard let previous = value, dt > 0 else { value = x; return x }
        func alpha(_ cutoff: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }
        velocity += alpha(derivativeCutoff) * ((x - previous) / dt - velocity)
        let smoothed = previous + alpha(minCutoff + beta * abs(velocity)) * (x - previous)
        value = smoothed
        return smoothed
    }

    mutating func reset() { value = nil; velocity = 0 }
}

/// Everything that moves the cursor runs on its own high-priority queue, so UI updates on the
/// main thread can never delay it. Only display values hop to the main thread.
final class Receiver: NSObject, CBPeripheralManagerDelegate {
    private let live: Live
    private let queue = DispatchQueue(label: "WatchPointer.pointer", qos: .userInteractive)
    private var manager: CBPeripheralManager!
    private var askedForLowLatency = false

    // Pointer state (only touched on `queue`).
    private var phase = Live.Phase.waiting
    private var watchInfo: WatchInfo?
    private var reachDegrees: Double
    private var filterX: OneEuroFilter
    private var filterY: OneEuroFilter
    private var target: CGPoint?   // filtered position from the latest watch sample
    private var shown = CGPoint.zero
    private var lastSample = 0.0   // arrival time, only to notice the watch going quiet
    private var lastWatchMs: UInt16?
    private var watchClock = 0.0       // the watch's clock (s), unwrapped from the 16-bit ms in each sample
    private var clockOffset: Double?   // Mac time minus watch time, from the quickest-arriving sample
    private var aimLeft = 0.0, aimUp = 0.0
    private var lastLog = 0.0
    private var frames = 0
    private var samplesThisSecond = 0
    private var rate = 0
    private var frameTimer: DispatchSourceTimer?
    private var history: [(time: Double, point: CGPoint)] = [] // where the cursor was, last ~1 s
    private var dragging = false

    init(live: Live) {
        self.live = live
        self.reachDegrees = 25.0 / max(live.speed, 0.2)
        self.filterX = OneEuroFilter(minCutoff: live.steady, beta: live.quick)
        self.filterY = OneEuroFilter(minCutoff: live.steady, beta: live.quick)
        super.init()
        live.onSettingsChanged = { [weak self] speed, steady, quick in
            self?.updateSettings(speed: speed, steady: steady, quick: quick)
        }
        manager = CBPeripheralManager(delegate: self, queue: queue)
        queue.async { self.startFrameLoop() }
    }

    func updateSettings(speed: Double, steady: Double, quick: Double) {
        queue.async {
            self.reachDegrees = 25.0 / max(speed, 0.2)
            self.filterX.minCutoff = steady
            self.filterX.beta = quick
            self.filterY.minCutoff = steady
            self.filterY.beta = quick
        }
    }

    /// UI values live on the main thread.
    private func ui(_ change: @escaping (Live) -> Void) {
        DispatchQueue.main.async { [live] in change(live) }
    }

    private func setPhase(_ new: Live.Phase, toast: Live.Toast? = nil) {
        phase = new
        ui { live in
            live.phase = new
            if let toast { live.show(toast) }
        }
    }

    // MARK: Bluetooth

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            let note: String = switch peripheral.state {
            case .unauthorized: "請在系統設定開啟藍牙權限"
            case .poweredOff: "Mac 藍牙已關閉"
            case .unsupported: "此 Mac 不支援 BLE 周邊模式"
            default: "藍牙準備中…"
            }
            ui {
                $0.bluetoothReady = false
                $0.bluetoothNote = note
            }
            print("Bluetooth not ready (state \(peripheral.state.rawValue)). Turn it on / allow access.")
            return
        }
        let input = CBMutableCharacteristic(type: inputUUID, properties: [.writeWithoutResponse, .write],
                                            value: nil, permissions: [.writeable])
        let output = CBMutableCharacteristic(type: outputUUID, properties: [.notify], value: nil, permissions: [.readable])
        let service = CBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [input, output]
        peripheral.removeAllServices()
        peripheral.add(service)
        // The Mac's own name ("Sam's MacBook Pro"), so the watch's pairing list says which Mac this is.
        let name = String((Host.current().localizedName ?? "Mac").prefix(24))
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
                                     CBAdvertisementDataLocalNameKey: name])
        ui {
            $0.bluetoothReady = true
            $0.bluetoothNote = "藍牙廣播中（\(name)）"
        }
        print("Advertising. Open WatchPointer on your Apple Watch.")
    }

    /// The watch's Bluetooth link closed (app quit, out of range, watch asleep long enough to drop it).
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        drop()
        watchInfo = nil
        ui { $0.watch = nil } // don't keep showing an old battery level or model
        if phase != .waiting {
            log("watch disconnected")
            setPhase(.idle, toast: .lost) // also ends a "Paused" that would otherwise never clear
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        if !askedForLowLatency, let watch = requests.first?.central {
            askedForLowLatency = true
            // Ask for the shortest Bluetooth interval, so samples arrive as often as possible.
            peripheral.setDesiredConnectionLatency(.low, for: watch)
        }
        for request in requests {
            if let data = request.value { handle(data) }
        }
        if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
    }

    private func handle(_ data: Data) {
        let d = Data(data) // re-base so indices start at 0
        if d.first == Kind.info.rawValue {
            if let info = try? JSONDecoder().decode(WatchInfo.self, from: d.dropFirst()), info != watchInfo {
                if watchInfo?.model != info.model { log("\(info.modelName) (\(info.model)), watchOS \(info.os)") }
                watchInfo = info
                ui { $0.watch = info }
            }
            return
        }
        guard d.count >= 5, let kind = Kind(rawValue: d[0]) else { return }
        let a = Int16(bitPattern: UInt16(d[1]) | UInt16(d[2]) << 8)
        let b = Int16(bitPattern: UInt16(d[3]) | UInt16(d[4]) << 8)
        switch kind {
        case .aim:
            let ms = d.count >= 7 ? UInt16(d[5]) | UInt16(d[6]) << 8 : nil
            aim(left: Double(a) / 100, up: Double(b) / 100, watchMs: ms)
        case .leftClick: log("click"); ui { $0.clicks += 1 }; click(.left, at: when(d))
        case .rightClick: log("right click"); ui { $0.clicks += 1 }; click(.right, at: when(d))
        case .center: log("centered"); ui { $0.show(.centered) }
        case .drag: a != 0 ? grab(at: when(d)) : drop(at: when(d))
        case .pause:
            let paused = a != 0
            if paused { drop() }
            log(paused ? "paused" : "resumed")
            setPhase(paused ? .paused : .live, toast: paused ? .paused : .resumed)
        case .info: break // handled above
        case .scroll:
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(a), wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
    }

    // MARK: Aim → cursor

    /// Projects the aim onto the screen the way a laser pointer hits a flat wall.
    private func aim(left: Double, up: Double, watchMs: UInt16?) {
        let screen = CGDisplayBounds(CGMainDisplayID())
        let h = min(max(-left, -80), 80) * .pi / 180
        let v = min(max(up, -80), 80) * .pi / 180
        let pixelsPerUnit = screen.width / 2 / tan(reachDegrees * .pi / 180)
        let x = screen.midX + tan(h) * pixelsPerUnit
        let y = screen.midY - tan(v) / cos(h) * pixelsPerUnit

        let now = ProcessInfo.processInfo.systemUptime
        let fresh = now - lastSample > 0.3
        if fresh { // first sample after a pause: start fresh, don't glide from the old spot
            filterX.reset(); filterY.reset()
            shown = CGPoint(x: x, y: y)
        }
        if phase == .waiting || phase == .idle {
            log("watch connected")
            setPhase(.live, toast: .connected)
        }
        // Time between measurements on the watch. A sample the link dropped just makes this gap longer.
        var dt = now - lastSample
        if let watchMs {
            if let previous = lastWatchMs, !fresh {
                dt = Double(watchMs &- previous) / 1000
                watchClock += dt
            } else {
                watchClock = Double(watchMs) / 1000
                clockOffset = nil
            }
            // Line the two clocks up using the sample that arrived quickest (least Bluetooth delay).
            clockOffset = min(clockOffset ?? .infinity, now - watchClock)
        }
        lastWatchMs = watchMs
        lastSample = now
        samplesThisSecond += 1
        aimLeft = left
        aimUp = up
        guard dt > 0, dt < 0.2 else { target = CGPoint(x: filterX(x, dt: 0), y: filterY(y, dt: 0)); return }
        target = CGPoint(x: filterX(x, dt: dt), y: filterY(y, dt: dt))
    }

    /// Moves the cursor 240 times a second, gliding toward the newest sample. That's faster than any display,
    /// so every screen refresh gets a fresh position, and the steps between Bluetooth samples don't show.
    private func startFrameLoop() {
        let frame = 1.0 / 240
        let follow = 1 - exp(-frame / 0.005) // ~5 ms catch-up
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: frame, leeway: .microseconds(200))
        timer.setEventHandler { [weak self] in self?.tick(follow: follow) }
        timer.resume()
        frameTimer = timer
    }

    private func tick(follow: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        frames += 1
        if frames % 240 == 0 { // once a second
            rate = samplesThisSecond
            samplesThisSecond = 0
            let rate = rate
            ui { $0.rate = rate }
        }
        guard let target else { return }
        guard now - lastSample < 0.3 else { // watch idle: leave the trackpad alone
            drop() // never leave the button held down if the watch goes quiet mid-drag
            if phase == .live, now - lastSample > 1.5 {
                log("watch lost")
                setPhase(.idle, toast: .lost)
            }
            return
        }
        let next = CGPoint(x: shown.x + (target.x - shown.x) * follow, y: shown.y + (target.y - shown.y) * follow)
        guard abs(next.x - shown.x) + abs(next.y - shown.y) > 0.05 else { return }
        shown = next
        // Every display is reachable, laid out as in System Settings › Displays. Pointing past the outer
        // edge pins the cursor to the nearest display; coming back lines up again.
        let p = Displays.clamp(next)
        post(dragging ? .leftMouseDragged : .mouseMoved, p)
        history.append((now, p))
        while let first = history.first, now - first.time > 1 { history.removeFirst() }
        if frames % 16 == 0 { // 15 Hz is plenty for the notch; more just keeps the main thread busy
            let screen = Displays.bounds(containing: p)
            let spot = CGPoint(x: (p.x - screen.minX) / screen.width, y: (p.y - screen.minY) / screen.height)
            let (left, up) = (aimLeft, aimUp)
            ui { live in
                live.pointer = spot
                live.aimLeft = left
                live.aimUp = up
            }
        }
        if now - lastLog > 0.1 { // one line that rewrites itself, 10× a second
            lastLog = now
            print(String(format: "\rpointer %5.0f, %5.0f   %3d samples/s   ", p.x, p.y, rate), terminator: "")
        }
    }

    private func log(_ text: String) { print("\n\(text)") }

    // MARK: Clicks and drag

    /// The Mac time a click or drag packet refers to, from the watch time it carries (nil for older watch builds).
    private func when(_ d: Data) -> Double? {
        guard d.count >= 7, let last = lastWatchMs, let clockOffset else { return nil }
        let ms = UInt16(d[5]) | UInt16(d[6]) << 8
        let sinceLastSample = Double(Int16(bitPattern: ms &- last)) / 1000 // may be slightly before or after it
        return watchClock + sinceLastSample + clockOffset
    }

    /// Where to press: while the watch is steering, where the pointer was at `time` (touch-down, before the tap
    /// jolted the watch). Otherwise just the current cursor.
    private func pressPoint(at time: Double?) -> CGPoint {
        let current = CGEvent(source: nil)?.location ?? .zero
        let now = ProcessInfo.processInfo.systemUptime
        let moment = time ?? now - fallbackRewind
        guard phase == .live, now - lastSample < 0.3,
              let before = history.last(where: { $0.time <= moment }) ?? history.first else { return current }
        shown = before.point
        return before.point
    }

    private func post(_ type: CGEventType, _ p: CGPoint, _ button: CGMouseButton = .left) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)?.post(tap: .cghidEventTap)
    }

    private func click(_ button: CGMouseButton, at time: Double?) {
        let p = pressPoint(at: time)
        post(dragging ? .leftMouseDragged : .mouseMoved, p)
        let (down, up): (CGEventType, CGEventType) = button == .left ? (.leftMouseDown, .leftMouseUp)
                                                                     : (.rightMouseDown, .rightMouseUp)
        post(down, p, button)
        post(up, p, button)
    }

    /// Mouse down where the pointer was when the thumb pressed; following aim then drags.
    private func grab(at time: Double?) {
        guard !dragging else { return }
        let p = pressPoint(at: time ?? ProcessInfo.processInfo.systemUptime - 0.45)
        post(.mouseMoved, p)
        post(.leftMouseDown, p)
        dragging = true
        log("grab")
    }

    /// Mouse up where the pointer was just before the thumb lifted.
    private func drop(at time: Double? = nil) {
        guard dragging else { return }
        let p = pressPoint(at: time)
        post(.leftMouseDragged, p)
        post(.leftMouseUp, p)
        dragging = false
        log("drop")
    }
}
