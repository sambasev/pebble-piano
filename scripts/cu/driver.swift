import Foundation
import Cocoa
import ApplicationServices

/// Computer Use Driver for PerfectPiano.
/// Provides native desktop automation, window management, accessibility tree inspection,
/// pixel capture, and synthetic mouse/keyboard events on macOS.

enum DriverError: Error {
    case appNotFound
    case windowNotFound
    case elementNotFound(String)
    case actionFailed(String)
}

final class CUDriver {
    static let shared = CUDriver()

    var targetAppName = "PianoPad"
    var cachedWindowID: CGWindowID?
    var cachedWindowBounds: CGRect?

    func findApp() -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        return running.first { $0.localizedName == targetAppName || $0.bundleIdentifier?.contains("perfectpiano") == true || $0.executableURL?.lastPathComponent == targetAppName }
    }

    func findWindowInfo() -> (id: CGWindowID, bounds: CGRect)? {
        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in windowList {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if owner.contains("PianoPad") || owner.contains("PerfectPiano") {
                if let idNum = w[kCGWindowNumber as String] as? NSNumber,
                   let boundsDict = w[kCGWindowBounds as String] as? [String: Any],
                   let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
                    cachedWindowID = CGWindowID(idNum.uint32Value)
                    cachedWindowBounds = bounds
                    return (CGWindowID(idNum.uint32Value), bounds)
                }
            }
        }
        return nil
    }

    func getAXApp() -> AXUIElement? {
        guard let app = findApp() else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }

    func getAXMainWindow() -> AXUIElement? {
        guard let axApp = getAXApp() else { return nil }
        var windowsValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue)
        guard err == .success, let windows = windowsValue as? [AXUIElement], let main = windows.first else {
            return nil
        }
        return main
    }

    func setWindowGeometry(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Bool {
        guard let win = getAXMainWindow() else { return false }
        var pos = CGPoint(x: x, y: y)
        var size = CGSize(width: width, height: height)
        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return false }
        
        AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sizeVal)
        return true
    }

    func captureWindow(to path: String) -> Bool {
        guard let info = findWindowInfo() else { return false }
        let bounds = info.bounds
        let rectArg = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(Int(bounds.size.width)),\(Int(bounds.size.height))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", rectArg, path]
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Input Simulation

    func click(at screenPoint: CGPoint) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: screenPoint, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: screenPoint, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms hold
        mouseUp?.post(tap: .cghidEventTap)
    }

    func clickRelative(relX: CGFloat, relY: CGFloat) -> Bool {
        guard let info = findWindowInfo() else { return false }
        let screenPoint = CGPoint(x: info.bounds.origin.x + relX, y: info.bounds.origin.y + relY)
        click(at: screenPoint)
        return true
    }

    func pressAndHold(at screenPoint: CGPoint, durationMs: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: screenPoint, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: screenPoint, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        usleep(useconds_t(durationMs * 1000))
        mouseUp?.post(tap: .cghidEventTap)
    }

    func sendKey(code: CGKeyCode, durationMs: Int = 100) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        usleep(useconds_t(durationMs * 1000))
        keyUp?.post(tap: .cghidEventTap)
    }

    // Key mappings
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
        "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33, "escape": 0x35, "esc": 0x35,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E
    ]

    func sendKeyNamed(_ name: String, durationMs: Int = 100) -> Bool {
        guard let code = Self.keyCodes[name.lowercased()] else { return false }
        sendKey(code: code, durationMs: durationMs)
        return true
    }

    // MARK: - On-screen Piano Hit-Testing
    // C2 (36) to C6 (84). Four octaves around Middle C (C4 = 60).
    static let blackPitchClasses: Set<Int> = [1, 3, 6, 8, 10]
    static let keyboardRange: ClosedRange<Int> = 36...84

    func calculateKeyPoint(for pitch: Int, in keyboardRect: CGRect) -> CGPoint? {
        let range = Self.keyboardRange
        guard range.contains(pitch) else { return nil }

        let whites = range.filter { !Self.blackPitchClasses.contains($0 % 12) }
        guard !whites.isEmpty else { return nil }

        let edgeWidth: CGFloat = 18.0
        let spacing: CGFloat = 4.0
        let keysWidth = keyboardRect.width - (edgeWidth * 2 + spacing * 2)
        let whiteWidth = keysWidth / CGFloat(whites.count)
        let height = keyboardRect.height
        let blackWidth = whiteWidth * 0.62
        let blackHeight = height * 0.58

        let isBlack = Self.blackPitchClasses.contains(pitch % 12)
        if isBlack {
            guard let index = whites.firstIndex(of: pitch - 1) else { return nil }
            let centerX = keyboardRect.origin.x + edgeWidth + spacing + CGFloat(index + 1) * whiteWidth
            let centerY = keyboardRect.origin.y + (blackHeight * 0.5)
            return CGPoint(x: centerX, y: centerY)
        } else {
            guard let index = whites.firstIndex(of: pitch) else { return nil }
            let centerX = keyboardRect.origin.x + edgeWidth + spacing + (CGFloat(index) + 0.5) * whiteWidth
            // Click below black keys (e.g. 75% down)
            let centerY = keyboardRect.origin.y + (height * 0.75)
            return CGPoint(x: centerX, y: centerY)
        }
    }

    func clickPianoKey(pitch: Int, durationMs: Int = 200, keyboardRect: CGRect? = nil) -> Bool {
        guard let info = findWindowInfo() else { return false }
        // Default keyboard rect in standard 1200x750 layout:
        // Sits above bottom playOptions panel: roughly y = 490 to 640 in window.
        let kbRect = keyboardRect ?? CGRect(x: info.bounds.origin.x + 20,
                                            y: info.bounds.origin.y + info.bounds.height - 245,
                                            width: info.bounds.width - 40,
                                            height: 140)
        guard let pt = calculateKeyPoint(for: pitch, in: kbRect) else { return false }
        pressAndHold(at: pt, durationMs: durationMs)
        return true
    }

    // MARK: - AX Element Traversal & Inspection

    func findElement(matching: (AXUIElement) -> Bool, in root: AXUIElement? = nil) -> AXUIElement? {
        guard let start = root ?? getAXMainWindow() else { return nil }
        var queue = [start]
        while !queue.isEmpty {
            let el = queue.removeFirst()
            if matching(el) { return el }
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
               let childList = children as? [AXUIElement] {
                queue.append(contentsOf: childList)
            }
        }
        return nil
    }

    func clickButton(named: String) -> Bool {
        let needle = named.lowercased()
        let el = findElement { el in
            var role: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            guard let r = role as? String, r.contains("Button") else { return false }
            
            var title: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
            var desc: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc)
            
            let t = (title as? String)?.lowercased() ?? ""
            let d = (desc as? String)?.lowercased() ?? ""
            return t == needle || d == needle || t.contains(needle) || d.contains(needle)
        }

        guard let target = el else { return false }
        // Attempt AXPressAction
        let err = AXUIElementPerformAction(target, kAXPressAction as CFString)
        if err == .success { return true }

        // Fallback: click element center
        var posVal: AnyObject?
        var sizeVal: AnyObject?
        if AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posVal) == .success,
           AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let pv = posVal, let sv = sizeVal {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            let center = CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
            click(at: center)
            return true
        }
        return false
    }

    func setText(_ text: String) -> Bool {
        guard let tf = findElement(matching: { el in
            var role: AnyObject?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            return (role as? String)?.contains("TextField") == true
        }) else { return false }

        var posVal: AnyObject?
        var sizeVal: AnyObject?
        if AXUIElementCopyAttributeValue(tf, kAXPositionAttribute as CFString, &posVal) == .success,
           AXUIElementCopyAttributeValue(tf, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let pv = posVal, let sv = sizeVal {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            click(at: CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2))
            usleep(100_000)
        }

        let err = AXUIElementSetAttributeValue(tf, kAXValueAttribute as CFString, text as CFTypeRef)
        return err == .success
    }

    func dumpAXTree(el: AXUIElement, depth: Int = 0) -> [String: Any] {
        var node: [String: Any] = [:]
        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        node["role"] = role as? String ?? ""

        var title: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
        if let t = title as? String, !t.isEmpty { node["title"] = t }

        var desc: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &desc)
        if let d = desc as? String, !d.isEmpty { node["description"] = d }

        var val: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val)
        if let v = val { node["value"] = "\(v)" }

        var posVal: AnyObject?
        var sizeVal: AnyObject?
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posVal) == .success,
           AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let pv = posVal, let sv = sizeVal {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(pv as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sv as! AXValue, .cgSize, &sz)
            node["frame"] = ["x": pt.x, "y": pt.y, "width": sz.width, "height": sz.height]
        }

        if depth < 12 {
            var children: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success,
               let childList = children as? [AXUIElement] {
                node["children"] = childList.map { dumpAXTree(el: $0, depth: depth + 1) }
            }
        }
        return node
    }
}

// MARK: - CLI Entrypoint

func main() {
    let args = CommandLine.arguments
    guard args.count > 1 else {
        print("""
        Usage: driver [options]
          --check-environment
          --find-window
          --set-geometry <x> <y> <w> <h>
          --capture <path.png>
          --click <relX> <relY>
          --click-button <name>
          --key <name> [durationMs]
          --click-piano-key <pitch> [durationMs]
          --dump-ax <path.json>
        """)
        exit(1)
    }

    let cmd = args[1]
    let driver = CUDriver.shared

    switch cmd {
    case "--check-environment":
        let trusted = AXIsProcessTrusted()
        let win = driver.findWindowInfo()
        let result: [String: Any] = [
            "accessibility_trusted": trusted,
            "window_found": win != nil,
            "window_id": win?.id ?? 0,
            "window_bounds": win != nil ? ["x": win!.bounds.origin.x, "y": win!.bounds.origin.y, "w": win!.bounds.width, "h": win!.bounds.height] : [:]
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: .prettyPrinted)
        print(String(data: data, encoding: .utf8)!)

    case "--find-window":
        guard let win = driver.findWindowInfo() else {
            print("{\"error\": \"Window not found\"}")
            exit(1)
        }
        let dict: [String: Any] = [
            "id": win.id,
            "x": win.bounds.origin.x,
            "y": win.bounds.origin.y,
            "width": win.bounds.width,
            "height": win.bounds.height
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        print(String(data: data, encoding: .utf8)!)

    case "--set-geometry":
        guard args.count >= 6,
              let x = Double(args[2]), let y = Double(args[3]),
              let w = Double(args[4]), let h = Double(args[5]) else {
            print("Error: Missing geometry arguments")
            exit(1)
        }
        let ok = driver.setWindowGeometry(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
        print("{\"success\": \(ok)}")

    case "--capture":
        guard args.count >= 3 else { exit(1) }
        let ok = driver.captureWindow(to: args[2])
        print("{\"success\": \(ok)}")

    case "--click":
        guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else { exit(1) }
        let ok = driver.clickRelative(relX: CGFloat(x), relY: CGFloat(y))
        print("{\"success\": \(ok)}")

    case "--click-button":
        guard args.count >= 3 else { exit(1) }
        let ok = driver.clickButton(named: args[2])
        print("{\"success\": \(ok)}")

    case "--set-text":
        guard args.count >= 3 else { exit(1) }
        let ok = driver.setText(args[2])
        print("{\"success\": \(ok)}")

    case "--key":
        guard args.count >= 3 else { exit(1) }
        let dur = args.count >= 4 ? Int(args[3]) ?? 100 : 100
        let ok = driver.sendKeyNamed(args[2], durationMs: dur)
        print("{\"success\": \(ok)}")

    case "--click-piano-key":
        guard args.count >= 3, let pitch = Int(args[2]) else { exit(1) }
        let dur = args.count >= 4 ? Int(args[3]) ?? 200 : 200
        let ok = driver.clickPianoKey(pitch: pitch, durationMs: dur)
        print("{\"success\": \(ok)}")

    case "--dump-ax":
        guard let win = driver.getAXMainWindow() else {
            print("{\"error\": \"No main window\"}")
            exit(1)
        }
        let tree = driver.dumpAXTree(el: win)
        let data = try! JSONSerialization.data(withJSONObject: tree, options: .prettyPrinted)
        if args.count >= 3 {
            try! data.write(to: URL(fileURLWithPath: args[2]))
            print("{\"success\": true, \"path\": \"\(args[2])\"}")
        } else {
            print(String(data: data, encoding: .utf8)!)
        }

    default:
        print("Unknown command: \(cmd)")
        exit(1)
    }
}

main()
