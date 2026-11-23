import AppKit
import Combine
import SwiftUI

// MARK: - Menu Bar Popover UI

struct MenuBarPopoverView: View {
    @ObservedObject var live: Live
    let onOpenAccessibility: () -> Void
    let onOpenGame: () -> Void
    let onQuit: () -> Void

    @State private var showTuning = false

    private var statusColor: Color {
        switch live.phase {
        case .live: .green
        case .paused, .idle: .orange
        case .waiting: .secondary
        }
    }

    private var statusLabel: String {
        if let toast = live.toast {
            switch toast {
            case .connected: return "手錶已連線"
            case .centered: return "已重新置中"
            case .paused: return "已暫停操控"
            case .resumed: return "已恢復操控"
            case .lost: return "連線已中斷"
            }
        }
        switch live.phase {
        case .live: return "操控中"
        case .paused: return "已暫停"
        case .idle: return "待機中"
        case .waiting: return live.bluetoothReady ? "等待手錶連線" : live.bluetoothNote
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Watch title + connection pill + battery
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: live.phase == .live ? "applewatch.radiowaves.left.and.right" : "applewatch")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(live.watch.map { $0.name.isEmpty ? $0.modelName : $0.name } ?? "WatchPointer")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if let watch = live.watch {
                        Text(watch.name.isEmpty ? watch.subtitle : "\(watch.modelName) · \(watch.subtitle)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(live.bluetoothNote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }

            // Accessibility warning banner if permission not granted yet
            if !live.accessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("需要「輔助使用」權限才能移動游標")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("請在系統設定開啟 WatchPointer")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("前往設定", action: onOpenAccessibility)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(9)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Live aim map + telemetry
            HStack(spacing: 14) {
                ScreenMap(pointer: live.pointer, active: live.phase == .live)
                    .frame(width: 146, height: 92)
                    .padding(6)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    statRow("arrow.left.and.right", "左右", live.phase == .live ? String(format: "%+.1f°", -live.aimLeft) : "–")
                    statRow("arrow.up.and.down", "上下", live.phase == .live ? String(format: "%+.1f°", live.aimUp) : "–")
                    statRow("waveform", "頻率", live.phase == .live ? "\(live.rate) Hz" : "–")
                    statRow(batterySymbol, "電量", live.watch.map { $0.battery < 0 ? "–" : "\($0.battery)%" } ?? "–")
                }
                Spacer(minLength: 0)
            }

            Divider()

            // Collapsible sensitivity & smoothing controls
            DisclosureGroup(isExpanded: $showTuning) {
                VStack(alignment: .leading, spacing: 8) {
                    sliderRow(title: "移動速度", value: $live.speed, range: 0.5...2.5, step: 0.05,
                              display: String(format: "%.2f×", live.speed))
                    sliderRow(title: "靜止防抖", value: $live.steady, range: 0.2...2.0, step: 0.05,
                              display: String(format: "%.2f", live.steady))
                    sliderRow(title: "快速響應", value: $live.quick, range: 0.002...0.05, step: 0.002,
                              display: String(format: "%.3f", live.quick))

                    HStack {
                        Spacer()
                        Button("恢復預設值") { live.resetTuning() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
                .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Text("指標靈敏度與平滑設定")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(String(format: "%.2f×", live.speed))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            // Footer actions
            HStack(spacing: 8) {
                Button(action: onOpenGame) {
                    Label("試玩瞄準遊戲", systemImage: "gamecontroller")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button(action: onQuit) {
                    Text("退出")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(14)
        .frame(width: 344)
    }

    private var batterySymbol: String {
        guard let watch = live.watch, watch.battery >= 0 else { return "battery.0percent" }
        if watch.charging { return "battery.100percent.bolt" }
        return switch watch.battery {
        case 88...: "battery.100percent"
        case 63..<88: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }

    private func statRow(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 15)
                .foregroundStyle(.secondary)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .monospacedDigit()
                .fontWeight(.medium)
        }
        .font(.system(size: 11.5))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(display).font(.system(size: 11)).monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
        }
    }
}

/// A tiny picture of the screen with the pointer where the watch is aiming.
struct ScreenMap: View {
    let pointer: CGPoint
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let display = MacDisplay().path(in: CGRect(origin: .zero, size: size))
            context.fill(display, with: .color(Color.primary.opacity(0.16)))
            guard active else { return }
            let c = CGPoint(x: pointer.x * size.width, y: pointer.y * size.height)
            let arrow = context.resolve(Text(Image(systemName: "cursorarrow")).font(.system(size: 13)).foregroundStyle(.primary))
            context.draw(arrow, at: CGPoint(x: c.x - 3, y: c.y - 1), anchor: .topLeading)
        }
    }
}

// MARK: - Menu Bar Controller

/// Native macOS menu bar icon + popover (replaces the center notch overlay).
final class MenuBarController: NSObject {
    private let live: Live
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var cancellables: Set<AnyCancellable> = []
    private var axTimer: Timer?
    private var eventMonitor: Any?

    init(live: Live) {
        self.live = live
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(
                live: live,
                onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
                onOpenGame: { [weak self] in self?.openGame() },
                onQuit: { NSApp.terminate(nil) }
            )
        )

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleStatusBarClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "WatchPointer"
        }

        updateStatusIcon()

        live.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        live.$accessibilityGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        // Periodically check Accessibility status until granted so the banner clears immediately.
        axTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            if granted != self.live.accessibilityGranted {
                self.live.accessibilityGranted = granted
            }
        }

        // Close popover when clicking outside (extra safety on macOS accessory apps).
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
    }

    deinit {
        axTimer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch live.phase {
        case .live:
            symbolName = "applewatch.radiowaves.left.and.right"
        case .paused:
            symbolName = "applewatch.slash"
        case .waiting, .idle:
            symbolName = "applewatch"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WatchPointer")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.alphaValue = (live.phase == .waiting || live.phase == .idle) ? 0.72 : 1.0
    }

    @objc private func handleStatusBarClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            live.refreshAccessibility(prompt: false)
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        let menu = NSMenu()
        let title = live.phase == .live ? "WatchPointer：操控中" : "WatchPointer：等待連線"
        let statusEntry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        statusEntry.isEnabled = false
        menu.addItem(statusEntry)
        menu.addItem(.separator())

        if !live.accessibilityGranted {
            let axItem = NSMenuItem(title: "開啟「輔助使用」設定…", action: #selector(openAccessibilityMenuAction), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
        }

        let gameItem = NSMenuItem(title: "試玩瞄準小遊戲 (Sky Shot)", action: #selector(openGameMenuAction), keyEquivalent: "")
        gameItem.target = self
        menu.addItem(gameItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 WatchPointer", action: #selector(quitMenuAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openAccessibilityMenuAction() { openAccessibilitySettings() }
    @objc private func openGameMenuAction() { openGame() }
    @objc private func quitMenuAction() { NSApp.terminate(nil) }

    private func openAccessibilitySettings() {
        live.refreshAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openGame() {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL {
            candidates.append(res.appendingPathComponent("Game/index.html"))
        }
        // Walk up from the executable path to find Game/index.html when running via `swift run`.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            candidates.append(dir.appendingPathComponent("Game/index.html"))
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }
            dir = parent
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Game/index.html"))
        candidates.append(cwd.deletingLastPathComponent().appendingPathComponent("Game/index.html"))

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            if popover.isShown { popover.performClose(nil) }
            return
        }
    }
}
