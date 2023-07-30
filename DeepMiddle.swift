import Cocoa
import ApplicationServices
import Foundation

let requiredEvent = CGEventType(rawValue: 29)!
let selectedAppsFilePath = NSString(string: "~/Library/Application Support/DeepMiddle/selectedApps.txt").expandingTildeInPath

var needIgnoreNextLeftMouseUp = false
var selectedApps: Set<String> = []

class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        loadSelectedApps()
        populateMenuWithRunningApps()
    }

    func setupStatusBarItem() {
        statusItem.button?.title = "DeepMiddle"
        statusItem.menu = menu
    }

    func loadSelectedApps() {
        if FileManager.default.fileExists(atPath: selectedAppsFilePath) {
            do {
                let fileContents = try String(contentsOfFile: selectedAppsFilePath)
                let lines = fileContents.split(separator: "\n")
                for line in lines {
                    selectedApps.insert(String(line))
                }
            } catch {
                print("Failed to load selected apps from file")
            }
        }
    }

    func populateMenuWithRunningApps() {
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let appName = app.localizedName {
                let menuItem = NSMenuItem(title: appName, action: #selector(toggleApp), keyEquivalent: "")
                menuItem.state = selectedApps.contains(appName) ? .on : .off
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleApp(_ sender: NSMenuItem) {
        if sender.state == .on {
            sender.state = .off
            selectedApps.remove(sender.title)
        } else {
            sender.state = .on
            selectedApps.insert(sender.title)
        }
        saveSelectedApps()
    }

    func saveSelectedApps() {
        do {
            try FileManager.default.createDirectory(atPath: (selectedAppsFilePath as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: nil)

            let fileContents = selectedApps.joined(separator: "\n")
            try fileContents.write(toFile: selectedAppsFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save selected apps to file")
        }
    }
}

func myCGEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if shouldIgnoreNextLeftMouseUp(type) {
        return nil
    }
    if type != requiredEvent { return Unmanaged.passRetained(event) }

    let nsEvent = NSEvent(cgEvent: event)!
    if shouldIgnoreNextLeftMouseUp(nsEvent.stage) {
        return nil
    }
    if needIgnoreNextLeftMouseUp {
        needIgnoreNextLeftMouseUp = false
        return nil
    }
    guard let targetApp = getTargetApp(event) else { return Unmanaged.passRetained(event) }
    if !selectedApps.contains(targetApp) { return Unmanaged.passRetained(event) }

    if nsEvent.type == .pressure && nsEvent.stage == 2 {
        if nsEvent.pressure > 0.000 {
            return nil
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let mousePos = event.location
        let clickDown = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: mousePos, mouseButton: .left)!
        let clickUp = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: mousePos, mouseButton: .left)!

        clickDown.flags = [.maskCommand]
        clickUp.flags = [.maskCommand]
        clickDown.post(tap: .cghidEventTap)
        needIgnoreNextLeftMouseUp = true
        return Unmanaged.passRetained(clickUp)
    }

    return Unmanaged.passRetained(event)
}

func shouldIgnoreNextLeftMouseUp(_ typeOrStageValue:Any) -> Bool{
    return needIgnoreNextLeftMouseUp && (typeOrStageValue as? CGEventType == .leftMouseUp || typeOrStageValue as? CGEventType == .leftMouseDown || typeOrStageValue as? Int != 0)
}

func getTargetApp(_ eventRef : CGEvent) -> String? {
    var procName = CChar)
    if proc_name(pid_t(eventRef.getIntegerValueField(.eventTargetUnixProcessID)), &procName, UInt32(procName.count)) == 0 {
        return nil
    }
    return String(cString: procName)
}

let eventMask = (1 << requiredEvent.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDown.rawValue)

guard let eventTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(eventMask), callback: myCGEventCallback, userInfo: nil) else {
    print("Failed to create event tap")
    exit(1)
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap, enable: true)

let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
