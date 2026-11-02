import AppKit
import PortsCore
import ServiceManagement

// The agent runs this at launch, because linking ServiceManagement there would keep it in memory for good.
if CommandLine.arguments.dropFirst().first == enableLoginArgument {
    // Only once, so someone who turns it off stays off. Only once installed, because a login item
    // pointing at a download or a disk image would break when that moves.
    if !loginItemWasEnabled(), isInstalled(Bundle.main.bundlePath), (try? SMAppService.mainApp.register()) != nil {
        setLoginItemWasEnabled()
    }
    exit(0)
}

// Started by the menu bar agent when its icon is clicked, and exits when the popover closes.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = PanelApp(arguments: CommandLine.arguments)
app.delegate = delegate
app.run()
