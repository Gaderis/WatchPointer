import AppKit
import SwiftUI

/// Live state shared between the Bluetooth Receiver and the menu bar UI.
final class Live: ObservableObject {
    enum Phase { case waiting, live, paused, idle }
    enum Toast { case connected, lost, centered, paused, resumed }

    @Published var phase = Phase.waiting
    @Published var toast: Toast?
    @Published var pointer = CGPoint(x: 0.5, y: 0.5) // 0...1 across the active display
    @Published var aimLeft = 0.0                     // degrees
    @Published var aimUp = 0.0
    @Published var rate = 0                          // samples per second from the watch
    @Published var clicks = 0
    @Published var watch: WatchInfo?
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var bluetoothReady = false
    @Published var bluetoothNote = "正在初始化藍牙…"

    /// Persisted pointer tuning settings (live-updated on the Receiver queue).
    @Published var speed: Double {
        didSet {
            UserDefaults.standard.set(speed, forKey: "wp.speed")
            notifySettingsChanged()
        }
    }
    @Published var steady: Double {
        didSet {
            UserDefaults.standard.set(steady, forKey: "wp.steady")
            notifySettingsChanged()
        }
    }
    @Published var quick: Double {
        didSet {
            UserDefaults.standard.set(quick, forKey: "wp.quick")
            notifySettingsChanged()
        }
    }

    var onSettingsChanged: ((Double, Double, Double) -> Void)?
    private var clearToast: DispatchWorkItem?

    init() {
        let d = UserDefaults.standard
        let savedSpeed = d.object(forKey: "wp.speed") as? Double ?? 1.0
        let savedSteady = d.object(forKey: "wp.steady") as? Double ?? 0.8
        let savedQuick = d.object(forKey: "wp.quick") as? Double ?? 0.01

        // Preserve CLI override compatibility if launched from Terminal with flags.
        let args = CommandLine.arguments.dropFirst()
        func argSetting(_ name: String) -> Double? {
            args.first { $0.hasPrefix(name + "=") }.flatMap { Double($0.dropFirst(name.count + 1)) }
        }
        self.speed = args.lazy.compactMap(Double.init).first ?? savedSpeed
        self.steady = argSetting("steady") ?? savedSteady
        self.quick = argSetting("quick") ?? savedQuick
    }

    func resetTuning() {
        speed = 1.0
        steady = 0.8
        quick = 0.01
    }

    func refreshAccessibility(prompt: Bool = false) {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            accessibilityGranted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        } else {
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    func show(_ toast: Toast) {
        self.toast = toast
        clearToast?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        clearToast = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func notifySettingsChanged() {
        onSettingsChanged?(speed, steady, quick)
    }
}
