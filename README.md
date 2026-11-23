# WatchPointer (Menu Bar Edition)

<img src="docs/icon.png" width="96" align="right" alt="">

Use your Apple Watch as a motion-controlled air pointer for your Mac — point it at the screen to move the cursor, tap to click, hold to drag, and spin the Digital Crown to scroll.

No Wi-Fi, no servers: the watch talks straight to the Mac over Bluetooth LE.

> Based on [umarz317/WatchPointer](https://github.com/umarz317/WatchPointer) (MIT License).
> This fork replaces the center notch overlay with a **native macOS Menu Bar app (`WatchPointer.app`)**, adds live sensitivity & smoothing sliders inside the menu bar popover, and includes a one-command `.app` packager — ideal for notchless Macs (such as MacBook Air) or anyone who prefers a clean menu bar icon.

<p align="center">
  <img src="docs/demo.webp" width="320" alt="Holding an Apple Watch like a remote and pointing it at a MacBook to move the cursor">
</p>

## What's New in This Menu Bar Fork

- **Native macOS Menu Bar Icon & Popover**: No fake center notch bar. Left-click the Apple Watch icon in the top-right menu bar for the live dashboard; right-click for quick actions & Quit (`⌘Q`).
- **Live Tuning Sliders**: Adjust **Speed**, **Steady** (still-hand smoothing), and **Quick** (fast-move responsiveness) directly from the menu bar popover with instant updates and saved preferences — no Terminal flags or restart required.
- **Standalone `WatchPointer.app`**: Build and install a double-clickable `/Applications/WatchPointer.app` with one script (`./Mac/build-app.sh --install`), including built-in Accessibility permission check and one-click Sky Shot game launcher.

## What It Does

- **Point** like a laser pointer: the cursor goes where the top edge (12 o'clock) of the watch points across all connected displays.
- **Tap** the pad to click, **hold** to drag, **right-click** button, **Digital Crown** to scroll.
- **Center** re-aims the middle of the screen; **Pause** frees the cursor for your trackpad.
- **Pair** with a Mac once; the watch only connects to that Mac until you unpair it.
- **Sky Shot**, a small light-gun style browser game to test out aiming.

## Requirements

- Mac with macOS 14 or later and Bluetooth
- Apple Watch with watchOS 11 or later
- Xcode 16 or later (to build and install the watch app)

## Install & Run

### 1. Mac Menu Bar App (Recommended)

Build the standalone `.app` and install it to `/Applications`:

```bash
./Mac/build-app.sh --install
open /Applications/WatchPointer.app
```

*(You can still run it from Terminal with CLI flags if you prefer: `cd Mac && swift run WatchPointer 1.2 steady=0.6`.)*

The first time you open `WatchPointer.app`, macOS asks for **Bluetooth** and **Accessibility** access (`System Settings › Privacy & Security › Accessibility`). Allow both — Accessibility is what lets it move the cursor.

### 2. Watch App

1. Open `Watch/WatchPointer.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, select your personal Apple ID team (`Personal Team`, free account works) and change the Bundle Identifier (`com.example.watchpointer`) to something unique.
3. Make sure **Developer Mode** is enabled on both your paired iPhone and Apple Watch (`Settings › Privacy & Security › Developer Mode`).
4. Select your Apple Watch as the run destination and press **⌘R**.
5. Open **WatchPointer** on your Apple Watch and tap **Pair** next to your Mac.

### 3. Point

Hold the watch like a remote with the top edge (12 o'clock) toward the screen. Point at the middle of the screen and tap **Center** to line it up.

## Sky Shot

Click **試玩瞄準遊戲** in the menu bar popover (or open `Game/index.html` in a browser), press **F** for full screen, and tap the watch to start.

## Tips for Using It in Your Hand

On the iPhone's **Watch** app, turn off **Passcode › Wrist Detection**, or the watch locks as soon as it's off your wrist. On the watch, set **Display & Brightness › Wake Duration** to 70 seconds and **General › Return to Clock › WatchPointer** to one hour.

## How It Works

- **Watch** (`Watch/`): reads gravity and the gyroscope 100 times a second. Up/down comes from gravity, so it never drifts; left/right integrates turns around the vertical axis. Each sample carries the watch's timestamp.
- **Mac** (`Mac/`): projects the aim onto the screen like a laser hitting a wall, smooths it with a [1€ filter](https://gery.casiez.net/1euro/) using the watch's timestamps, and moves the cursor 240 times a second on its own high-priority queue. Clicks land where you were pointing the moment your thumb touched the watch, so tap jolt doesn't shift them.
- **Bluetooth**: the Mac advertises a BLE service; the watch connects and writes compact packets (`aim`, `click`, `drag`, `scroll`, `pause`, `info`). The protocol is documented at the top of `Mac/Sources/WatchPointer/Receiver.swift`.

## Security Note

Pairing is chosen on the watch. The Mac itself doesn't ask for confirmation yet, so any nearby Bluetooth device that speaks this protocol could move the cursor while the receiver is running. Quit WatchPointer from the menu bar when you're not using it.

## Credits & License

Originally created by [Umar Afzal](https://github.com/umarz317/WatchPointer).
MIT License — see [LICENSE](LICENSE).
