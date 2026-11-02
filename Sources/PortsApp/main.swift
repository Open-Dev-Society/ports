import AppKit

// Three programs, to stay small: this menu bar agent runs all the time and links only AppKit.
// PortsPanel runs only while open, because one opening of a popover left this process at 22 MB for good.
// `ports` does the scanning and is also the terminal command.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MenuBarAgent()
app.delegate = delegate
app.run()
