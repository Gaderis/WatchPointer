import AppKit

setvbuf(stdout, nil, _IONBF, 0) // show log lines immediately

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar app: no Dock icon, no center notch

let live = Live()
if !live.accessibilityGranted {
    live.refreshAccessibility(prompt: true)
    print("Grant Accessibility access to WatchPointer (System Settings › Privacy & Security › Accessibility).")
}

let receiver = Receiver(live: live)
let menuBar = MenuBarController(live: live)
withExtendedLifetime((receiver, menuBar)) {
    app.run()
}
