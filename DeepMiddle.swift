import Cocoa
import Foundation

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let requiredEvent = CGEventType(rawValue: 29)!
var requiredProcNames: Set<String> = ["Google Chrome"]

var needIgnoreNextLeftMouseUp = false

func myCGEventCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if needIgnoreNextLeftMouseUp, type == .leftMouseUp || type == .leftMouseDown {
        return nil
    }

    if type != requiredEvent {
        return Unmanaged.passRetained(event)
    }

    let nsEvent = NSEvent(cgEvent: event)!
    if needIgnoreNextLeftMouseUp, nsEvent.stage != 0 {
        return nil
    }

    if needIgnoreNextLeftMouseUp {
        needIgnoreNextLeftMouseUp = false
        return nil
    }

    let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let frontmostAppName = NSRunningApplication(processIdentifier: frontmostAppPID!)?.localizedName

    if !requiredProcNames.contains(frontmostAppName!) {
        return Unmanaged.passRetained(event)
    }

    if nsEvent.type == .pressure, nsEvent.stage == 2 {
        if nsEvent.pressure > 0.000 {
            return nil
        }

        let src = CGEventSource(stateID: .hidSystemState)
        let mousePos = event.location
        let clickDown = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: mousePos, mouseButton: .left)
        let clickUp = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: mousePos, mouseButton: .left)

        clickDown?.flags = [.maskCommand]
        clickUp?.flags = [.maskCommand]
        clickDown?.post(tap: .cghidEventTap)
        needIgnoreNextLeftMouseUp = true
        return Unmanaged.passRetained(clickUp!)
    }

    return Unmanaged.passRetained(event)
}

var eventMask = CGEventMask(1 << requiredEvent.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
let eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: eventMask, callback: myCGEventCallback, userInfo: nil)

if eventTap == nil {
    print("failed to create event tap")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap!, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap!, enable: true)

// Add button to status bar
let statusBar = NSStatusBar.system
let statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "DeepMiddle"

// Create menu for status bar button
let menu = NSMenu()
statusItem.menu = menu

// Get list of user-installed apps and add them to the menu
let fileManager = FileManager.default
let applicationsDirectoryURLs = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)
for directoryURL in applicationsDirectoryURLs {
    do {
        let applicationURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for applicationURL in applicationURLs {
            let appName = applicationURL.lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let menuItem = NSMenuItem(title: appName, action: #selector(AppDelegate.toggleApp(_:)), keyEquivalent: "")
            menuItem.target = NSApp.delegate
            menuItem.state = requiredProcNames.contains(appName) ? .on : .off
            menu.addItem(menuItem)
        }
    } catch {
        print(error.localizedDescription)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func toggleApp(_ sender: NSMenuItem) {
        let appName = sender.title
        if requiredProcNames.contains(appName) {
            requiredProcNames.remove(appName)
            sender.state = .off
        } else {
            requiredProcNames.insert(appName)
            sender.state = .on
        }
    }
}

let delegate = AppDelegate()
app.delegate = delegate

print("Start handling deep clicks in selected apps")
app.run()
