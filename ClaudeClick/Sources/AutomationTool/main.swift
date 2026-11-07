import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import Vision
import Carbon.HIToolbox

func checkAccessibilityPermissions() -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
    return AXIsProcessTrustedWithOptions(options)
}

func checkScreenRecordingPermissions() -> Bool {
    guard let mainDisplay = CGMainDisplayID() as CGDirectDisplayID? else {
        return false
    }

    let image = CGDisplayCreateImage(mainDisplay)
    return image != nil
}

// MARK: - JSON-based Element Finding

let DEFAULT_SCREEN_ELEMENTS_PATH = "/tmp/screen-elements.json"
let DEFAULT_FOCUSED_APP_PATH = "/tmp/focused-app.json"

func loadElementsFromJSON(filePath: String) -> ElementDump? {
    let tmpDir = "/tmp"
    let fullPath = (filePath as NSString).isAbsolutePath ? filePath : "\(tmpDir)/\(filePath)"

    // Check if file exists and is recent (less than 5 seconds old)
    if let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
       let modDate = attributes[.modificationDate] as? Date {
        let age = Date().timeIntervalSince(modDate)
        if age < 5.0 {
            // File exists and is recent, try to load it
            if let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) {
                let decoder = JSONDecoder()
                if let dump = try? decoder.decode(ElementDump.self, from: data) {
                    return dump
                }
            }
        }
    }

    // File doesn't exist or is stale
    return nil
}

func findElementInJSON(name: String, appName: String? = nil, jsonPath: String? = nil) -> DumpedElement? {
    let path = jsonPath ?? (appName == nil ? DEFAULT_SCREEN_ELEMENTS_PATH : DEFAULT_FOCUSED_APP_PATH)

    guard let dump = loadElementsFromJSON(filePath: path) else {
        if appName == nil {
            print("Error: App name is required for find-click")
            print("Usage: claude-click find-click \"<element name>\" \"<app name>\"")
            print("Example: claude-click find-click \"New Document\" \"Keynote\"")
            print("Note: For desktop items, use \"Finder\" as the app name")
        } else {
            print("Error: Could not load elements from \(path)")
        }
        return nil
    }

    // Filter by app if specified
    let candidateElements = dump.elements

    // Find matching elements (case-insensitive, flexible matching)
    let searchLower = name.lowercased()
    var matches: [(element: DumpedElement, score: Double)] = []

    for element in candidateElements {
        let titleLower = element.title.lowercased()
        let descLower = element.description.lowercased()
        let placeholderLower = (element.placeholder ?? "").lowercased()
        let valueLower = (element.value ?? "").lowercased()

        var score: Double = 0.0

        // Exact match (highest priority)
        if titleLower == searchLower || descLower == searchLower || placeholderLower == searchLower || valueLower == searchLower {
            score = 10.0
        }
        // Starts with
        else if titleLower.hasPrefix(searchLower) || descLower.hasPrefix(searchLower) || placeholderLower.hasPrefix(searchLower) || valueLower.hasPrefix(searchLower) {
            score = 5.0
        }
        // Contains
        else if titleLower.contains(searchLower) || descLower.contains(searchLower) || placeholderLower.contains(searchLower) || valueLower.contains(searchLower) {
            score = 3.0
        }

        if score > 0 {
            // Bonus for enabled elements
            if element.enabled {
                score += 1.0
            }
            // Bonus for clickable roles
            let clickableRoles = ["AXButton", "AXMenuItem", "AXLink", "AXTextField", "AXTextArea"]
            if clickableRoles.contains(element.role) {
                score += 0.5
            }

            matches.append((element, score))
        }
    }

    // Sort by score (highest first)
    matches.sort { $0.score > $1.score }

    if let best = matches.first {
        return best.element
    }

    print("Could not find element named: \(name)")
    if !matches.isEmpty {
        print("Similar elements found:")
        for (i, match) in matches.prefix(5).enumerated() {
            print("  \(i+1). '\(match.element.title)' (\(match.element.role))")
        }
    }

    return nil
}

func getElementPosition(_ element: DumpedElement) -> CGPoint {
    // Calculate center position of element
    let centerX = CGFloat(element.x) + CGFloat(element.width) / 2.0
    let centerY = CGFloat(element.y) + CGFloat(element.height) / 2.0

    // Add small offset below center for better button click reliability
    // Many buttons have clickable areas slightly below visual center
    let offsetY: CGFloat = 2.0

    return CGPoint(x: centerX, y: centerY + offsetY)
}

func findElementByName(name: String, appName: String? = nil) -> CGPoint? {
    guard let element = findElementInJSON(name: name, appName: appName) else {
        return nil
    }
    return getElementPosition(element)
}

func animatedMoveMouse(to targetPoint: CGPoint, duration: Double = 0.3) {
    let startPosition = NSEvent.mouseLocation
    let screenHeight = NSScreen.main?.frame.height ?? 0
    let startPoint = CGPoint(x: startPosition.x, y: screenHeight - startPosition.y)

    let steps = Int(duration * 60.0) // 60 fps
    let stepDelay = UInt32((duration * 1_000_000.0) / Double(steps))

    for step in 0...steps {
        let progress = Double(step) / Double(steps)

        // Ease-in-out interpolation
        let easedProgress: Double
        if progress < 0.5 {
            easedProgress = 2.0 * progress * progress
        } else {
            easedProgress = 1.0 - 2.0 * (1.0 - progress) * (1.0 - progress)
        }

        let x = startPoint.x + (targetPoint.x - startPoint.x) * easedProgress
        let y = startPoint.y + (targetPoint.y - startPoint.y) * easedProgress

        let currentPoint = CGPoint(x: x, y: y)
        CGWarpMouseCursorPosition(currentPoint)

        if step < steps {
            usleep(stepDelay)
        }
    }
}

func waitForElement(name: String, appName: String, timeout: Double = 10.0) -> Bool {
    let startTime = Date()
    print("Waiting for element '\(name)' in \(appName) (timeout: \(timeout)s)...")

    let workspace = NSWorkspace.shared

    while Date().timeIntervalSince(startTime) < timeout {
        // Get fresh workspace and running apps list each iteration
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        // Find the app
        var targetApp: NSRunningApplication?
        for runningApp in runningApps {
            let localizedName = runningApp.localizedName ?? ""
            let bundleURL = runningApp.bundleURL?.lastPathComponent ?? ""

            if bundleURL.lowercased() == appName.lowercased() + ".app" ||
               localizedName.lowercased() == appName.lowercased() {
                targetApp = runningApp
                break
            }
        }

        guard let app = targetApp else {
            usleep(100_000) // 100ms
            continue
        }

        // Collect elements
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var elements: [DumpedElement] = []
        var elementId = 1
        collectElements(appElement, elements: &elements, elementId: &elementId)

        // Search for element
        let searchLower = name.lowercased()
        for element in elements {
            let titleLower = element.title.lowercased()
            let descLower = element.description.lowercased()

            if titleLower == searchLower || descLower == searchLower ||
               titleLower.contains(searchLower) || descLower.contains(searchLower) {
                let elapsed = Date().timeIntervalSince(startTime)
                print("Found '\(name)' in \(String(format: "%.2f", elapsed))s")
                return true
            }
        }

        usleep(100_000) // Check every 100ms
    }

    print("Timeout: Element '\(name)' not found after \(timeout)s")
    return false
}

func clickMouse(x: Int, y: Int, flags: CGEventFlags = []) {
    let point = CGPoint(x: x, y: y)

    print("Clicking at: x=\(x), y=\(y)")

    // Animate mouse movement to position
    animatedMoveMouse(to: point, duration: 0.3)

    // Left button down
    let leftDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    leftDown?.flags = flags
    leftDown?.post(tap: .cghidEventTap)

    // Short delay (15ms like cliclick)
    usleep(15000)

    // Left button up
    let leftUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    leftUp?.flags = flags
    leftUp?.post(tap: .cghidEventTap)

    print("Clicked at: x=\(x), y=\(y)")
}

func doubleClickMouse(x: Int, y: Int, flags: CGEventFlags = []) {
    let point = CGPoint(x: x, y: y)

    print("Double-clicking at: x=\(x), y=\(y)")

    // Animate mouse movement to position
    animatedMoveMouse(to: point, duration: 0.3)

    // First click
    let leftDown1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    leftDown1?.setIntegerValueField(.mouseEventClickState, value: 1)
    leftDown1?.flags = flags
    leftDown1?.post(tap: .cghidEventTap)
    usleep(15000)
    let leftUp1 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    leftUp1?.setIntegerValueField(.mouseEventClickState, value: 1)
    leftUp1?.flags = flags
    leftUp1?.post(tap: .cghidEventTap)

    // Very short delay between clicks (100ms)
    usleep(100000)

    // Second click with click count = 2
    let leftDown2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    leftDown2?.setIntegerValueField(.mouseEventClickState, value: 2)
    leftDown2?.flags = flags
    leftDown2?.post(tap: .cghidEventTap)
    usleep(15000)
    let leftUp2 = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    leftUp2?.setIntegerValueField(.mouseEventClickState, value: 2)
    leftUp2?.flags = flags
    leftUp2?.post(tap: .cghidEventTap)

    // Wait for text field to gain keyboard focus
    // Increased from 100ms to 500ms for more reliable focus acquisition
    usleep(500000) // 500ms

    print("Double-clicked at: x=\(x), y=\(y)")
}

func rightClickMouse(x: Int, y: Int, flags: CGEventFlags = []) {
    let point = CGPoint(x: x, y: y)

    print("Right-clicking at: x=\(x), y=\(y)")

    // Animate mouse movement to position
    animatedMoveMouse(to: point, duration: 0.3)

    // Right button down
    let rightDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
    rightDown?.flags = flags
    rightDown?.post(tap: .cghidEventTap)

    // Short delay (15ms like cliclick)
    usleep(15000)

    // Right button up
    let rightUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
    rightUp?.flags = flags
    rightUp?.post(tap: .cghidEventTap)

    print("Right-clicked at: x=\(x), y=\(y)")
}

// MARK: - Pointer helpers shared by click, drag, scroll and mouse up/down

// Backing scale factor of the main display (2.0 on Retina). Screenshots are in
// pixels; mouse events use points. Divide screenshot pixel coordinates by this
// to get point coordinates.
func mainDisplayScaleFactor() -> CGFloat {
    return NSScreen.main?.backingScaleFactor ?? 1.0
}

// Converts a coordinate to point space. When pixels is true the input is treated
// as screenshot pixel coordinates and divided by the backing scale factor.
func pointCoordinate(x: Int, y: Int, pixels: Bool) -> CGPoint {
    guard pixels else { return CGPoint(x: x, y: y) }
    let scale = Double(mainDisplayScaleFactor())
    return CGPoint(x: Double(x) / scale, y: Double(y) / scale)
}

// Parses modifier tokens (space-separated and/or +-joined, e.g. "cmd", "ctrl+shift")
// into CGEventFlags. "super" maps to Command to match the computer use toolset.
func parseModifierFlags(_ tokens: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for token in tokens {
        for part in token.split(separator: "+").map({ $0.lowercased() }) {
            switch part {
            case "cmd", "command", "super":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "alt", "option":
                flags.insert(.maskAlternate)
            case "ctrl", "control":
                flags.insert(.maskControl)
            default:
                break
            }
        }
    }
    return flags
}

// Current cursor position in point space (top-left origin).
func currentCursorPoint() -> CGPoint {
    return CGEvent(source: nil)?.location ?? .zero
}

func moveMouse(to point: CGPoint) {
    animatedMoveMouse(to: point, duration: 0.3)
    print("Moved to: x=\(Int(point.x)), y=\(Int(point.y))")
}

func mouseButtonDown(at point: CGPoint, flags: CGEventFlags = []) {
    let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
    print("Mouse down at: x=\(Int(point.x)), y=\(Int(point.y))")
}

func mouseButtonUp(at point: CGPoint, flags: CGEventFlags = []) {
    let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    event?.flags = flags
    event?.post(tap: .cghidEventTap)
    print("Mouse up at: x=\(Int(point.x)), y=\(Int(point.y))")
}

// Presses at start, drags to end through intermediate steps, then releases.
func dragMouse(from start: CGPoint, to end: CGPoint, flags: CGEventFlags = []) {
    print("Dragging from x=\(Int(start.x)), y=\(Int(start.y)) to x=\(Int(end.x)), y=\(Int(end.y))")

    animatedMoveMouse(to: start, duration: 0.3)
    usleep(50000)

    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    usleep(50000)

    let steps = 30
    for step in 1...steps {
        let progress = Double(step) / Double(steps)
        let x = start.x + (end.x - start.x) * CGFloat(progress)
        let y = start.y + (end.y - start.y) * CGFloat(progress)
        let point = CGPoint(x: x, y: y)
        let dragged = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left)
        dragged?.flags = flags
        dragged?.post(tap: .cghidEventTap)
        usleep(8000)
    }

    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)

    print("Dragged to: x=\(Int(end.x)), y=\(Int(end.y))")
}

// Scrolls by a number of wheel clicks in the given direction, optionally at a
// position. Posts one line-unit tick per click so edges and direction changes
// are handled reliably. Up scrolls toward the top, down toward the bottom.
func scrollWheel(direction: String, amount: Int, at point: CGPoint?, flags: CGEventFlags = []) {
    if let point = point {
        animatedMoveMouse(to: point, duration: 0.3)
        usleep(50000)
    }

    var wheel1: Int32 = 0 // vertical, positive scrolls up
    var wheel2: Int32 = 0 // horizontal, positive scrolls left

    switch direction.lowercased() {
    case "up":
        wheel1 = 1
    case "down":
        wheel1 = -1
    case "left":
        wheel2 = 1
    case "right":
        wheel2 = -1
    default:
        print("Error: scroll direction must be up, down, left or right")
        return
    }

    let ticks = max(1, amount)
    for _ in 0..<ticks {
        let event = CGEvent(scrollWheelEvent2Source: hidEventSource, units: .line, wheelCount: 2, wheel1: wheel1, wheel2: wheel2, wheel3: 0)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        usleep(15000)
    }

    print("Scrolled \(direction.lowercased()) by \(ticks)")
}

// MARK: - Activity indicator overlay

// A persistent, always-on-top, click-through badge that shows the machine is
// being driven by claude-click. It runs as a detached helper process (indicator
// start/stop) and reflects live activity through a heartbeat file every command
// touches. It hides itself briefly while claude-click captures a screenshot so
// it does not appear in the captured image.

let indicatorPidPath = "/tmp/claude-click-indicator.pid"
let activityHeartbeatPath = "/tmp/claude-click-heartbeat"
let indicatorSuppressPath = "/tmp/claude-click-indicator-suppress"

func recordActivityHeartbeat() {
    try? Data().write(to: URL(fileURLWithPath: activityHeartbeatPath))
}

func fileIsFresh(_ path: String, within seconds: TimeInterval) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let modified = attributes[.modificationDate] as? Date else {
        return false
    }
    return Date().timeIntervalSince(modified) <= seconds
}

func indicatorIsRunning() -> Bool {
    guard let pidText = try? String(contentsOfFile: indicatorPidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(pidText) else {
        return false
    }
    return kill(pid, 0) == 0
}

// Called by screenshot commands: if the indicator is running, flag a short
// suppression window and wait for it to hide. Returns whether suppression was engaged.
func beginScreenshotSuppressionIfNeeded() -> Bool {
    guard indicatorIsRunning() else { return false }
    try? Data().write(to: URL(fileURLWithPath: indicatorSuppressPath))
    usleep(160000) // allow the indicator's poll to hide the badge before capture
    return true
}

func endScreenshotSuppression(_ engaged: Bool) {
    guard engaged else { return }
    try? FileManager.default.removeItem(atPath: indicatorSuppressPath)
}

class IndicatorController: NSObject {
    let window: NSWindow
    let dot: NSView

    init(labelText: String) {
        let width: CGFloat = 190
        let height: CGFloat = 30

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.cornerRadius = height / 2

        dot = NSView(frame: NSRect(x: 14, y: height / 2 - 5, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        container.addSubview(dot)

        let label = NSTextField(labelWithString: labelText)
        label.frame = NSRect(x: 32, y: 6, width: width - 42, height: 18)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        container.addSubview(label)

        window.contentView = container
        super.init()
        positionWindow()
    }

    func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 16
        window.setFrameOrigin(NSPoint(x: visible.maxX - size.width - margin,
                                      y: visible.maxY - size.height - margin))
    }

    @objc func tick() {
        positionWindow()

        // Show the badge only while claude-click is actually acting: the activity
        // heartbeat is fresh and a screenshot is not being captured.
        let suppressed = fileIsFresh(indicatorSuppressPath, within: 2.0)
        let active = fileIsFresh(activityHeartbeatPath, within: 2.5)

        if active && !suppressed {
            if !window.isVisible { window.orderFrontRegardless() }
        } else {
            if window.isVisible { window.orderOut(nil) }
        }
    }
}

func runIndicator(labelText: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let controller = IndicatorController(labelText: labelText)
    // The window starts hidden; the poll shows it only while claude-click is active.

    let timer = Timer(timeInterval: 0.1, target: controller, selector: #selector(IndicatorController.tick), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .common)

    app.run()
}

// MARK: - Screen settle detection

// Captures the main display downscaled to a small RGBA buffer for cheap frame-to-frame comparison.
func captureDownscaledFrame(side: Int = 48) -> [UInt8]? {
    guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = 4 * side
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * side)
    let drew: Bool = buffer.withUnsafeMutableBytes { raw in
        guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    return drew ? buffer : nil
}

// Mean absolute difference between two equal-length frames, normalized to 0...1.
func frameDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 1.0 }
    var total = 0
    for i in 0..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
    return Double(total) / Double(a.count) / 255.0
}

// Waits until two consecutive frames differ by less than threshold, or until timeout.
// Returns true if the screen settled, false on timeout.
@discardableResult
func waitUntilScreenStable(timeout: Double = 5.0, interval: Double = 0.15, threshold: Double = 0.004) -> Bool {
    let start = Date()
    var previous = captureDownscaledFrame()
    while Date().timeIntervalSince(start) < timeout {
        usleep(UInt32(interval * 1_000_000))
        let current = captureDownscaledFrame()
        if let p = previous, let c = current, frameDifference(p, c) <= threshold {
            return true
        }
        previous = current
    }
    return false
}

// MARK: - Action recorder (observation -> action trajectories)

// Records an episode of (pre-action observation, action) steps built entirely from
// claude-click's own primitives: a screenshot, the focused app, cursor position,
// screen geometry, and optionally the accessibility tree. Intended for collecting
// or inspecting computer-use trajectories.

struct RecordingState: Codable {
    var dir: String
    var step: Int
    var label: String
    var ax: Bool
    var startedAt: String
}

let recordingStatePath = "/tmp/claude-click-recording.json"

func loadRecordingState() -> RecordingState? {
    guard let data = FileManager.default.contents(atPath: recordingStatePath) else { return nil }
    return try? JSONDecoder().decode(RecordingState.self, from: data)
}

func saveRecordingState(_ state: RecordingState) {
    if let data = try? JSONEncoder().encode(state) {
        try? data.write(to: URL(fileURLWithPath: recordingStatePath))
    }
}

func isoTimestamp() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
}

func fileTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
}

// Silently captures the main display to a JPEG at the given path (no stdout).
@discardableResult
func captureDisplayJPEG(to path: String, scale: CGFloat = 0.5, quality: CGFloat = 0.6) -> Bool {
    guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return false }
    let width = max(1, Int(CGFloat(image.width) * scale))
    let height = max(1, Int(CGFloat(image.height) * scale))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.jpeg" as CFString, 1, nil) else {
        return false
    }
    CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    return CGImageDestinationFinalize(dest)
}

// Collects the frontmost app's accessibility tree as DumpedElements.
func captureFrontmostAXTree() -> [DumpedElement]? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)
    return elements
}

// If a recording is active, captures the pre-action observation and appends one step to episode.jsonl.
func recordStep(actionType: String, details: [String: Any]) {
    guard var state = loadRecordingState() else { return }
    let step = state.step + 1
    state.step = step
    let base = String(format: "step_%04d_before", step)

    let shotName = base + ".jpg"
    let suppressing = beginScreenshotSuppressionIfNeeded()
    captureDisplayJPEG(to: state.dir + "/" + shotName)
    endScreenshotSuppression(suppressing)

    var observation: [String: Any] = [
        "screenshot": shotName,
        "focused_app": NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
    ]
    let cursor = currentCursorPoint()
    observation["cursor"] = [Int(cursor.x), Int(cursor.y)]
    if let screen = NSScreen.main {
        observation["screen_points"] = [Int(screen.frame.width), Int(screen.frame.height)]
        observation["scale"] = Double(screen.backingScaleFactor)
    }
    if state.ax, let elements = captureFrontmostAXTree(), let axData = try? JSONEncoder().encode(elements) {
        let axName = base + ".ax.json"
        try? axData.write(to: URL(fileURLWithPath: state.dir + "/" + axName))
        observation["ax_dump"] = axName
    }

    var action: [String: Any] = ["type": actionType]
    for (key, value) in details { action[key] = value }

    let record: [String: Any] = [
        "step": step,
        "timestamp": isoTimestamp(),
        "action": action,
        "observation": observation,
    ]

    if let data = try? JSONSerialization.data(withJSONObject: record, options: []),
       var line = String(data: data, encoding: .utf8) {
        line += "\n"
        let episodeURL = URL(fileURLWithPath: state.dir + "/episode.jsonl")
        if let handle = try? FileHandle(forWritingTo: episodeURL) {
            handle.seekToEndOfFile()
            if let lineData = line.data(using: .utf8) { handle.write(lineData) }
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: episodeURL)
        }
    }

    saveRecordingState(state)
}




func runAppleScript(_ scriptSource: String) -> (success: Bool, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", scriptSource]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            return (true, output)
        } else {
            return (false, output)
        }
    } catch {
        return (false, "Failed to execute osascript: \(error)")
    }
}

// MARK: - Keyboard

// Keyboard input is driven by real virtual key codes posted from an HID system
// event source. On recent macOS releases synthetic events built with
// keyboardSetUnicodeString (virtual key 0) are dropped by most applications, so
// every character is resolved to the key code that produces it and posted as a
// key-down/key-up pair, adding Shift where the character requires it.

// HID system event source shared by every synthetic keyboard event.
let hidEventSource = CGEventSource(stateID: .hidSystemState)

// US ANSI layout virtual key codes, used as a fallback when the current layout
// cannot be resolved through the Text Input Source APIs.
let usLayoutKeyCodes: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
    "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
    "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
    "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50, " ": 49, "\n": 36, "\t": 48,
]

// Characters produced by holding Shift over a US-layout base key.
let usShiftedCharacters: [Character: Character] = [
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0", "_": "-",
    "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
]

// Named special keys shared by type, press-key and shortcut.
let namedKeyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
    "forward-delete": 117, "forwarddelete": 117, "fn-delete": 117,
    "escape": 53, "esc": 53, "capslock": 57,
    "home": 115, "end": 119, "pageup": 116, "page-up": 116, "pagedown": 121, "page-down": 121,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "command": 55, "cmd": 55, "shift": 56, "option": 58, "alt": 58, "control": 59, "ctrl": 59, "rightshift": 60,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
    "f9": 101, "f10": 109, "f11": 103, "f12": 111,
]

struct KeyStroke {
    let code: CGKeyCode
    let shift: Bool
}

// Builds a character to (key code, shift) map for the current keyboard layout
// using UCKeyTranslate, so non-US layouts resolve correctly. Returns nil if the
// layout data is unavailable, in which case callers fall back to the US table.
func buildCurrentLayoutMap() -> [Character: KeyStroke]? {
    guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
          let layoutPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
    let keyboardType = UInt32(LMGetKbdType())

    var map: [Character: KeyStroke] = [:]
    for keyCode in CGKeyCode(0)..<CGKeyCode(128) {
        for shift in [false, true] {
            let modifierState: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = layoutData.withUnsafeBytes { raw -> OSStatus in
                guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
                return UCKeyTranslate(base, keyCode, UInt16(kUCKeyActionDisplay), modifierState,
                                      keyboardType, OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                      &deadKeyState, 4, &length, &chars)
            }
            guard status == noErr, length > 0 else { continue }
            let produced = String(utf16CodeUnits: chars, count: length)
            guard produced.unicodeScalars.count == 1, let scalar = produced.unicodeScalars.first,
                  scalar.value >= 0x20, scalar.value != 0x7F else { continue }
            let character = Character(scalar)
            // Keep the first spelling seen for a character; unshifted is tried first.
            if map[character] == nil {
                map[character] = KeyStroke(code: keyCode, shift: shift)
            }
        }
    }
    return map.isEmpty ? nil : map
}

let currentLayoutMap = buildCurrentLayoutMap()

// Resolves a character to the key code (and Shift state) that types it, trying
// the current layout first and falling back to the US table.
func keyStroke(for character: Character) -> KeyStroke? {
    if let stroke = currentLayoutMap?[character] {
        return stroke
    }
    if let code = usLayoutKeyCodes[character] {
        return KeyStroke(code: code, shift: false)
    }
    let lower = Character(character.lowercased())
    if character.isUppercase, let code = usLayoutKeyCodes[lower] {
        return KeyStroke(code: code, shift: true)
    }
    if let base = usShiftedCharacters[character], let code = usLayoutKeyCodes[base] {
        return KeyStroke(code: code, shift: true)
    }
    return nil
}

// Resolves a key name for press-key / shortcut: a named special key, or a single
// character looked up in the layout. Returns the key code and any flags the
// character itself requires (for example Shift for a capital letter).
func keyCodeForName(_ name: String) -> (code: CGKeyCode, flags: CGEventFlags)? {
    let lowered = name.lowercased()
    if let code = namedKeyCodes[lowered] {
        return (code, [])
    }
    if name.count == 1, let character = name.first, let stroke = keyStroke(for: character) {
        return (stroke.code, stroke.shift ? .maskShift : [])
    }
    return nil
}

// Posts a key-down/key-up pair from the HID system source with the given flags.
func postKeyStroke(code: CGKeyCode, flags: CGEventFlags = [], holdMicros: UInt32 = 8000) {
    let keyDown = CGEvent(keyboardEventSource: hidEventSource, virtualKey: code, keyDown: true)
    keyDown?.flags = flags
    keyDown?.post(tap: .cghidEventTap)
    usleep(holdMicros)
    let keyUp = CGEvent(keyboardEventSource: hidEventSource, virtualKey: code, keyDown: false)
    keyUp?.flags = flags
    keyUp?.post(tap: .cghidEventTap)
}

func typeText(_ text: String, delayMillis: Double = 40) {
    // Check if we should re-activate an app (after clicking a text field)
    let appNamePath = "/tmp/claude-click-last-app.txt"
    if let savedAppName = try? String(contentsOfFile: appNamePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       !savedAppName.isEmpty {
        // Re-activate the saved app
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: { $0.localizedName == savedAppName }) {
            app.activate(options: [.activateIgnoringOtherApps])
            usleep(200000) // 200ms for activation
        }
        // Clear the saved app
        try? FileManager.default.removeItem(atPath: appNamePath)
    }

    let perCharDelay = UInt32(max(0, delayMillis) * 1000)
    var unmapped: [Character] = []

    for char in text {
        if let stroke = keyStroke(for: char) {
            postKeyStroke(code: stroke.code, flags: stroke.shift ? .maskShift : [])
        } else {
            // No key on the current layout produces this character (accented
            // letters, emoji). Fall back to a Unicode-string event; many apps
            // drop these, so report them on stderr.
            let string = String(char)
            if let keyDownEvent = CGEvent(keyboardEventSource: hidEventSource, virtualKey: 0, keyDown: true) {
                keyDownEvent.keyboardSetUnicodeString(stringLength: string.utf16.count, unicodeString: Array(string.utf16))
                keyDownEvent.post(tap: .cghidEventTap)
            }
            if let keyUpEvent = CGEvent(keyboardEventSource: hidEventSource, virtualKey: 0, keyDown: false) {
                keyUpEvent.keyboardSetUnicodeString(stringLength: string.utf16.count, unicodeString: Array(string.utf16))
                keyUpEvent.post(tap: .cghidEventTap)
            }
            unmapped.append(char)
        }
        usleep(perCharDelay)
    }

    print("Typed: \(text)")
    if !unmapped.isEmpty {
        let list = String(unmapped)
        FileHandle.standardError.write("Warning: characters not on the current keyboard layout were sent as Unicode events and may not appear in all apps: \(list)\n".data(using: .utf8)!)
    }
}

func pressKey(_ keyName: String) {
    guard let resolved = keyCodeForName(keyName) else {
        print("Error: Unknown key '\(keyName)'")
        print("Available keys: \(namedKeyCodes.keys.sorted().joined(separator: ", ")) (plus any single character)")
        return
    }

    postKeyStroke(code: resolved.code, flags: resolved.flags, holdMicros: 50000)

    print("Pressed key: \(keyName)")
}

func keyboardShortcut(modifiers: [String], key: String, appName: String) {
    // First, activate the target app
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var foundApp: NSRunningApplication?
    var bestMatch: NSRunningApplication?
    var bestMatchScore = 0

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleIdentifier = app.bundleIdentifier ?? ""

        if localizedName.lowercased().contains(appName.lowercased()) ||
           bundleIdentifier.lowercased().contains(appName.lowercased()) {
            var score = 1
            if localizedName.lowercased() == appName.lowercased() {
                score += 10
            }
            if app.activationPolicy == .regular {
                score += 5
            }
            if score > bestMatchScore {
                bestMatchScore = score
                bestMatch = app
            }
        }
    }

    foundApp = bestMatch

    guard let app = foundApp else {
        print("Error: App '\(appName)' is not running")
        print("Cannot send shortcut to an app that is not running.")
        return
    }

    // Activate the app
    app.activate(options: [.activateIgnoringOtherApps])
    usleep(200000) // Wait 200ms for activation

    var flags: CGEventFlags = []

    for modifier in modifiers {
        switch modifier.lowercased() {
        case "cmd", "command":
            flags.insert(.maskCommand)
        case "shift":
            flags.insert(.maskShift)
        case "option", "alt":
            flags.insert(.maskAlternate)
        case "control", "ctrl":
            flags.insert(.maskControl)
        default:
            print("Warning: Unknown modifier '\(modifier)'")
        }
    }

    // Resolve the key through the shared table: named special keys (including
    // arrows, home/end, page up/down) or any single character on the layout.
    guard let resolved = keyCodeForName(key) else {
        print("Error: Unknown key '\(key)' for shortcut")
        return
    }
    let keyCode = resolved.code
    flags.formUnion(resolved.flags)

    let keyDown = CGEvent(keyboardEventSource: hidEventSource, virtualKey: keyCode, keyDown: true)
    keyDown?.flags = flags
    keyDown?.post(tap: .cghidEventTap)

    usleep(50000)

    let keyUp = CGEvent(keyboardEventSource: hidEventSource, virtualKey: keyCode, keyDown: false)
    keyUp?.flags = flags
    keyUp?.post(tap: .cghidEventTap)

    let modifierStr = modifiers.joined(separator: "+")
    print("Sent shortcut \(modifierStr)+\(key) to '\(app.localizedName ?? appName)'")
}

func waitForSeconds(_ seconds: Double) {
    print("Waiting \(seconds) seconds...")
    usleep(UInt32(seconds * 1_000_000))
    print("Wait complete")
}

func waitForAppLaunch(appName: String, timeout: Double = 10.0, activate: Bool = false) -> Bool {
    let startTime = Date()
    print("Waiting for '\(appName)' to launch (timeout: \(timeout)s)...")

    var foundApp: NSRunningApplication?

    while Date().timeIntervalSince(startTime) < timeout {
        // Get fresh workspace and apps list each iteration
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        foundApp = nil
        for app in runningApps {
            let localizedName = app.localizedName ?? ""
            let bundleIdentifier = app.bundleIdentifier ?? ""

            if localizedName.lowercased().contains(appName.lowercased()) ||
               bundleIdentifier.lowercased().contains(appName.lowercased()) {
                foundApp = app
                break
            }
        }

        if let app = foundApp {
            // App found, give it a moment for window to appear
            usleep(2000000) // Wait 2s for window to fully load

            let elapsed = Date().timeIntervalSince(startTime)
            print("App '\(appName)' launched in \(String(format: "%.2f", elapsed))s")

            if activate {
                app.activate(options: [.activateIgnoringOtherApps])
                usleep(500000) // Wait 0.5s for activation
                print("Activated '\(appName)'")
            }

            return true
        }

        usleep(100000) // Check every 100ms for fast detection
    }

    print("Timeout: App '\(appName)' did not launch after \(timeout) seconds")
    return false
}

func hasVisibleWindow(appName: String, debug: Bool = false) -> Bool {
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        if debug { print("DEBUG: Could not get window list") }
        return false
    }

    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased().contains(appName.lowercased()) {
            let pid = app.processIdentifier
            if debug { print("DEBUG: Found app '\(localizedName)' with PID \(pid)") }

            var windowCount = 0
            for window in windowList {
                if let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
                   windowPID == pid {
                    windowCount += 1
                    let windowLayer = window[kCGWindowLayer as String] as? Int ?? -1
                    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
                    let width = bounds?["Width"] ?? 0
                    let height = bounds?["Height"] ?? 0

                    if debug {
                        print("DEBUG: Window #\(windowCount): layer=\(windowLayer) size=\(Int(width))x\(Int(height))")
                    }

                    if windowLayer == 0 {
                        // Check for actual window (not tiny toolbar)
                        if width > 100 && height > 100 {
                            if debug { print("DEBUG: Found valid window!") }
                            return true
                        }
                    }
                }
            }
            if debug { print("DEBUG: Checked \(windowCount) windows for PID \(pid), none valid") }
        }
    }

    return false
}

func findTextWithOCR(searchText: String, appName: String) -> CGPoint? {
    print("DEBUG: findTextWithOCR called for '\(searchText)' in \(appName)")

    // Reuse single temp file instead of creating new UUIDs
    let tempPath = "/tmp/claude-click-ocr-temp.png"

    // Take window screenshot at full resolution for accurate OCR coordinates
    takeWindowScreenshot(appName: appName, filename: tempPath, fullResolution: true)

    // Load image
    guard let image = NSImage(contentsOfFile: tempPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Failed to load window screenshot")
        return nil
    }

    // Run Vision OCR
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
    } catch {
        print("OCR failed: \(error)")
        return nil
    }

    guard let observations = request.results else {
        print("No text found in image")
        return nil
    }

    // Find matching text
    for observation in observations {
        guard let topCandidate = observation.topCandidates(1).first else { continue }
        let text = topCandidate.string

        if text.lowercased().contains(searchText.lowercased()) {
            let boundingBox = observation.boundingBox

            // Vision uses normalized coordinates (0-1) with origin at bottom-left
            // Convert to pixel coordinates with origin at top-left
            let imageWidth = cgImage.width
            let imageHeight = cgImage.height

            // Calculate center of text
            let centerX = (boundingBox.origin.x + boundingBox.width / 2) * CGFloat(imageWidth)
            let centerY = (1.0 - boundingBox.origin.y - boundingBox.height / 2) * CGFloat(imageHeight)

            print("DEBUG: Image size: \(imageWidth)x\(imageHeight)")
            print("DEBUG: Text bounding box (normalized): \(boundingBox)")
            print("DEBUG: Text center in image (pixels): (\(centerX), \(centerY))")

            // Get window position on screen
            let workspace = NSWorkspace.shared
            guard let app = workspace.runningApplications.first(where: {
                $0.localizedName?.lowercased().contains(appName.lowercased()) == true
            }) else {
                print("Could not find app for coordinate conversion")
                return nil
            }

            let pid = app.processIdentifier

            // Get window bounds
            guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
                return nil
            }

            for window in windowList {
                if let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
                   windowPID == pid,
                   let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                   let windowX = bounds["X"],
                   let windowY = bounds["Y"] {

                    print("DEBUG: Window position: (\(windowX), \(windowY))")

                    // Convert from window screenshot coords to screen coords
                    // Full resolution screenshot is 2x scaled on Retina displays
                    let screenX = windowX + (centerX / 2.0)
                    let screenY = windowY + (centerY / 2.0)

                    print("DEBUG: Final screen coords: (\(screenX), \(screenY))")

                    // Don't clean up temp file for debugging
                    // try? FileManager.default.removeItem(atPath: tempPath)

                    return CGPoint(x: screenX, y: screenY)
                }
            }
        }
    }

    // Clean up temp file
    try? FileManager.default.removeItem(atPath: tempPath)

    print("Text '\(searchText)' not found in window")
    return nil
}

func listAccessibleElements() {
    print("Listing all accessible elements...")
    print(String(repeating: "=", count: 80))

    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    for app in runningApps {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let appElement = AXUIElementCreateApplication(pid)

        print("\nApplication: \(appName) (PID: \(pid))")
        print(String(repeating: "-", count: 80))

        listElements(appElement, depth: 0, maxDepth: 3)
    }
}

func listElements(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    if depth > maxDepth {
        return
    }

    let indent = String(repeating: "  ", count: depth)

    // Get element info
    var roleValue: CFTypeRef?
    var titleValue: CFTypeRef?
    var descValue: CFTypeRef?
    var posValue: CFTypeRef?

    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)

    let role = roleValue as? String ?? "unknown"
    let title = titleValue as? String ?? ""
    let desc = descValue as? String ?? ""

    var posString = ""
    if let pos = posValue {
        var point = CGPoint.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &point)
        posString = " at (\(Int(point.x)), \(Int(point.y)))"
    }

    if !title.isEmpty || !desc.isEmpty {
        print("\(indent)[\(role)] title: '\(title)' desc: '\(desc)'\(posString)")
    }

    // Get children
    var childrenValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

    if result == .success, let children = childrenValue as? [AXUIElement] {
        for child in children {
            listElements(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

struct DumpedElement: Codable {
    var id: Int
    var role: String
    var title: String
    var description: String
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var enabled: Bool
    var value: String?
    var placeholder: String?
}

struct ElementDump: Codable {
    var app: String
    var timestamp: String
    var screenshot: String
    var elements: [DumpedElement]
}

func dumpElements(appName: String, outputBaseName: String) {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased().contains(appName.lowercased()) {
            targetApp = app
            break
        }
    }

    guard let app = targetApp else {
        print("Error: Could not find running app '\(appName)'")
        return
    }

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    print("Collecting elements from \(app.localizedName ?? appName)...")

    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)

    print("Found \(elements.count) elements")

    let screenshotPath = "\(outputBaseName).png"
    let jsonPath = "\(outputBaseName).json"

    takeWindowScreenshot(appName: appName, filename: screenshotPath)

    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        print("Error: Could not get window list")
        return
    }

    var windowBounds: CGRect?
    for window in windowList {
        if let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
           windowPID == pid,
           let windowLayer = window[kCGWindowLayer as String] as? Int,
           windowLayer == 0,
           let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
           let x = bounds["X"],
           let y = bounds["Y"],
           let w = bounds["Width"],
           let h = bounds["Height"] {
            windowBounds = CGRect(x: x, y: y, width: w, height: h)
            break
        }
    }

    print("Drawing element bounding boxes...")
    drawElementsOnScreenshot(screenshotPath: screenshotPath, elements: elements, windowBounds: windowBounds, outputPath: screenshotPath)

    let dateFormatter = ISO8601DateFormatter()
    let timestamp = dateFormatter.string(from: Date())

    let dump = ElementDump(
        app: app.localizedName ?? appName,
        timestamp: timestamp,
        screenshot: screenshotPath,
        elements: elements
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let jsonData = try encoder.encode(dump)
        let tmpDir = "/tmp"
        let fullJsonPath = (jsonPath as NSString).isAbsolutePath ? jsonPath : "\(tmpDir)/\(jsonPath)"
        try jsonData.write(to: URL(fileURLWithPath: fullJsonPath))
        print("Element data saved to: \(fullJsonPath)")
        print("Annotated screenshot saved to: \(screenshotPath)")
    } catch {
        print("Error saving JSON: \(error)")
    }
}

func dumpAllScreenElements(outputBaseName: String) {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    print("Collecting elements from all applications on screen...")

    var allElements: [DumpedElement] = []
    var elementId = 1

    for app in runningApps {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        let appName = app.localizedName ?? "Unknown"

        collectElements(appElement, elements: &allElements, elementId: &elementId)
    }

    print("Found \(allElements.count) total elements across all apps")

    let screenshotPath = "\(outputBaseName).png"
    let jsonPath = "\(outputBaseName).json"

    takeScreenshot(filename: screenshotPath)

    print("Drawing element bounding boxes...")
    drawElementsOnFullScreenshot(screenshotPath: screenshotPath, elements: allElements, outputPath: screenshotPath)

    let dateFormatter = ISO8601DateFormatter()
    let timestamp = dateFormatter.string(from: Date())

    let dump = ElementDump(
        app: "All Applications",
        timestamp: timestamp,
        screenshot: screenshotPath,
        elements: allElements
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    do {
        let jsonData = try encoder.encode(dump)
        let tmpDir = "/tmp"
        let fullJsonPath = (jsonPath as NSString).isAbsolutePath ? jsonPath : "\(tmpDir)/\(jsonPath)"
        try jsonData.write(to: URL(fileURLWithPath: fullJsonPath))
        print("Element data saved to: \(fullJsonPath)")
        print("Annotated screenshot saved to: \(screenshotPath)")
    } catch {
        print("Error saving JSON: \(error)")
    }
}

func dumpAllAttributes(appName: String, outputBaseName: String) {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased().contains(appName.lowercased()) {
            targetApp = app
            break
        }
    }

    guard let app = targetApp else {
        print("Error: Could not find running app '\(appName)'")
        return
    }

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    print("Collecting ALL attributes from \(app.localizedName ?? appName)...")

    var elements: [[String: Any]] = []
    collectElementsWithAllAttributes(appElement, elements: &elements)

    print("Found \(elements.count) elements")

    let jsonPath = "\(outputBaseName).json"

    let dateFormatter = ISO8601DateFormatter()
    let timestamp = dateFormatter.string(from: Date())

    let dump: [String: Any] = [
        "app": app.localizedName ?? appName,
        "timestamp": timestamp,
        "elements": elements
    ]

    do {
        let jsonData = try JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys])
        let tmpDir = "/tmp"
        let fullJsonPath = (jsonPath as NSString).isAbsolutePath ? jsonPath : "\(tmpDir)/\(jsonPath)"
        try jsonData.write(to: URL(fileURLWithPath: fullJsonPath))
        print("All attributes saved to: \(fullJsonPath)")
    } catch {
        print("Error saving JSON: \(error)")
    }
}

func drawElementsOnFullScreenshot(screenshotPath: String, elements: [DumpedElement], outputPath: String) {
    let tmpDir = "/tmp"
    let fullScreenshotPath = (screenshotPath as NSString).isAbsolutePath ? screenshotPath : "\(tmpDir)/\(screenshotPath)"

    guard let image = NSImage(contentsOfFile: fullScreenshotPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Failed to load screenshot")
        return
    }

    let width = cgImage.width
    let height = cgImage.height

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 4 * width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Error: Failed to create graphics context")
        return
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let scaleFactor = 2.0
    guard let mainScreen = NSScreen.main else {
        print("Error: Could not get main screen")
        return
    }
    let screenHeight = mainScreen.frame.height

    for element in elements {
        let elementX = CGFloat(element.x)
        let elementYScreen = CGFloat(element.y)
        let elementY = screenHeight - elementYScreen - CGFloat(element.height)

        if elementX < 0 || elementY < 0 {
            continue
        }

        let color = colorForRole(element.role)
        context.setStrokeColor(red: color.r, green: color.g, blue: color.b, alpha: 0.8)
        context.setLineWidth(3.0)

        let rect = CGRect(
            x: elementX * scaleFactor,
            y: elementY * scaleFactor,
            width: CGFloat(element.width) * scaleFactor,
            height: CGFloat(element.height) * scaleFactor
        )
        context.stroke(rect)

        let labelText: String
        if !element.title.isEmpty {
            labelText = element.title
        } else if !element.description.isEmpty {
            labelText = element.description
        } else {
            let roleShort = element.role.replacingOccurrences(of: "AX", with: "")
            labelText = "[\(roleShort)]"
        }

        let fontSize: CGFloat = 14
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: labelText, attributes: textAttributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let labelWidth = bounds.width
        let labelHeight = bounds.height
        let padding: CGFloat = 3

        let bgRect = CGRect(
            x: rect.origin.x + 3,
            y: rect.origin.y + 3,
            width: min(labelWidth + padding * 2, rect.width - 6),
            height: labelHeight + padding * 2
        )

        context.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.9)
        context.fill(bgRect)

        context.saveGState()
        context.textMatrix = CGAffineTransform.identity
        context.translateBy(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding)
        context.scaleBy(x: 1.0, y: 1.0)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    guard let finalImage = context.makeImage() else {
        print("Error: Failed to create final image")
        return
    }

    let fullOutputPath = (outputPath as NSString).isAbsolutePath ? outputPath : "\(tmpDir)/\(outputPath)"
    let url = URL(fileURLWithPath: fullOutputPath)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, finalImage, nil)
    CGImageDestinationFinalize(destination)
}

func getAllElementAttributes(_ element: AXUIElement) -> [String: Any] {
    var attributes: [String: Any] = [:]

    var attributeNamesValue: CFArray?
    let result = AXUIElementCopyAttributeNames(element, &attributeNamesValue)

    guard result == .success, let attributeNames = attributeNamesValue as? [String] else {
        return attributes
    }

    for attributeName in attributeNames {
        var attributeValue: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(element, attributeName as CFString, &attributeValue)

        if valueResult == .success, let value = attributeValue {
            if let stringValue = value as? String {
                attributes[attributeName] = stringValue
            } else if let boolValue = value as? Bool {
                attributes[attributeName] = boolValue
            } else if let numberValue = value as? NSNumber {
                attributes[attributeName] = numberValue
            } else if CFGetTypeID(value) == AXValueGetTypeID() {
                let axValue = value as! AXValue
                let valueType = AXValueGetType(axValue)

                if valueType == .cgPoint {
                    var point = CGPoint.zero
                    AXValueGetValue(axValue, .cgPoint, &point)
                    attributes[attributeName] = ["x": point.x, "y": point.y]
                } else if valueType == .cgSize {
                    var size = CGSize.zero
                    AXValueGetValue(axValue, .cgSize, &size)
                    attributes[attributeName] = ["width": size.width, "height": size.height]
                } else if valueType == .cgRect {
                    var rect = CGRect.zero
                    AXValueGetValue(axValue, .cgRect, &rect)
                    attributes[attributeName] = ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
                }
            } else if let arrayValue = value as? [Any] {
                attributes[attributeName] = "[Array with \(arrayValue.count) items]"
            } else {
                attributes[attributeName] = "\(type(of: value))"
            }
        }
    }

    return attributes
}

func collectElementsWithAllAttributes(_ element: AXUIElement, elements: inout [[String: Any]], depth: Int = 0, maxDepth: Int = 10) {
    if depth > maxDepth {
        return
    }

    var attributes = getAllElementAttributes(element)
    attributes["_depth"] = depth

    var position = CGPoint.zero
    var size = CGSize.zero

    if let posDict = attributes["AXPosition"] as? [String: CGFloat],
       let x = posDict["x"], let y = posDict["y"] {
        position = CGPoint(x: x, y: y)
    }

    if let sizeDict = attributes["AXSize"] as? [String: CGFloat],
       let width = sizeDict["width"], let height = sizeDict["height"] {
        size = CGSize(width: width, height: height)
    }

    if size.width > 0 && size.height > 0 {
        elements.append(attributes)
    }

    var childrenValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

    if result == .success, let children = childrenValue as? [AXUIElement] {
        for child in children {
            collectElementsWithAllAttributes(child, elements: &elements, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

func collectElements(_ element: AXUIElement, elements: inout [DumpedElement], elementId: inout Int, depth: Int = 0, maxDepth: Int = 10) {
    if depth > maxDepth {
        return
    }

    var roleValue: CFTypeRef?
    var titleValue: CFTypeRef?
    var descValue: CFTypeRef?
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    var enabledValue: CFTypeRef?
    var valueValue: CFTypeRef?
    var placeholderValue: CFTypeRef?

    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
    AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
    AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledValue)
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueValue)
    AXUIElementCopyAttributeValue(element, "AXPlaceholderValue" as CFString, &placeholderValue)

    let role = roleValue as? String ?? "unknown"
    let title = titleValue as? String ?? ""
    let desc = descValue as? String ?? ""
    let enabled = (enabledValue as? Bool) ?? true
    let value = valueValue as? String
    let placeholder = placeholderValue as? String

    var position = CGPoint.zero
    var size = CGSize.zero

    if let pos = posValue {
        AXValueGetValue(pos as! AXValue, .cgPoint, &position)
    }
    if let sz = sizeValue {
        AXValueGetValue(sz as! AXValue, .cgSize, &size)
    }

    let interactiveRoles = ["AXButton", "AXTextField", "AXLink", "AXTextArea", "AXScrollArea",
                            "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXComboBox",
                            "AXSlider", "AXTable", "AXList", "AXOutline", "AXGroup",
                            "AXMenuButton", "AXTabGroup", "AXWebArea", "AXRow", "AXCell"]
    let isInteractive = interactiveRoles.contains(role)

    if (!title.isEmpty || !desc.isEmpty || placeholder != nil || isInteractive) && size.width > 0 && size.height > 0 {
        let dumpedElement = DumpedElement(
            id: elementId,
            role: role,
            title: title,
            description: desc,
            x: Int(position.x),
            y: Int(position.y),
            width: Int(size.width),
            height: Int(size.height),
            enabled: enabled,
            value: value,
            placeholder: placeholder
        )
        elements.append(dumpedElement)
        elementId += 1
    }

    var childrenValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

    if result == .success, let children = childrenValue as? [AXUIElement] {
        for child in children {
            collectElements(child, elements: &elements, elementId: &elementId, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

func drawElementsOnScreenshot(screenshotPath: String, elements: [DumpedElement], windowBounds: CGRect?, outputPath: String) {
    let tmpDir = "/tmp"
    let fullScreenshotPath = (screenshotPath as NSString).isAbsolutePath ? screenshotPath : "\(tmpDir)/\(screenshotPath)"

    guard let image = NSImage(contentsOfFile: fullScreenshotPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Failed to load screenshot")
        return
    }

    let width = cgImage.width
    let height = cgImage.height

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 4 * width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Error: Failed to create graphics context")
        return
    }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let scaleFactor = 2.0
    let windowX = windowBounds?.origin.x ?? 0
    let windowY = windowBounds?.origin.y ?? 0
    let windowHeight = windowBounds?.height ?? CGFloat(height) / scaleFactor

    for element in elements {
        let elementX = CGFloat(element.x) - windowX
        let elementYScreen = CGFloat(element.y) - windowY
        let elementY = windowHeight - elementYScreen - CGFloat(element.height)

        if elementX < 0 || elementY < 0 {
            continue
        }

        let color = colorForRole(element.role)
        context.setStrokeColor(red: color.r, green: color.g, blue: color.b, alpha: 0.8)
        context.setLineWidth(3.0)

        let rect = CGRect(
            x: elementX * scaleFactor,
            y: elementY * scaleFactor,
            width: CGFloat(element.width) * scaleFactor,
            height: CGFloat(element.height) * scaleFactor
        )
        context.stroke(rect)

        let labelText: String
        if !element.title.isEmpty {
            labelText = element.title
        } else if !element.description.isEmpty {
            labelText = element.description
        } else {
            let roleShort = element.role.replacingOccurrences(of: "AX", with: "")
            labelText = "[\(roleShort)]"
        }

        let fontSize: CGFloat = 14
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: labelText, attributes: textAttributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let labelWidth = bounds.width
        let labelHeight = bounds.height
        let padding: CGFloat = 3

        let bgRect = CGRect(
            x: rect.origin.x + 3,
            y: rect.origin.y + 3,
            width: min(labelWidth + padding * 2, rect.width - 6),
            height: labelHeight + padding * 2
        )

        context.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.9)
        context.fill(bgRect)

        context.saveGState()
        context.textMatrix = CGAffineTransform.identity
        context.translateBy(x: bgRect.origin.x + padding, y: bgRect.origin.y + padding)
        context.scaleBy(x: 1.0, y: 1.0)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    guard let finalImage = context.makeImage() else {
        print("Error: Failed to create final image")
        return
    }

    let fullOutputPath = (outputPath as NSString).isAbsolutePath ? outputPath : "\(tmpDir)/\(outputPath)"
    let url = URL(fileURLWithPath: fullOutputPath)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, finalImage, nil)
    CGImageDestinationFinalize(destination)
}

func colorForRole(_ role: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    switch role {
    case "AXButton":
        return (0.0, 0.5, 1.0)  // Blue
    case "AXTextField", "AXTextArea":
        return (0.0, 0.8, 0.2)  // Green
    case "AXLink":
        return (1.0, 0.8, 0.0)  // Yellow
    case "AXMenuItem", "AXMenuButton":
        return (0.8, 0.0, 0.8)  // Purple
    case "AXCheckBox", "AXRadioButton":
        return (1.0, 0.5, 0.0)  // Orange
    case "AXScrollArea", "AXWebArea":
        return (0.0, 0.8, 0.8)  // Cyan
    case "AXTable", "AXList", "AXOutline":
        return (0.5, 0.0, 1.0)  // Violet
    default:
        return (1.0, 0.0, 0.0)  // Red
    }
}

func findAndClickInElements(name: String, elements: [DumpedElement], doubleClick: Bool, rightClick: Bool = false, targetApp: NSRunningApplication? = nil, offsetX: Int = 0, offsetY: Int = 0) {
    let searchLower = name.lowercased()
    var matches: [(element: DumpedElement, score: Double)] = []

    for element in elements {
        let titleLower = element.title.lowercased()
        let descLower = element.description.lowercased()
        let placeholderLower = (element.placeholder ?? "").lowercased()
        let valueLower = (element.value ?? "").lowercased()

        var score: Double = 0.0

        // Exact match (highest priority)
        if titleLower == searchLower || descLower == searchLower || placeholderLower == searchLower || valueLower == searchLower {
            score = 10.0
        }
        // Starts with
        else if titleLower.hasPrefix(searchLower) || descLower.hasPrefix(searchLower) || placeholderLower.hasPrefix(searchLower) || valueLower.hasPrefix(searchLower) {
            score = 5.0
        }
        // Contains
        else if titleLower.contains(searchLower) || descLower.contains(searchLower) || placeholderLower.contains(searchLower) || valueLower.contains(searchLower) {
            score = 3.0
        }

        if score > 0 {
            // Bonus for enabled elements
            if element.enabled {
                score += 1.0
            }
            // Bonus for clickable roles
            let clickableRoles = ["AXButton", "AXMenuItem", "AXLink", "AXTextField", "AXTextArea"]
            if clickableRoles.contains(element.role) {
                score += 0.5
            }

            matches.append((element, score))
        }
    }

    // Sort by score (highest first)
    matches.sort { $0.score > $1.score }

    if let best = matches.first {
        let element = best.element
        let centerX = CGFloat(element.x) + CGFloat(element.width) / 2.0
        let centerY = CGFloat(element.y) + CGFloat(element.height) / 2.0
        let finalX = centerX + CGFloat(offsetX)
        let finalY = centerY + CGFloat(offsetY)
        let position = CGPoint(x: finalX, y: finalY)

        // Auto-detect text fields - use single click for SwiftUI compatibility
        let textFieldRoles = ["AXTextField", "AXTextArea", "AXComboBox"]
        let isTextField = textFieldRoles.contains(element.role)

        print("Found '\(name)' at: x=\(Int(position.x)), y=\(Int(position.y))")

        // Always use click for text fields - most reliable for SwiftUI and AppKit
        if doubleClick {
            doubleClickMouse(x: Int(position.x), y: Int(position.y))
        } else if rightClick {
            rightClickMouse(x: Int(position.x), y: Int(position.y))
        } else {
            clickMouse(x: Int(position.x), y: Int(position.y))

            // For text fields, ensure proper focus
            if isTextField {
                usleep(200000) // 200ms for click to register and focus to establish

                // Ensure app is frontmost for keyboard input
                let workspace = NSWorkspace.shared
                if let frontApp = workspace.frontmostApplication {
                    let appName = frontApp.localizedName ?? "Unknown"
                    frontApp.activate(options: [.activateIgnoringOtherApps])
                    usleep(150000) // 150ms for activation

                    // Additional step: Click on window title bar first to ensure window is key
                    // This is crucial for fresh launches
                    if let targetApp = targetApp {
                        let pid = targetApp.processIdentifier
                        let appElement = AXUIElementCreateApplication(pid)

                        // Get the main window
                        var mainWindowRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindowRef) == .success,
                           let mainWindow = mainWindowRef {
                            // Make window key by setting focused
                            AXUIElementSetAttributeValue(mainWindow as! AXUIElement, kAXMainAttribute as CFString, kCFBooleanTrue)
                            usleep(100000) // 100ms for window to become key
                        }
                    }

                    // Click the text field one more time to ensure it's really focused
                    clickMouse(x: Int(position.x), y: Int(position.y))
                    usleep(150000) // 150ms for second click to register

                    // Now try to explicitly set focus on the text field using AX API
                    if let targetApp = targetApp {
                        let pid = targetApp.processIdentifier
                        let appElement = AXUIElementCreateApplication(pid)

                        // Try to find the element at the clicked position and set focus
                        if let axElement = findAXElement(appElement: appElement, position: position) {
                            // Try to set focused attribute
                            AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                            usleep(150000) // 150ms for focus to take effect
                        }
                    }

                    // CRITICAL FIX: Send a Tab key to establish keyboard responder chain
                    // This is necessary for fresh launches where the window hasn't had keyboard input yet
                    let tabKeyCode: CGKeyCode = 0x30
                    if let tabDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: tabKeyCode, keyDown: true) {
                        tabDownEvent.post(tap: .cghidEventTap)
                    }
                    usleep(50000) // 50ms
                    if let tabUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: tabKeyCode, keyDown: false) {
                        tabUpEvent.post(tap: .cghidEventTap)
                    }
                    usleep(50000) // 50ms for tab to take effect

                    // Tab moves focus forward, so send Shift+Tab to move back to our text field
                    let shiftTabDown = CGEvent(keyboardEventSource: nil, virtualKey: tabKeyCode, keyDown: true)
                    shiftTabDown?.flags = .maskShift
                    shiftTabDown?.post(tap: .cghidEventTap)
                    usleep(50000)
                    let shiftTabUp = CGEvent(keyboardEventSource: nil, virtualKey: tabKeyCode, keyDown: false)
                    shiftTabUp?.flags = .maskShift
                    shiftTabUp?.post(tap: .cghidEventTap)
                    usleep(100000) // 100ms for focus to settle

                    // Save app name to temp file so type command can re-activate if needed
                    let appNamePath = "/tmp/claude-click-last-app.txt"
                    try? appName.write(toFile: appNamePath, atomically: true, encoding: .utf8)

                    print("Text field ready for input")
                }
            }
        }
    } else {
        print("Could not find element: \(name)")
        if !matches.isEmpty {
            print("Similar elements found:")
            for (i, match) in matches.prefix(5).enumerated() {
                print("  \(i+1). '\(match.element.title)' (\(match.element.role))")
            }
        }
    }
}

func findAXElement(appElement: AXUIElement, position: CGPoint) -> AXUIElement? {
    // Try to find the element at the given position using AX API
    var axElement: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(appElement, Float(position.x), Float(position.y), &axElement)

    if result == .success, let element = axElement {
        return element
    }
    return nil
}

func checkElementExists(name: String, appName: String, timeout: Double = 0.0) -> Bool {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var targetApp: NSRunningApplication?
    var exactBundleMatch: NSRunningApplication?

    for runningApp in runningApps {
        let localizedName = runningApp.localizedName ?? ""
        let bundleURL = runningApp.bundleURL?.lastPathComponent ?? ""

        if bundleURL.lowercased() == appName.lowercased() + ".app" {
            exactBundleMatch = runningApp
            break
        }

        if localizedName.lowercased() == appName.lowercased() {
            if exactBundleMatch == nil {
                exactBundleMatch = runningApp
            }
        }

        if exactBundleMatch == nil {
            if !localizedName.contains("Service") && !localizedName.contains("Helper") {
                if localizedName.lowercased().contains(appName.lowercased()) {
                    if targetApp == nil {
                        targetApp = runningApp
                    }
                }
            }
        }
    }

    let foundApp = exactBundleMatch ?? targetApp

    guard let targetApp = foundApp else {
        return false
    }

    let pid = targetApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)

    let searchLower = name.lowercased()
    var matches: [(element: DumpedElement, score: Double)] = []

    for element in elements {
        let titleLower = element.title.lowercased()
        let descLower = element.description.lowercased()

        var score: Double = 0.0

        if titleLower == searchLower || descLower == searchLower {
            score = 10.0
        } else if titleLower.hasPrefix(searchLower) || descLower.hasPrefix(searchLower) {
            score = 5.0
        } else if titleLower.contains(searchLower) || descLower.contains(searchLower) {
            score = 3.0
        }

        if score > 0 {
            if element.enabled {
                score += 1.0
            }
            let clickableRoles = ["AXButton", "AXMenuItem", "AXLink", "AXTextField", "AXTextArea"]
            if clickableRoles.contains(element.role) {
                score += 0.5
            }

            matches.append((element, score))
        }
    }

    matches.sort { $0.score > $1.score }
    return !matches.isEmpty
}

func getElementValue(name: String, appName: String) -> String? {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var targetApp: NSRunningApplication?
    var exactBundleMatch: NSRunningApplication?

    for runningApp in runningApps {
        let localizedName = runningApp.localizedName ?? ""
        let bundleURL = runningApp.bundleURL?.lastPathComponent ?? ""

        if bundleURL.lowercased() == appName.lowercased() + ".app" {
            exactBundleMatch = runningApp
            break
        }

        if localizedName.lowercased() == appName.lowercased() {
            if exactBundleMatch == nil {
                exactBundleMatch = runningApp
            }
        }

        if exactBundleMatch == nil {
            if !localizedName.contains("Service") && !localizedName.contains("Helper") {
                if localizedName.lowercased().contains(appName.lowercased()) {
                    if targetApp == nil {
                        targetApp = runningApp
                    }
                }
            }
        }
    }

    let foundApp = exactBundleMatch ?? targetApp

    guard let targetApp = foundApp else {
        return nil
    }

    let pid = targetApp.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)

    let searchLower = name.lowercased()
    var matches: [(element: DumpedElement, score: Double)] = []

    for element in elements {
        let titleLower = element.title.lowercased()
        let descLower = element.description.lowercased()

        var score: Double = 0.0

        if titleLower == searchLower || descLower == searchLower {
            score = 10.0
        } else if titleLower.hasPrefix(searchLower) || descLower.hasPrefix(searchLower) {
            score = 5.0
        } else if titleLower.contains(searchLower) || descLower.contains(searchLower) {
            score = 3.0
        }

        if score > 0 {
            if element.enabled {
                score += 1.0
            }
            matches.append((element, score))
        }
    }

    matches.sort { $0.score > $1.score }

    if let best = matches.first {
        let element = best.element
        if let value = element.value, !value.isEmpty {
            return value
        }
        return element.title.isEmpty ? element.description : element.title
    }

    return nil
}

func findAndClick(name: String, appName: String? = nil, doubleClick: Bool = false, rightClick: Bool = false, offsetX: Int = 0, offsetY: Int = 0) {
    // If app name specified, check if already running first
    if let app = appName {
        print("Searching for element: \(name) in application: \(app)")

        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        var targetApp: NSRunningApplication?
        var exactBundleMatch: NSRunningApplication?

        // Check if app is already running
        for runningApp in runningApps {
            let localizedName = runningApp.localizedName ?? ""
            let bundleURL = runningApp.bundleURL?.lastPathComponent ?? ""

            if bundleURL.lowercased() == app.lowercased() + ".app" {
                exactBundleMatch = runningApp
                break
            }

            if localizedName.lowercased() == app.lowercased() {
                if exactBundleMatch == nil {
                    exactBundleMatch = runningApp
                }
            }

            if exactBundleMatch == nil {
                if !localizedName.contains("Service") && !localizedName.contains("Helper") {
                    if localizedName.lowercased().contains(app.lowercased()) {
                        if targetApp == nil {
                            targetApp = runningApp
                        }
                    }
                }
            }
        }

        let foundApp = exactBundleMatch ?? targetApp

        // Only call 'open -a' if app is NOT already running
        if foundApp == nil {
            print("Opening \(app)...")
            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = ["-a", app]

            do {
                try openProcess.run()
                openProcess.waitUntilExit()

                if openProcess.terminationStatus != 0 {
                    print("Error: Failed to open app '\(app)'")
                    return
                }
            } catch {
                print("Error opening app: \(error)")
                return
            }
        } else {
            print("App '\(app)' already running")
        }

        // Wait for app to become frontmost with timeout
        let startTime = Date()
        let timeout = 3.0

        while Date().timeIntervalSince(startTime) < timeout {
            let runningApps = workspace.runningApplications
            exactBundleMatch = nil
            targetApp = nil

            for runningApp in runningApps {
                let localizedName = runningApp.localizedName ?? ""
                let bundleURL = runningApp.bundleURL?.lastPathComponent ?? ""

                // Priority 1: Exact bundle name match (e.g., "Xcode3.app" matches "Xcode3")
                // This prevents "Xcode" from matching when we want "Xcode3"
                if bundleURL.lowercased() == app.lowercased() + ".app" {
                    exactBundleMatch = runningApp
                    break
                }

                // Priority 2: Exact localized name match
                if localizedName.lowercased() == app.lowercased() {
                    if exactBundleMatch == nil {
                        exactBundleMatch = runningApp
                    }
                }

                // Priority 3: Partial match as fallback (skip helper processes)
                // Only use if no exact match found
                if exactBundleMatch == nil {
                    if !localizedName.contains("Service") && !localizedName.contains("Helper") {
                        if localizedName.lowercased().contains(app.lowercased()) {
                            if targetApp == nil {
                                targetApp = runningApp
                            }
                        }
                    }
                }
            }

            // Use exact match if found, otherwise use partial match
            let appToCheck = exactBundleMatch ?? targetApp

            // Check if we found the app and it's active
            if let foundApp = appToCheck, foundApp.isActive {
                targetApp = foundApp
                print("App is ready: \(foundApp.localizedName ?? app) (bundle: \(foundApp.bundleURL?.lastPathComponent ?? "unknown"))")
                break
            } else if let foundApp = appToCheck {
                targetApp = foundApp
            }

            // Small delay before checking again
            usleep(50_000) // 50ms
        }

        guard let targetApp = targetApp else {
            print("Error: Could not find app '\(app)' in running applications")
            return
        }

        // If app isn't active yet, give it a bit more time
        if !targetApp.isActive {
            print("Waiting for app activation...")
            usleep(300_000) // 300ms
        }

        let bundleName = targetApp.bundleURL?.lastPathComponent ?? "unknown"
        print("Using app: \(targetApp.localizedName ?? app) (bundle: \(bundleName))")

        // Collect elements directly from the app using AX API
        let pid = targetApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var elements: [DumpedElement] = []
        var elementId = 1
        collectElements(appElement, elements: &elements, elementId: &elementId)

        print("Collected \(elements.count) elements from \(targetApp.localizedName ?? app)")

        // Use helper function to find and click, passing targetApp for AX focus
        findAndClickInElements(name: name, elements: elements, doubleClick: doubleClick, rightClick: rightClick, targetApp: targetApp, offsetX: offsetX, offsetY: offsetY)
        return
    } else {
        print("Searching for element: \(name)")
    }

    // Fallback to JSON-based search if no app specified
    if let position = findElementByName(name: name, appName: appName) {
        print("Found '\(name)' at: x=\(Int(position.x)), y=\(Int(position.y))")
        if doubleClick {
            doubleClickMouse(x: Int(position.x), y: Int(position.y))
        } else {
            clickMouse(x: Int(position.x), y: Int(position.y))
        }
    } else {
        print("Could not find element: \(name)")
    }
}



func takeScreenshot(filename: String) {
    guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
        print("Error: Failed to capture screen")
        return
    }

    // Use /tmp directory by default
    let tmpDir = "/tmp"
    let fullPath = (filename as NSString).isAbsolutePath ? filename : "\(tmpDir)/\(filename)"
    let url = URL(fileURLWithPath: fullPath)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, image, nil)

    if CGImageDestinationFinalize(destination) {
        print("Screenshot saved to: \(fullPath)")
    } else {
        print("Error: Failed to save screenshot")
    }
}

func takeWindowScreenshot(appName: String, filename: String, fullResolution: Bool = false) {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?
    var partialMatch: NSRunningApplication?
    var activeMatch: NSRunningApplication?

    // First pass: look for exact match, collect partial matches, prioritize active apps
    for app in runningApps {
        let localizedName = app.localizedName ?? ""

        if localizedName.lowercased() == appName.lowercased() {
            if app.isActive {
                activeMatch = app
                targetApp = app
                break
            } else if targetApp == nil {
                targetApp = app
            }
        } else if localizedName.lowercased().contains(appName.lowercased()) {
            if app.isActive && activeMatch == nil {
                activeMatch = app
            }
            if partialMatch == nil {
                partialMatch = app
            }
        }
    }

    // Priority: active match > exact match > partial match
    if activeMatch != nil {
        targetApp = activeMatch
    } else if targetApp == nil {
        targetApp = partialMatch
    }

    guard let app = targetApp else {
        print("Error: Could not find running app '\(appName)'")
        return
    }

    let pid = app.processIdentifier

    // Get window list
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        print("Error: Could not get window list")
        return
    }

    // Find windows belonging to this app
    var targetWindowID: CGWindowID?
    var allWindows: [(id: CGWindowID, layer: Int, size: CGSize)] = []

    for window in windowList {
        if let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
           windowPID == pid {
            let windowLayer = window[kCGWindowLayer as String] as? Int ?? -1
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            let width = bounds?["Width"] ?? 0
            let height = bounds?["Height"] ?? 0
            let windowID = window[kCGWindowNumber as String] as? CGWindowID ?? 0

            if windowLayer == 0 {
                allWindows.append((id: windowID, layer: windowLayer, size: CGSize(width: width, height: height)))
            }
        }
    }

    // Select the largest window (prefer main window over toolbars/menus)
    if !allWindows.isEmpty {
        let sorted = allWindows.sorted { $0.size.width * $0.size.height > $1.size.width * $1.size.height }
        targetWindowID = sorted.first?.id
    }

    guard let windowID = targetWindowID else {
        print("Error: Could not find window for '\(appName)'")
        return
    }

    // Capture just this window
    guard let windowImage = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        windowID,
        [.boundsIgnoreFraming, .bestResolution]
    ) else {
        print("Error: Failed to capture window image")
        return
    }

    let tmpDir = "/tmp"
    let fullPath = (filename as NSString).isAbsolutePath ? filename : "\(tmpDir)/\(filename)"
    let url = URL(fileURLWithPath: fullPath)

    let finalImage: CGImage
    let finalWidth: Int
    let finalHeight: Int

    if fullResolution {
        finalImage = windowImage
        finalWidth = windowImage.width
        finalHeight = windowImage.height
    } else {
        // Downscale to 1/4 size (1/2 in each dimension)
        let scaledWidth = windowImage.width / 2
        let scaledHeight = windowImage.height / 2

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: scaledWidth,
            height: scaledHeight,
            bitsPerComponent: 8,
            bytesPerRow: 4 * scaledWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("Error: Failed to create graphics context for downscaling")
            return
        }

        context.interpolationQuality = .medium
        context.draw(windowImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))

        guard let scaledImage = context.makeImage() else {
            print("Error: Failed to scale image")
            return
        }

        finalImage = scaledImage
        finalWidth = scaledWidth
        finalHeight = scaledHeight
    }

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, finalImage, nil)

    if CGImageDestinationFinalize(destination) {
        print("Window screenshot saved to: \(fullPath)")
        print("App: \(app.localizedName ?? "Unknown")")
        print("Window size: \(finalWidth)x\(finalHeight) pixels")
    } else {
        print("Error: Failed to save screenshot")
    }
}

func takeAppScreenshot(appName: String, filename: String) {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?
    var partialMatch: NSRunningApplication?

    // First pass: look for exact match, collect partial matches
    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased() == appName.lowercased() {
            targetApp = app
            break
        } else if localizedName.lowercased().contains(appName.lowercased()) {
            if partialMatch == nil {
                partialMatch = app
            }
        }
    }

    // Use partial match if no exact match found
    if targetApp == nil {
        targetApp = partialMatch
    }

    guard let app = targetApp else {
        print("Error: Could not find running app '\(appName)'")
        return
    }

    print("Found app '\(appName)', capturing all displays...")

    // Get all active displays
    var displayCount: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &displayCount)
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
    CGGetActiveDisplayList(displayCount, &displays, &displayCount)

    print("Capturing \(displayCount) display(s)")

    // Get the bounds of all displays
    var displayImages: [(bounds: CGRect, image: CGImage)] = []
    var minX = CGFloat.infinity
    var minY = CGFloat.infinity
    var maxX = -CGFloat.infinity
    var maxY = -CGFloat.infinity

    for display in displays {
        let bounds = CGDisplayBounds(display)
        guard let image = CGDisplayCreateImage(display) else {
            print("Warning: Could not capture display at \(bounds)")
            continue
        }
        displayImages.append((bounds: bounds, image: image))

        minX = min(minX, bounds.origin.x)
        minY = min(minY, bounds.origin.y)
        maxX = max(maxX, bounds.origin.x + bounds.width)
        maxY = max(maxY, bounds.origin.y + bounds.height)
    }

    guard !displayImages.isEmpty else {
        print("Error: Could not capture any displays")
        return
    }

    let totalWidth = Int(maxX - minX)
    let totalHeight = Int(maxY - minY)

    print("Total screen space: \(totalWidth)x\(totalHeight) logical pixels")

    // Calculate pixel dimensions (accounting for Retina)
    let scale = CGFloat(displayImages[0].image.width) / displayImages[0].bounds.width
    let pixelWidth = Int(CGFloat(totalWidth) * scale)
    let pixelHeight = Int(CGFloat(totalHeight) * scale)

    // Create a combined image
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 4 * pixelWidth,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else {
        print("Error: Failed to create graphics context")
        return
    }

    // Draw each display image at its correct position
    for (bounds, image) in displayImages {
        let x = (bounds.origin.x - minX) * scale
        let y = (bounds.origin.y - minY) * scale
        let width = bounds.width * scale
        let height = bounds.height * scale

        let rect = CGRect(x: x, y: y, width: width, height: height)
        context.draw(image, in: rect)
    }

    guard let combinedImage = context.makeImage() else {
        print("Error: Failed to create combined image")
        return
    }

    // Save the image
    let tmpDir = "/tmp"
    let fullPath = (filename as NSString).isAbsolutePath ? filename : "\(tmpDir)/\(filename)"
    let url = URL(fileURLWithPath: fullPath)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
        print("Error: Failed to create image destination")
        return
    }

    CGImageDestinationAddImage(destination, combinedImage, nil)

    if CGImageDestinationFinalize(destination) {
        print("Screenshot saved to: \(fullPath)")
        print("App: \(app.localizedName ?? "Unknown")")
        print("Combined image size: \(combinedImage.width)x\(combinedImage.height) pixels")
    } else {
        print("Error: Failed to save screenshot")
    }
}

func monitorAppActivity(appName: String, timeout: Double = 0) {
    print("Monitoring activity for '\(appName)'...")
    print("Press Ctrl+C to stop")
    print(String(repeating: "=", count: 80))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "stream",
        "--predicate",
        "subsystem == \"com.apple.launchservices\" AND composedMessage CONTAINS \"\(appName)\"",
        "--level", "info"
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let outputHandle = pipe.fileHandleForReading

    outputHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if data.count > 0, let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                if line.contains("Found application") {
                    if line.contains("to open") {
                        print("App launched: \(appName)")
                        print("  \(line)")
                    }
                } else if line.contains("terminate") || line.contains("exit") {
                    print("App terminated: \(appName)")
                    print("  \(line)")
                } else if !line.contains("Filtering") && !line.contains("Timestamp") {
                    print(line)
                }
            }
        }
    }

    do {
        try process.run()

        if timeout > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                process.terminate()
                print("\nMonitoring timeout reached (\(timeout)s)")
                exit(0)
            }
        }

        process.waitUntilExit()
    } catch {
        print("Error: Failed to start log stream: \(error)")
        exit(1)
    }
}

func monitorDaemon(logFile: String) {
    print("Starting monitor daemon...")
    print("Writing events to: \(logFile)")
    print("Press Ctrl+C to stop")
    print(String(repeating: "=", count: 80))

    let logFileURL = URL(fileURLWithPath: logFile)
    let logFilePath = NSString(string: logFile).expandingTildeInPath

    // Create initial log file
    let header = "Monitor daemon started at \(Date())\n"
    try? header.write(toFile: logFilePath, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "stream",
        "--predicate",
        "subsystem == \"com.apple.launchservices\"",
        "--level", "info"
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let outputHandle = pipe.fileHandleForReading
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    outputHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if data.count > 0, let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                var eventType: String?
                var appName: String?
                var pid: String?

                // Parse LAUNCH events
                if line.contains("LAUNCH:") && line.contains("Opening") {
                    eventType = "LAUNCH"
                    if let range = line.range(of: #"/([^/]+)\.app/"#, options: .regularExpression) {
                        let match = String(line[range])
                        appName = match.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: ".app", with: "")
                    }
                }
                // Parse ACTIVATE events (menu bar ownership)
                else if line.contains("Making App:") && line.contains("into menu bar owning process") {
                    eventType = "ACTIVATE"
                    if let range = line.range(of: #"App:"([^"]+)""#, options: .regularExpression) {
                        let match = String(line[range])
                        appName = match.replacingOccurrences(of: "App:\"", with: "").replacingOccurrences(of: "\"", with: "")
                    }
                    if let range = line.range(of: #"pid:(\d+)"#, options: .regularExpression) {
                        let match = String(line[range])
                        pid = match.replacingOccurrences(of: "pid:", with: "")
                    }
                }
                // Parse FRONT events (moving to front)
                else if line.contains("Moving App:") && line.contains("to front of visible list") {
                    eventType = "FRONT"
                    if let range = line.range(of: #"App:"([^"]+)""#, options: .regularExpression) {
                        let match = String(line[range])
                        appName = match.replacingOccurrences(of: "App:\"", with: "").replacingOccurrences(of: "\"", with: "")
                    }
                    if let range = line.range(of: #"pid:(\d+)"#, options: .regularExpression) {
                        let match = String(line[range])
                        pid = match.replacingOccurrences(of: "pid:", with: "")
                    }
                }

                // Write event to file if we parsed something useful
                if let eventType = eventType, let appName = appName {
                    let timestamp = dateFormatter.string(from: Date())
                    var logEntry = "[\(timestamp)] \(eventType): \(appName)"
                    if let pid = pid {
                        logEntry += " (pid:\(pid))"
                    }
                    logEntry += "\n"

                    // Append to log file
                    if let fileHandle = FileHandle(forWritingAtPath: logFilePath) {
                        fileHandle.seekToEndOfFile()
                        if let data = logEntry.data(using: .utf8) {
                            fileHandle.write(data)
                        }
                        fileHandle.closeFile()
                    }

                    // Also print to console
                    print(logEntry, terminator: "")
                }
            }
        }
    }

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("Error: Failed to start log stream: \(error)")
        exit(1)
    }
}

func startScreenElementMonitor(outputPath: String, interval: Double = 0.5) {
    print("Starting unified element monitor daemon...")
    print("Monitoring ALL applications → \(DEFAULT_SCREEN_ELEMENTS_PATH)")
    print("Monitoring focused app → \(DEFAULT_FOCUSED_APP_PATH)")
    print("Update interval: \(interval)s")
    print("Press Ctrl+C to stop")
    print(String(repeating: "=", count: 80))

    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    timer.schedule(deadline: .now(), repeating: interval)

    timer.setEventHandler {
        autoreleasepool {
            let workspace = NSWorkspace.shared
            let runningApps = workspace.runningApplications

            // Update screen elements
            var allElements: [DumpedElement] = []
            var elementId = 1

            for app in runningApps {
                let pid = app.processIdentifier
                let appElement = AXUIElementCreateApplication(pid)
                collectElements(appElement, elements: &allElements, elementId: &elementId)
            }

            let dateFormatter = ISO8601DateFormatter()
            let timestamp = dateFormatter.string(from: Date())

            // Save screen elements
            let screenDump = ElementDump(
                app: "All Applications",
                timestamp: timestamp,
                screenshot: "",
                elements: allElements
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            do {
                let jsonData = try encoder.encode(screenDump)
                try jsonData.write(to: URL(fileURLWithPath: DEFAULT_SCREEN_ELEMENTS_PATH))
            } catch {
                print("[\(timestamp)] Error saving screen elements: \(error)")
            }

            // Update focused app elements
            if let frontApp = workspace.frontmostApplication {
                let pid = frontApp.processIdentifier
                let appElement = AXUIElementCreateApplication(pid)
                let appName = frontApp.localizedName ?? "Unknown"

                var focusedElements: [DumpedElement] = []
                var focusedId = 1
                collectElements(appElement, elements: &focusedElements, elementId: &focusedId)

                let focusedDump = ElementDump(
                    app: appName,
                    timestamp: timestamp,
                    screenshot: "",
                    elements: focusedElements
                )

                do {
                    let jsonData = try encoder.encode(focusedDump)
                    try jsonData.write(to: URL(fileURLWithPath: DEFAULT_FOCUSED_APP_PATH))
                } catch {
                    print("[\(timestamp)] Error saving focused app: \(error)")
                }

                print("[\(timestamp)] Screen: \(allElements.count) | Focused (\(appName)): \(focusedElements.count)")
            }
        }
    }

    timer.resume()

    RunLoop.main.run()
}

func startFocusedAppMonitor(outputPath: String, interval: Double = 0.5) {
    print("Starting event-driven focused app monitor...")
    print("Monitoring app switches via system logs")
    print("Output: \(outputPath)")
    print("Press Ctrl+C to stop")
    print(String(repeating: "=", count: 80))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "stream",
        "--predicate",
        "subsystem == \"com.apple.launchservices\"",
        "--level", "info"
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    let outputHandle = pipe.fileHandleForReading
    let dateFormatter = ISO8601DateFormatter()

    var lastAppName: String? = nil

    // Function to collect and save elements for an app
    func updateElementsForApp(_ appName: String, pid: Int32) {
        autoreleasepool {
            let appElement = AXUIElementCreateApplication(pid)
            var elements: [DumpedElement] = []
            var elementId = 1
            collectElements(appElement, elements: &elements, elementId: &elementId)

            let timestamp = dateFormatter.string(from: Date())
            let dump = ElementDump(
                app: appName,
                timestamp: timestamp,
                screenshot: "",
                elements: elements
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            do {
                let jsonData = try encoder.encode(dump)
                let tmpDir = "/tmp"
                let fullPath = (outputPath as NSString).isAbsolutePath ? outputPath : "\(tmpDir)/\(outputPath)"
                try jsonData.write(to: URL(fileURLWithPath: fullPath))
                print("[\(timestamp)] \(appName): \(elements.count) elements")
            } catch {
                print("[\(timestamp)] Error: \(error)")
            }
        }
    }

    outputHandle.readabilityHandler = { handle in
        let data = handle.availableData
        if data.count > 0, let output = String(data: data, encoding: .utf8) {
            let lines = output.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                var appName: String? = nil
                var pidValue: Int32? = nil

                // Parse ACTIVATE events (menu bar ownership)
                if line.contains("Making App:") && line.contains("into menu bar owning process") {
                    if let range = line.range(of: #"App:"([^"]+)""#, options: .regularExpression) {
                        let match = String(line[range])
                        appName = match.replacingOccurrences(of: "App:\"", with: "").replacingOccurrences(of: "\"", with: "")
                    }
                    if let range = line.range(of: #"pid:(\d+)"#, options: .regularExpression) {
                        let match = String(line[range])
                        if let pid = Int32(match.replacingOccurrences(of: "pid:", with: "")) {
                            pidValue = pid
                        }
                    }
                }

                // Update elements when app changes
                if let appName = appName, let pid = pidValue, appName != lastAppName {
                    lastAppName = appName
                    updateElementsForApp(appName, pid: pid)
                }
            }
        }
    }

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("Error: Failed to start log stream: \(error)")
        exit(1)
    }
}

func takeQuickScreenshot(appName: String?, filename: String) {
    let defaultFilename = "quick-screenshot.jpg"
    let finalFilename = filename

    let tempPngPath = "/tmp/temp-screenshot-\(UUID().uuidString).png"

    if let app = appName {
        takeWindowScreenshot(appName: app, filename: tempPngPath)
    } else {
        takeScreenshot(filename: tempPngPath)
    }

    guard let image = NSImage(contentsOfFile: tempPngPath),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Error: Failed to load screenshot")
        try? FileManager.default.removeItem(atPath: tempPngPath)
        return
    }

    let scaledWidth = cgImage.width / 4
    let scaledHeight = cgImage.height / 4

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: scaledWidth,
        height: scaledHeight,
        bitsPerComponent: 8,
        bytesPerRow: 4 * scaledWidth,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Error: Failed to create graphics context")
        try? FileManager.default.removeItem(atPath: tempPngPath)
        return
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))

    guard let scaledImage = context.makeImage() else {
        print("Error: Failed to scale image")
        try? FileManager.default.removeItem(atPath: tempPngPath)
        return
    }

    let tmpDir = "/tmp"
    let fullPath = (finalFilename as NSString).isAbsolutePath ? finalFilename : "\(tmpDir)/\(finalFilename)"
    let url = URL(fileURLWithPath: fullPath)

    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypeJPEG, 1, nil) else {
        print("Error: Failed to create image destination")
        try? FileManager.default.removeItem(atPath: tempPngPath)
        return
    }

    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.4
    ]
    CGImageDestinationAddImage(destination, scaledImage, options as CFDictionary)

    if CGImageDestinationFinalize(destination) {
        print("Quick screenshot saved to: \(fullPath)")
        if let app = appName {
            print("App: \(app)")
        }
        print("Size: \(scaledWidth)x\(scaledHeight) pixels (25% scale)")

        if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
           let fileSize = attrs[.size] as? UInt64 {
            print("File size: \(fileSize / 1024)KB")
        }
    } else {
        print("Error: Failed to save screenshot")
    }

    try? FileManager.default.removeItem(atPath: tempPngPath)
}

func getBuildErrors() -> [String] {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?
    var allXcodes: [NSRunningApplication] = []

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleName = app.bundleURL?.lastPathComponent ?? ""

        if localizedName.lowercased() == "xcode" || bundleName.lowercased().hasPrefix("xcode") {
            allXcodes.append(app)
            if app.isActive {
                targetApp = app
            }
        }
    }

    if targetApp == nil && !allXcodes.isEmpty {
        var bestXcode: (app: NSRunningApplication, elementCount: Int)?

        for xcode in allXcodes {
            let pid = xcode.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            var tempElements: [DumpedElement] = []
            var tempId = 1
            collectElements(appElement, elements: &tempElements, elementId: &tempId, depth: 0, maxDepth: 3)

            if bestXcode == nil || tempElements.count > bestXcode!.elementCount {
                bestXcode = (xcode, tempElements.count)
            }
        }

        targetApp = bestXcode?.app ?? allXcodes.first
    }

    guard let app = targetApp else {
        return []
    }

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var errors: [String] = []
    searchForErrors(appElement, errors: &errors, depth: 0, maxDepth: 15)

    return errors
}

func searchForErrors(_ element: AXUIElement, errors: inout [String], depth: Int, maxDepth: Int) {
    if depth > maxDepth { return }

    var role: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    let roleStr = role as? String ?? ""

    var desc: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
    let descStr = desc as? String ?? ""

    // Check for error buttons (Issue Navigator)
    if roleStr == "AXButton" && descStr.contains("Error Line") {
        errors.append(descStr)
    }

    // Also check static text for error messages
    if roleStr == "AXStaticText" {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        let valueStr = value as? String ?? ""

        if valueStr.contains("error:") || valueStr.contains("Cannot find") {
            // Don't add duplicates
            if !errors.contains(valueStr) {
                errors.append(valueStr)
            }
        }
    }

    var children: AnyObject?
    AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

    if let childArray = children as? [AXUIElement] {
        for child in childArray {
            searchForErrors(child, errors: &errors, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}

func monitorBuildWithErrors(appName: String, timeout: Double = 60.0, activate: Bool = false) -> (launched: Bool, errors: [String]) {
    let startTime = Date()
    print("Monitoring build for '\(appName)' (timeout: \(timeout)s)...")
    print("Checking for compilation errors...")

    var lastErrorCount = 0
    var foundApp: NSRunningApplication?
    var errorFirstDetected: Date?
    var buildFinishWaitTime = 3.0  // Wait 3s after first error to see if build finishes

    while Date().timeIntervalSince(startTime) < timeout {
        // Check if app launched (build succeeded)
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        foundApp = nil  // Reset each loop
        for app in runningApps {
            let localizedName = app.localizedName ?? ""
            let bundleIdentifier = app.bundleIdentifier ?? ""

            if localizedName.lowercased().contains(appName.lowercased()) ||
               bundleIdentifier.lowercased().contains(appName.lowercased()) {
                foundApp = app
                break
            }
        }

        if let app = foundApp {
            // App found, give it a moment for window to appear
            usleep(2000000) // Wait 2s for window to fully load

            let elapsed = Date().timeIntervalSince(startTime)
            print("✅ BUILD SUCCEEDED - App '\(appName)' launched in \(String(format: "%.2f", elapsed))s")

            if activate {
                app.activate(options: [.activateIgnoringOtherApps])
                usleep(500000)
                print("Activated '\(appName)'")
            }

            return (true, [])
        }

        // Check for build errors
        let errors = getBuildErrors()
        if !errors.isEmpty {
            if errors.count != lastErrorCount {
                print("❌ BUILD ERROR DETECTED:")
                for error in errors {
                    print("  • \(error)")
                }
                lastErrorCount = errors.count
            }

            // Mark when we first detected errors
            if errorFirstDetected == nil {
                errorFirstDetected = Date()
            }

            // If errors have been present for buildFinishWaitTime seconds and count hasn't changed,
            // assume build has finished with errors
            if let firstDetected = errorFirstDetected,
               Date().timeIntervalSince(firstDetected) >= buildFinishWaitTime {
                print("❌ BUILD FAILED - Found \(errors.count) error(s)")
                return (false, errors)
            }
        } else {
            // No errors anymore - reset the timer
            errorFirstDetected = nil
        }

        usleep(100000) // Check every 100ms
    }

    // Timeout reached - check one final time for errors
    let finalErrors = getBuildErrors()
    if !finalErrors.isEmpty {
        print("❌ BUILD FAILED - Found \(finalErrors.count) error(s)")
        return (false, finalErrors)
    }

    print("⏱️  TIMEOUT - App '\(appName)' did not launch after \(timeout) seconds")
    return (false, [])
}

struct TestResults: Codable {
    var passed: Int
    var failed: Int
    var total: Int
    var failures: [String]
    var success: Bool
}

func getXcodeTestResults() -> TestResults? {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?
    var allXcodes: [NSRunningApplication] = []

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleName = app.bundleURL?.lastPathComponent ?? ""

        if localizedName.lowercased() == "xcode" || bundleName.lowercased().hasPrefix("xcode") {
            allXcodes.append(app)
            if app.isActive {
                targetApp = app
            }
        }
    }

    if targetApp == nil && !allXcodes.isEmpty {
        var bestXcode: (app: NSRunningApplication, elementCount: Int)?

        for xcode in allXcodes {
            let pid = xcode.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            var tempElements: [DumpedElement] = []
            var tempId = 1
            collectElements(appElement, elements: &tempElements, elementId: &tempId, depth: 0, maxDepth: 3)

            if bestXcode == nil || tempElements.count > bestXcode!.elementCount {
                bestXcode = (xcode, tempElements.count)
            }
        }

        targetApp = bestXcode?.app ?? allXcodes.first
    }

    guard let app = targetApp else {
        return nil
    }

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)

    var passed = 0
    var failed = 0
    var failures: [String] = []

    // Search for test results in various formats
    for element in elements {
        let title = element.title.lowercased()
        let desc = element.description.lowercased()
        let value = element.value?.lowercased() ?? ""

        // Look for "Test Succeeded" or "Test Failed" indicators
        if title.contains("test succeeded") || desc.contains("test succeeded") || value.contains("test succeeded") {
            // Try to extract pass count
            let fullText = "\(element.title) \(element.description) \(element.value ?? "")"
            if let match = fullText.range(of: #"(\d+) passed"#, options: .regularExpression) {
                let numStr = String(fullText[match]).replacingOccurrences(of: " passed", with: "")
                passed = Int(numStr) ?? 0
            }
        }

        if title.contains("test failed") || desc.contains("test failed") || value.contains("test failed") {
            // Extract failure count
            let fullText = "\(element.title) \(element.description) \(element.value ?? "")"
            if let match = fullText.range(of: #"(\d+) failed"#, options: .regularExpression) {
                let numStr = String(fullText[match]).replacingOccurrences(of: " failed", with: "")
                failed = Int(numStr) ?? 0
            }
        }

        // Look for individual test failure elements
        if (element.role == "AXButton" || element.role == "AXStaticText") &&
           (desc.contains("failed") || title.contains("failed") || value.contains("failed")) {
            let failureText = element.value ?? element.title
            if !failureText.isEmpty && !failures.contains(failureText) {
                failures.append(failureText)
            }
        }

        // Also check for test navigator elements showing failures
        if element.role == "AXStaticText" && (value.contains("xctestfailure") || value.contains("assertion failed")) {
            if let val = element.value, !failures.contains(val) {
                failures.append(val)
            }
        }
    }

    // If we found any test-related info, return results
    if passed > 0 || failed > 0 || !failures.isEmpty {
        let total = passed + failed
        return TestResults(
            passed: passed,
            failed: failed,
            total: total,
            failures: failures,
            success: failed == 0 && total > 0
        )
    }

    return nil
}

func readXcodeConsole() -> String? {
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var targetApp: NSRunningApplication?
    var allXcodes: [NSRunningApplication] = []

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleName = app.bundleURL?.lastPathComponent ?? ""

        if localizedName.lowercased() == "xcode" || bundleName.lowercased().hasPrefix("xcode") {
            allXcodes.append(app)
            if app.isActive {
                targetApp = app
            }
        }
    }

    if targetApp == nil && !allXcodes.isEmpty {
        // Try to find the Xcode with actual content (more elements)
        var bestXcode: (app: NSRunningApplication, elementCount: Int)?

        for xcode in allXcodes {
            let pid = xcode.processIdentifier
            let appElement = AXUIElementCreateApplication(pid)
            var tempElements: [DumpedElement] = []
            var tempId = 1
            collectElements(appElement, elements: &tempElements, elementId: &tempId, depth: 0, maxDepth: 3)

            if bestXcode == nil || tempElements.count > bestXcode!.elementCount {
                bestXcode = (xcode, tempElements.count)
            }
        }

        targetApp = bestXcode?.app ?? allXcodes.first
    }

    guard let app = targetApp else {
        print("Error: Xcode is not running")
        return nil
    }

    let bundleName = app.bundleURL?.lastPathComponent ?? "unknown"
    print("Debug: Found Xcode - \(app.localizedName ?? "nil") (\(bundleName)) PID: \(app.processIdentifier)")

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId)

    var consoleElements: [(element: DumpedElement, priority: Int)] = []

    for element in elements {
        if element.role == "AXTextArea" {
            let desc = element.description
            var priority = 0

            if desc == "Console" {
                priority = 10
            } else if desc.lowercased().contains("console") {
                priority = 5
            } else if desc.lowercased().contains("debug") {
                priority = 3
            }

            if priority > 0 {
                if element.value != nil && !element.value!.isEmpty {
                    consoleElements.append((element, priority))
                }
            }
        }
    }

    consoleElements.sort { $0.priority > $1.priority }

    if let best = consoleElements.first {
        return best.element.value
    }

    print("Warning: Could not find console element in Xcode")
    print("Debug: Found \(elements.count) total elements")
    let textAreas = elements.filter { $0.role == "AXTextArea" }
    print("Debug: Found \(textAreas.count) text areas")
    for ta in textAreas.prefix(5) {
        let hasValue = (ta.value != nil && !ta.value!.isEmpty)
        print("  - '\(ta.description)' (has value: \(hasValue))")
    }
    return nil
}

func watchXcodeConsole() {
    print("Watching Xcode console... (Press Ctrl+C to stop)")
    print(String(repeating: "=", count: 80))

    var lastContent = ""

    while true {
        if let content = readXcodeConsole() {
            if content != lastContent {
                if !lastContent.isEmpty {
                    let newLines = content.dropFirst(lastContent.count)
                    if !newLines.isEmpty {
                        print(newLines, terminator: "")
                    }
                } else {
                    print(content, terminator: "")
                }
                lastContent = content
            }
        }
        usleep(1_000_000)
    }
}

func printUsage() {
    print("""
    claude-click - macOS UI Automation Tool

    Usage:
      Mouse & Element Interaction:
        claude-click click <x> <y> [--double] [--right] [--pixels] [--mods <combo>]  Click at coordinates
        claude-click mouse-move <x> <y> [--pixels]   Move cursor (hover) without clicking
        claude-click mouse-down [x y] [--pixels] [--mods <combo>]  Press left button (at coords or current position)
        claude-click mouse-up [x y] [--pixels] [--mods <combo>]    Release left button
        claude-click drag <x1> <y1> <x2> <y2> [--pixels] [--mods <combo>]  Press, drag and release
        claude-click scroll <up|down|left|right> [amount] [--at <x> <y>] [--pixels] [--mods <combo>]  Scroll wheel
        claude-click cursor-position                 Report cursor position in points and pixels
        claude-click indicator <start|stop|status> [--label "text"]  On-screen badge while automating
        claude-click wait-until-stable [timeout] [--threshold t] [--interval ms]  Wait until the screen stops changing
        claude-click record <start|stop|status> [--label name] [--ax]  Record observation/action trajectories
        claude-click find-click <name> [app] [--double]  Find element and click it
        claude-click find-text-ocr <text> <app> [--double]  Find text via OCR and click

      Element State Inspection (NEW):
        claude-click element-exists <name> <app> [--timeout <sec>]  Check if element exists
        claude-click get-value <name> <app>          Read element text/value
        claude-click clear-field <name> <app>        Clear text field contents

      Keyboard & Text Input:
        claude-click type "<text>" [--delay-ms <n>]  Type text (real key codes; default 40ms per key)
        claude-click press-key <key>                 Press special key or single character
        claude-click shortcut <app> <mod> <key>      Execute keyboard shortcut in specific app
        claude-click applescript '<script>'          Execute AppleScript code

      Waiting:
        claude-click wait <seconds>                  Wait for specified time
        claude-click wait-for-app-launch <app> [timeout]  Wait for app to launch

      App Management:
        claude-click focused-app                     Show currently focused application
        claude-click activate-app <app>              Activate running app (SAFE - won't launch duplicates)
        claude-click list-apps [--filter <name>]     List running applications

      Screenshots & Debugging:
        claude-click screenshot [app] <file.jpg|file.png>  Take screenshot (JPEG=fast, PNG=high quality)
        claude-click dump <app|screen> <output>      Dump elements to JSON + annotated PNG
        claude-click focus-click <x> <y>             Click twice to focus a field before typing
        claude-click screen-info                     Show screen size in points and pixels
        claude-click check-permissions               Check accessibility and screen recording permissions

      Xcode Automation:
        claude-click xcode-build-run-app <project> <app> [timeout] [--xcode Ver]  BUILD & RUN (recommended - monitors errors, waits for launch)
        claude-click xcode-run <project> <app> [--xcode Version]  Legacy: Build and run (no error monitoring)
        claude-click xcode-get-build-errors          Check for current Xcode build errors
        claude-click xcode-test-results [--json]     Parse and return test results
        claude-click read-xcode-console              Read Xcode console output once
        claude-click watch-xcode-console             Continuously monitor Xcode console

      Task Learning & Workflow Management:
        claude-click teach-task "name" <app> <step1> <step2> ...  Save a new workflow
        claude-click search-tasks "query" [--json] [--top N]      Search learned workflows by similarity
        claude-click list-tasks [--json]             List all learned tasks with stats
        claude-click forget-task "name"              Delete a learned task
        claude-click record-success "name" [duration]  Mark task execution as successful
        claude-click record-failure "name"           Mark task execution as failed
        claude-click add-note "name" "note"          Add a note to a learned task

    Examples:
      Click and double-click:
        claude-click click 100 200
        claude-click click 100 200 --double
        claude-click click 100 200 --right
        claude-click click 512 742 --pixels          Treat coords as screenshot pixels (Retina-aware)
        claude-click click 100 200 --mods cmd         Cmd-click (also: shift, ctrl, alt, or ctrl+shift)

      Move, drag and scroll:
        claude-click mouse-move 400 300
        claude-click drag 100 200 400 200             Drag from one point to another
        claude-click scroll down 5                    Scroll down 5 wheel clicks
        claude-click scroll up 3 --at 600 400         Scroll up at a specific position
        claude-click cursor-position

      Find and click elements:
        claude-click find-click "Run" "Xcode"
        claude-click find-click "Submit" --double
        claude-click find-text-ocr "Save" "TextEdit"

      Type text and keyboard:
        claude-click type "Hello World"
        claude-click type "slowly typed" --delay-ms 170
        claude-click press-key return
        claude-click press-key end
        claude-click shortcut Safari cmd r          Refresh
        claude-click shortcut Safari cmd shift t    Reopen tab
        claude-click shortcut Notes cmd shift left  Select to start of line
        claude-click shortcut Xcode cmd c           Copy
        claude-click applescript 'tell application "Finder" to get name of every window'

      Wait for things:
        claude-click wait 2
        claude-click wait-for-app-launch "Safari" 15

      App management:
        claude-click focused-app
        claude-click activate-app Safari             Safely activate (won't launch if not running)
        claude-click list-apps
        claude-click list-apps --filter "Xcode"

      Element state inspection (NEW):
        claude-click element-exists "Submit" "Safari"
        claude-click get-value "Username" "MyApp"
        claude-click clear-field "Search" "Safari"

      Screenshots:
        claude-click screenshot test.jpg            Fast JPEG (DEFAULT - use this first)
        claude-click screenshot test.png            High-quality PNG (only if JPEG insufficient)
        claude-click screenshot Safari app.jpg      Fast app window JPEG
        claude-click screenshot Safari app.png      High-quality app window PNG

      Debug elements:
        claude-click dump Safari safari-debug
        claude-click dump screen full-screen-debug
        claude-click check-permissions

      Xcode automation:
        claude-click xcode-build-run-app ~/Desktop/MyProject.xcodeproj MyApp
        claude-click xcode-build-run-app ~/Desktop/Project.xcodeproj App 120 --xcode Xcode3
        claude-click xcode-run ~/Desktop/MyProject.xcodeproj MyApp
        claude-click xcode-run ~/Desktop/Project.xcodeproj App --xcode Xcode3
        claude-click xcode-get-build-errors
        claude-click xcode-test-results              # Human-readable output
        claude-click xcode-test-results --json       # JSON output for parsing
        claude-click read-xcode-console
        claude-click watch-xcode-console

      Task learning and workflows:
        claude-click teach-task "create keynote" Keynote activate-app Keynote find-click "New Document"
        claude-click search-tasks "make presentation" --json
        claude-click list-tasks
        claude-click forget-task "old workflow"
        claude-click record-success "create keynote" 5.2
        claude-click add-note "create keynote" "Works best when Keynote not already running"

    Available Keys:
      return, enter, tab, space, delete, backspace, forward-delete, escape, esc
      command, cmd, shift, capslock, option, alt, control, ctrl
      up, down, left, right, home, end, pageup, pagedown
      f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12
      (press-key and shortcut also accept any single character, e.g. a, 1, /)

    Notes:
      - Screenshots require Screen Recording permission in System Settings
      - Screenshots default to /tmp directory
      - Use .jpg extension for fast screenshots (DEFAULT choice)
      - Use .png only when high quality/precision needed
      - Use find-click (Accessibility API) first, fall back to find-text-ocr if needed
      - Keyboard commands (type, press-key) go to the currently active app - verify focus first
      - shortcut command requires app name and activates it first (prevents system-wide shortcuts)
      - watch-xcode-console monitors console output continuously (Ctrl+C to stop)
      - focused-app uses NSWorkspace API directly (instant, no setup needed)
      - Accessibility permission is required for UI interaction (clicking, typing, etc.)

    AppleScript Automation:
      - applescript command requires both 'claude-click' and 'osascript' in your agent's command allowlist
      - Both tools required: claude-click spawns osascript, macOS checks both for permissions
      - Alternative: run 'osascript -e "script"' directly (only needs osascript in allowlist)
      - Example: claude-click applescript 'tell application "Safari" to get URL of current tab of window 1'

    State Inspection Tips (NEW):
      - element-exists returns exit code 0 if found, 1 if not found (use in shell conditionals)
      - get-value returns the text content or value of an element (perfect for assertions)
      - clear-field uses Cmd+A + Delete to clear text fields before typing
      - list-apps shows all running apps with .regular activation policy
      - Use these for conditional logic: if element-exists "Button" "App"; then ...; fi

    Xcode Tips:
      - RECOMMENDED: Use xcode-build-run-app for testing (monitors errors, waits for launch, activates app)
      - xcode-build-run-app returns immediately on build errors (no timeout wait)
      - Console MUST be visible for read-xcode-console and watch-xcode-console to work
        Open console: View > Debug Area > Activate Console (Cmd+Shift+C)
      - Error detection works best when Issue Navigator is visible (Cmd+5)
      - Test results: xcode-test-results reads from Report Navigator (Cmd+9)
        IMPORTANT: Test results may not always be accessible via Accessibility API
        Alternative: Use 'swift test' from command line for reliable automated testing
        Or read test output from xcode console with read-xcode-console
      - xcode-test-results returns exit code 0 if all tests pass, 1 if any fail
      - Use xcode-test-results --json for programmatic parsing when results are available
      - Run tests with: osascript -e 'tell application "Xcode" to activate' && ~/bin/claude-click shortcut Xcode cmd u
      - xcode-get-build-errors reads from Xcode's UI, so Xcode must be running
      - If build errors aren't detected, ensure Xcode window is not minimized
      - Console text area must have accessibility enabled to be read

    SwiftUI Accessibility:
      - Add .accessibilityLabel() to buttons/elements for reliable find-click detection
      - Example: Button("Submit") { }.accessibilityLabel("Submit Button")
      - Without labels, find-click may fail to locate custom UI elements
      - Standard SwiftUI controls usually work, but custom views need explicit labels
      - Test your UI with find-click during development to ensure discoverability

    Performance Tips:
      - Use wait-for-app-launch after opening apps (instant detection)
      - Use wait-for-element only for NEW UI elements (dialogs, popups)
      - Don't use wait-for-element for browser page loads (too slow - scans 300+ elements)
      - Use sleep 1-2 for browser page loads instead

    App Activation Safety (CRITICAL):
      - NEVER use 'osascript -e \"tell application \\\"X\\\" to activate\"'
      - osascript can launch DUPLICATE instances of apps (causes conflicts)
      - ALWAYS use 'activate-app' command instead (only activates, won't launch)
      - After wait-for-app-launch --activate, app is ALREADY focused
      - No additional activation needed for immediate follow-up commands
      - Commands like app-screenshot, find-click work without extra activation
      - Example CORRECT workflow:
        osascript -e 'tell application "Xcode" to activate' && \\
        ~/bin/claude-click shortcut Xcode cmd r && \\
        ~/bin/claude-click wait-for-app-launch "MyApp" 60 --activate && \\
        ~/bin/claude-click app-screenshot "MyApp" test.png
      - Example WRONG (causes duplicates):
        ... wait-for-app-launch "MyApp" 60 --activate && \\
        osascript -e 'tell application "MyApp" to activate' && \\  # DON'T DO THIS
        ~/bin/claude-click app-screenshot "MyApp" test.png

    Troubleshooting:
      - If find-click fails: Verify app name with focused-app, try exact app name
      - If console reads fail: Ensure console is visible and not collapsed
      - If errors aren't detected: Open Issue Navigator (Cmd+5) and trigger a build
      - If shortcuts don't work: Check that target app is focused with focused-app
      - If app detection fails: Use app-running to verify app name matches
      - If typing in text fields fails with beeps (fresh app launch):
        Use find-click on text field (auto-applies tab fix) OR
        Manual fix: click <x> <y> && wait 0.2 && press-key tab && press-key tab && type "text"
        The tab key establishes the keyboard responder chain for fresh windows
    """)
}

let arguments = CommandLine.arguments

if arguments.count < 2 {
    printUsage()
    exit(1)
}

let command = arguments[1]

// Record activity so a running indicator overlay can reflect that claude-click
// is driving the machine. The indicator subcommands manage the overlay itself.
if command != "indicator" {
    recordActivityHeartbeat()
}

switch command {
case "help", "--help", "-h":
    printUsage()
    exit(0)

case "check-permissions":
    let hasAccessibility = checkAccessibilityPermissions()
    let hasScreenRecording = checkScreenRecordingPermissions()

    if hasAccessibility {
        print("✓ Accessibility permissions are granted")
    } else {
        print("✗ Accessibility permissions NOT granted")
    }

    if hasScreenRecording {
        print("✓ Screen Recording permissions are granted")
    } else {
        print("✗ Screen Recording permissions NOT granted")
    }

    if !hasAccessibility || !hasScreenRecording {
        print("\nPlease grant permissions in:")
        if !hasAccessibility {
            print("  System Settings > Privacy & Security > Accessibility")
            print("  (recent macOS renames this pane to \"Device Control and Data Access\")")
            print("  Open it directly: open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\"")
            print("  Add Terminal (or your terminal app) to the list")
        }
        if !hasScreenRecording {
            print("  System Settings > Privacy & Security > Screen Recording")
            print("  Open it directly: open \"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture\"")
            print("  Add Terminal (or your terminal app) to the list")
        }
        print("\nNote: Screen Recording permission is required for screenshots")
        print("      Accessibility permission is required for UI interaction")
    }

case "click":
    guard arguments.count >= 4,
          let x = Int(arguments[2]),
          let y = Int(arguments[3]) else {
        print("Error: click requires x and y coordinates")
        print("Usage: claude-click click <x> <y> [--double] [--right] [--pixels] [--mods <combo>]")
        exit(1)
    }
    let isDouble = arguments.contains("--double")
    let isRight = arguments.contains("--right")
    let usePixels = arguments.contains("--pixels")

    if isDouble && isRight {
        print("Error: cannot use both --double and --right")
        exit(1)
    }

    var clickModifiers: [String] = []
    if let modsIndex = arguments.firstIndex(of: "--mods"), modsIndex + 1 < arguments.count {
        clickModifiers = [arguments[modsIndex + 1]]
    }
    let clickFlags = parseModifierFlags(clickModifiers)
    let clickPoint = pointCoordinate(x: x, y: y, pixels: usePixels)
    let px = Int(clickPoint.x)
    let py = Int(clickPoint.y)

    recordStep(actionType: "click", details: ["x": px, "y": py, "double": isDouble, "right": isRight, "mods": clickModifiers.first ?? "", "pixels": usePixels])
    if isDouble {
        doubleClickMouse(x: px, y: py, flags: clickFlags)
    } else if isRight {
        rightClickMouse(x: px, y: py, flags: clickFlags)
    } else {
        clickMouse(x: px, y: py, flags: clickFlags)
    }

case "mouse-move":
    guard arguments.count >= 4,
          let x = Int(arguments[2]),
          let y = Int(arguments[3]) else {
        print("Error: mouse-move requires x and y coordinates")
        print("Usage: claude-click mouse-move <x> <y> [--pixels]")
        exit(1)
    }
    let movePoint = pointCoordinate(x: x, y: y, pixels: arguments.contains("--pixels"))
    recordStep(actionType: "mouse-move", details: ["x": Int(movePoint.x), "y": Int(movePoint.y)])
    moveMouse(to: movePoint)

case "mouse-down", "mouse-up":
    // Optional coordinate; without one, acts at the current cursor position.
    let usePixels = arguments.contains("--pixels")
    let modifierTokens = arguments.firstIndex(of: "--mods").flatMap { $0 + 1 < arguments.count ? [arguments[$0 + 1]] : nil } ?? []
    let flags = parseModifierFlags(modifierTokens)
    let point: CGPoint
    if arguments.count >= 4, let x = Int(arguments[2]), let y = Int(arguments[3]) {
        point = pointCoordinate(x: x, y: y, pixels: usePixels)
    } else {
        point = currentCursorPoint()
    }
    recordStep(actionType: command, details: ["x": Int(point.x), "y": Int(point.y)])
    if command == "mouse-down" {
        mouseButtonDown(at: point, flags: flags)
    } else {
        mouseButtonUp(at: point, flags: flags)
    }

case "drag":
    guard arguments.count >= 6,
          let x1 = Int(arguments[2]),
          let y1 = Int(arguments[3]),
          let x2 = Int(arguments[4]),
          let y2 = Int(arguments[5]) else {
        print("Error: drag requires start and end coordinates")
        print("Usage: claude-click drag <x1> <y1> <x2> <y2> [--pixels] [--mods <combo>]")
        exit(1)
    }
    let usePixels = arguments.contains("--pixels")
    let modifierTokens = arguments.firstIndex(of: "--mods").flatMap { $0 + 1 < arguments.count ? [arguments[$0 + 1]] : nil } ?? []
    recordStep(actionType: "drag", details: ["x1": x1, "y1": y1, "x2": x2, "y2": y2, "pixels": usePixels])
    dragMouse(from: pointCoordinate(x: x1, y: y1, pixels: usePixels),
              to: pointCoordinate(x: x2, y: y2, pixels: usePixels),
              flags: parseModifierFlags(modifierTokens))

case "scroll":
    guard arguments.count >= 3 else {
        print("Error: scroll requires a direction")
        print("Usage: claude-click scroll <up|down|left|right> [amount] [--at <x> <y>] [--pixels] [--mods <combo>]")
        exit(1)
    }
    let direction = arguments[2]
    var amount = 3
    if arguments.count >= 4, let parsed = Int(arguments[3]) {
        amount = parsed
    }
    var scrollPoint: CGPoint? = nil
    if let atIndex = arguments.firstIndex(of: "--at"),
       atIndex + 2 < arguments.count,
       let ax = Int(arguments[atIndex + 1]),
       let ay = Int(arguments[atIndex + 2]) {
        scrollPoint = pointCoordinate(x: ax, y: ay, pixels: arguments.contains("--pixels"))
    }
    let modifierTokens = arguments.firstIndex(of: "--mods").flatMap { $0 + 1 < arguments.count ? [arguments[$0 + 1]] : nil } ?? []
    recordStep(actionType: "scroll", details: ["direction": direction, "amount": amount])
    scrollWheel(direction: direction, amount: amount, at: scrollPoint, flags: parseModifierFlags(modifierTokens))

case "cursor-position":
    let point = currentCursorPoint()
    let scale = Double(mainDisplayScaleFactor())
    print("Cursor position (points): \(Int(point.x)), \(Int(point.y))")
    print("Cursor position (pixels): \(Int(point.x * scale)), \(Int(point.y * scale))")

case "indicator":
    let sub = arguments.count >= 3 ? arguments[2] : "status"
    var indicatorLabel = "claude-click active"
    if let labelIndex = arguments.firstIndex(of: "--label"), labelIndex + 1 < arguments.count {
        indicatorLabel = arguments[labelIndex + 1]
    }

    switch sub {
    case "start":
        if indicatorIsRunning() {
            print("Indicator already running")
            break
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        helper.arguments = ["indicator", "_run", "--label", indicatorLabel]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            try? "\(helper.processIdentifier)".write(toFile: indicatorPidPath, atomically: true, encoding: .utf8)
            print("Indicator started (pid \(helper.processIdentifier))")
        } catch {
            print("Error: could not start indicator: \(error)")
        }
    case "stop":
        if let pidText = try? String(contentsOfFile: indicatorPidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidText) {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: indicatorPidPath)
        try? FileManager.default.removeItem(atPath: indicatorSuppressPath)
        print("Indicator stopped")
    case "status":
        print(indicatorIsRunning() ? "Indicator running" : "Indicator not running")
    case "_run":
        // Internal: the detached helper process that hosts the overlay window.
        runIndicator(labelText: indicatorLabel)
    default:
        print("Usage: claude-click indicator <start|stop|status> [--label \"text\"]")
    }

case "wait-until-stable":
    var stableTimeout = 5.0
    var stableThreshold = 0.004
    var stableInterval = 0.15
    if arguments.count >= 3, let parsed = Double(arguments[2]) {
        stableTimeout = parsed
    }
    if let i = arguments.firstIndex(of: "--threshold"), i + 1 < arguments.count, let value = Double(arguments[i + 1]) {
        stableThreshold = value
    }
    if let i = arguments.firstIndex(of: "--interval"), i + 1 < arguments.count, let value = Double(arguments[i + 1]) {
        stableInterval = value / 1000.0
    }
    let settled = waitUntilScreenStable(timeout: stableTimeout, interval: stableInterval, threshold: stableThreshold)
    if settled {
        print("Screen stable")
    } else {
        print("Timed out after \(stableTimeout)s waiting for screen to settle")
        exit(1)
    }

case "record":
    let sub = arguments.count >= 3 ? arguments[2] : "status"
    switch sub {
    case "start":
        if loadRecordingState() != nil {
            print("Already recording. Run 'record stop' first.")
            break
        }
        var label = "recording"
        if let i = arguments.firstIndex(of: "--label"), i + 1 < arguments.count { label = arguments[i + 1] }
        let captureAX = arguments.contains("--ax")
        var dir = ""
        if let i = arguments.firstIndex(of: "--dir"), i + 1 < arguments.count { dir = arguments[i + 1] }
        if dir.isEmpty {
            dir = NSString(string: "~/.claude-click/recordings/\(fileTimestamp())").expandingTildeInPath
        }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            print("Error: could not create recording directory: \(error)")
            exit(1)
        }
        saveRecordingState(RecordingState(dir: dir, step: 0, label: label, ax: captureAX, startedAt: isoTimestamp()))
        print("Recording started\(captureAX ? " (with AX trees)" : ""): \(dir)")
        print("Each claude-click action now logs an observation and action to episode.jsonl. Run 'record stop' when done.")
    case "stop":
        if let state = loadRecordingState() {
            let session: [String: Any] = [
                "label": state.label,
                "startedAt": state.startedAt,
                "endedAt": isoTimestamp(),
                "steps": state.step,
                "dir": state.dir,
                "ax": state.ax,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: session, options: [.prettyPrinted]) {
                try? data.write(to: URL(fileURLWithPath: state.dir + "/session.json"))
            }
            try? FileManager.default.removeItem(atPath: recordingStatePath)
            print("Recording stopped: \(state.step) steps -> \(state.dir)")
        } else {
            print("Not recording")
        }
    case "status":
        if let state = loadRecordingState() {
            print("Recording: \(state.step) steps so far -> \(state.dir)")
        } else {
            print("Not recording")
        }
    default:
        print("Usage: claude-click record <start|stop|status> [--label name] [--dir path] [--ax]")
    }

case "find-click":
    guard arguments.count >= 3 else {
        print("Error: find-click requires an element name")
        print("Usage: claude-click find-click <name> [app] [--double] [--right] [--json] [--offset-x N] [--offset-y N]")
        exit(1)
    }
    let elementName = arguments[2]
    var appName: String? = nil
    var isDouble = false
    var isRight = false
    var jsonOutput = false
    var offsetX: Int = 0
    var offsetY: Int = 0

    var i = 3
    while i < arguments.count {
        if arguments[i] == "--double" {
            isDouble = true
            i += 1
        } else if arguments[i] == "--right" {
            isRight = true
            i += 1
        } else if arguments[i] == "--json" {
            jsonOutput = true
            i += 1
        } else if arguments[i] == "--offset-x" && i + 1 < arguments.count {
            offsetX = Int(arguments[i + 1]) ?? 0
            i += 2
        } else if arguments[i] == "--offset-y" && i + 1 < arguments.count {
            offsetY = Int(arguments[i + 1]) ?? 0
            i += 2
        } else if !arguments[i].hasPrefix("--") {
            appName = arguments[i]
            i += 1
        } else {
            i += 1
        }
    }

    if isDouble && isRight {
        print("Error: cannot use both --double and --right")
        exit(1)
    }

    let startTime = Date()
    recordStep(actionType: "find-click", details: ["name": elementName, "app": appName ?? "", "double": isDouble, "right": isRight])
    findAndClick(name: elementName, appName: appName, doubleClick: isDouble, rightClick: isRight, offsetX: offsetX, offsetY: offsetY)
    let duration = Date().timeIntervalSince(startTime)

    if jsonOutput {
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "success": true,
            "element": elementName,
            "app": appName ?? "screen",
            "double_click": isDouble,
            "right_click": isRight,
            "duration_ms": Int(duration * 1000)
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
    }

case "element-exists":
    guard arguments.count >= 4 else {
        print("Error: element-exists requires an element name and app name")
        print("Usage: claude-click element-exists <name> <app> [--timeout <seconds>] [--json]")
        exit(1)
    }
    let elementName = arguments[2]
    let appName = arguments[3]
    var timeout: Double = 0.0
    var jsonOutput = false

    for i in 4..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        } else if arguments[i] == "--timeout" && i + 1 < arguments.count {
            timeout = Double(arguments[i + 1]) ?? 0.0
        }
    }

    let exists = checkElementExists(name: elementName, appName: appName, timeout: timeout)

    if jsonOutput {
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "exists": exists,
            "element": elementName,
            "app": appName
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
    }

    exit(exists ? 0 : 1)

case "get-value":
    guard arguments.count >= 4 else {
        print("Error: get-value requires an element name and app name")
        print("Usage: claude-click get-value <name> <app> [--json]")
        exit(1)
    }
    let elementName = arguments[2]
    let appName = arguments[3]
    var jsonOutput = false

    for i in 4..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        }
    }

    if let value = getElementValue(name: elementName, appName: appName) {
        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "success": true,
                "element": elementName,
                "app": appName,
                "value": value
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print(value)
        }
        exit(0)
    } else {
        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "success": false,
                "element": elementName,
                "app": appName,
                "error": "Element not found"
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        }
        exit(1)
    }

case "clear-field":
    guard arguments.count >= 4 else {
        print("Error: clear-field requires a field name and app name")
        print("Usage: claude-click clear-field <name> <app>")
        exit(1)
    }
    let elementName = arguments[2]
    let appName = arguments[3]

    findAndClick(name: elementName, appName: appName, doubleClick: false)
    usleep(200000)

    let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: true)
    keyDownEvent?.flags = .maskCommand
    keyDownEvent?.post(tap: .cghidEventTap)

    let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0x00, keyDown: false)
    keyUpEvent?.flags = .maskCommand
    keyUpEvent?.post(tap: .cghidEventTap)

    usleep(100000)
    pressKey("delete")

case "click-sequence":
    guard arguments.count >= 4 else {
        print("Error: click-sequence requires at least one element name and an app name")
        print("Usage: claude-click click-sequence <element1> <element2> ... <app>")
        exit(1)
    }

    let appName = arguments[arguments.count - 1]
    let elementNames = Array(arguments[2..<arguments.count - 1])

    guard !elementNames.isEmpty else {
        print("Error: No element names provided")
        exit(1)
    }

    print("Clicking \(elementNames.count) elements in sequence in \(appName)")

    for (index, elementName) in elementNames.enumerated() {
        print("[\(index + 1)/\(elementNames.count)] Clicking: \(elementName)")
        findAndClick(name: elementName, appName: appName, doubleClick: false)
        if index < elementNames.count - 1 {
            usleep(300000)
        }
    }

    print("Sequence complete!")

case "screenshot":
    // Usage: screenshot [app] [filename]
    // Automatically uses quick-screenshot for .jpg/.jpeg, full quality for .png
    var appName: String? = nil
    var filename: String = "screenshot.jpg"

    if arguments.count >= 3 {
        // Check if first arg looks like an app name (not a filename)
        let firstArg = arguments[2]
        if !firstArg.hasSuffix(".png") && !firstArg.hasSuffix(".jpg") && !firstArg.hasSuffix(".jpeg") {
            appName = firstArg
            filename = arguments.count >= 4 ? arguments[3] : "screenshot.jpg"
        } else {
            filename = firstArg
        }
    }

    // Use quick screenshot for JPEG, full quality for PNG
    let isJPEG = filename.lowercased().hasSuffix(".jpg") || filename.lowercased().hasSuffix(".jpeg")

    let suppressingIndicator = beginScreenshotSuppressionIfNeeded()
    if isJPEG {
        takeQuickScreenshot(appName: appName, filename: filename)
    } else {
        if let app = appName {
            takeWindowScreenshot(appName: app, filename: filename)
        } else {
            takeScreenshot(filename: filename)
        }
    }
    endScreenshotSuppression(suppressingIndicator)

case "app-screenshot":
    // Legacy command - now just redirects to screenshot
    guard arguments.count >= 3 else {
        print("Error: app-screenshot requires app name and filename")
        print("Usage: claude-click app-screenshot <app> <filename> [--full-resolution]")
        print("Note: Use 'screenshot <app> file.jpg' instead (same functionality)")
        exit(1)
    }

    var fullResolution = false
    var filteredArgs = arguments.filter { arg in
        if arg == "--full-resolution" {
            fullResolution = true
            return false
        }
        return true
    }

    let appName = filteredArgs[2]
    let filename = filteredArgs.count >= 4 ? filteredArgs[3] : "screenshot.jpg"

    let isJPEG = filename.lowercased().hasSuffix(".jpg") || filename.lowercased().hasSuffix(".jpeg")

    let suppressingIndicator = beginScreenshotSuppressionIfNeeded()
    if isJPEG {
        takeQuickScreenshot(appName: appName, filename: filename)
    } else {
        takeWindowScreenshot(appName: appName, filename: filename, fullResolution: fullResolution)
    }
    endScreenshotSuppression(suppressingIndicator)

case "focus-click":
    guard arguments.count >= 4,
          let x = Int(arguments[2]),
          let y = Int(arguments[3]) else {
        print("Error: focus-click requires x and y coordinates")
        print("Usage: claude-click focus-click <x> <y>")
        exit(1)
    }
    // A single click often only brings the window forward; the caret lands on
    // the second click. Click twice with a pause so typing that follows goes in.
    recordStep(actionType: "focus-click", details: ["x": x, "y": y])
    clickMouse(x: x, y: y)
    usleep(400000)
    clickMouse(x: x, y: y)
    print("Focus-clicked at: x=\(x), y=\(y)")

case "screen-info":
    let mainDisplay = CGMainDisplayID()
    let pixelWidth = CGDisplayPixelsWide(mainDisplay)
    let pixelHeight = CGDisplayPixelsHigh(mainDisplay)
    if let screen = NSScreen.main {
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        print("Screen size (points): \(Int(frame.width)) x \(Int(frame.height))")
        print("Screen size (pixels): \(Int(frame.width * scale)) x \(Int(frame.height * scale))")
        print("Backing scale factor: \(scale)")
        print("Note: screenshots are in pixels. Divide screenshot coordinates by the scale factor to get click coordinates in points.")
    } else {
        print("Screen size (pixels): \(pixelWidth) x \(pixelHeight)")
    }

case "type":
    guard arguments.count >= 3 else {
        print("Error: type requires text to type")
        print("Usage: claude-click type \"<text>\" [--delay-ms <n>]")
        exit(1)
    }
    var typeDelayMs = 40.0
    var textParts: [String] = []
    var argIndex = 2
    while argIndex < arguments.count {
        if arguments[argIndex] == "--delay-ms", argIndex + 1 < arguments.count, let value = Double(arguments[argIndex + 1]) {
            typeDelayMs = value
            argIndex += 2
        } else {
            textParts.append(arguments[argIndex])
            argIndex += 1
        }
    }
    let text = textParts.joined(separator: " ")
    recordStep(actionType: "type", details: ["text": text, "delay_ms": typeDelayMs])
    typeText(text, delayMillis: typeDelayMs)

case "press-key":
    guard arguments.count >= 3 else {
        print("Error: press-key requires a key name")
        print("Usage: claude-click press-key <key>")
        exit(1)
    }
    recordStep(actionType: "press-key", details: ["key": arguments[2]])
    pressKey(arguments[2])

case "shortcut":
    guard arguments.count >= 5 else {
        print("Error: shortcut requires app name, modifiers, and key")
        print("Usage: claude-click shortcut <app> <modifiers> <key>")
        print("Example: claude-click shortcut Xcode cmd r")
        print("Example: claude-click shortcut Safari cmd shift t")
        exit(1)
    }
    let appName = arguments[2]
    // Last argument is the key, everything between app and key is modifiers
    let key = arguments.last!
    let modifiers = Array(arguments[3..<arguments.count-1])
    recordStep(actionType: "shortcut", details: ["app": appName, "mods": modifiers.joined(separator: "+"), "key": key])
    keyboardShortcut(modifiers: modifiers, key: key, appName: appName)

case "applescript":
    guard arguments.count >= 3 else {
        print("Error: applescript requires script source")
        print("Usage: claude-click applescript '<AppleScript code>'")
        print("Example: claude-click applescript 'tell application \"Finder\" to get name of every window'")
        exit(1)
    }
    let scriptSource = arguments[2...].joined(separator: " ")
    let result = runAppleScript(scriptSource)

    if result.success {
        if !result.output.isEmpty {
            print(result.output)
        }
        exit(0)
    } else {
        print("Error: \(result.output)")
        exit(1)
    }

case "wait":
    guard arguments.count >= 3, let seconds = Double(arguments[2]) else {
        print("Error: wait requires number of seconds")
        print("Usage: claude-click wait <seconds>")
        exit(1)
    }
    waitForSeconds(seconds)

case "wait-for-app-launch":
    guard arguments.count >= 3 else {
        print("Error: wait-for-app-launch requires app name")
        print("Usage: claude-click wait-for-app-launch <app> [timeout] [--activate] [--json]")
        exit(1)
    }
    let appName = arguments[2]
    var timeout = 10.0
    var activate = false
    var jsonOutput = false

    for i in 3..<arguments.count {
        if arguments[i] == "--activate" {
            activate = true
        } else if arguments[i] == "--json" {
            jsonOutput = true
        } else if let timeoutValue = Double(arguments[i]) {
            timeout = timeoutValue
        }
    }

    let startTime = Date()
    let launched = waitForAppLaunch(appName: appName, timeout: timeout, activate: activate)
    let duration = Date().timeIntervalSince(startTime)

    if jsonOutput {
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "launched": launched,
            "app": appName,
            "timeout": timeout,
            "time_taken_ms": Int(duration * 1000),
            "activated": activate && launched
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
    }

    exit(launched ? 0 : 1)

case "activate-app":
    guard arguments.count >= 3 else {
        print("Error: activate-app requires app name")
        print("Usage: claude-click activate-app <app> [--json]")
        exit(1)
    }
    let appName = arguments[2]
    var jsonOutput = false

    for i in 3..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        }
    }

    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var foundApp: NSRunningApplication? = nil
    var bestMatch: NSRunningApplication? = nil
    var bestMatchScore = 0

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleIdentifier = app.bundleIdentifier ?? ""

        if localizedName.lowercased().contains(appName.lowercased()) ||
           bundleIdentifier.lowercased().contains(appName.lowercased()) {

            var score = 1

            // Prefer exact matches
            if localizedName.lowercased() == appName.lowercased() {
                score += 10
            }

            // Prefer regular activation policy (main apps, not background services)
            if app.activationPolicy == .regular {
                score += 5
            }

            if score > bestMatchScore {
                bestMatchScore = score
                bestMatch = app
            }
        }
    }

    foundApp = bestMatch

    if let app = foundApp {
        app.activate(options: [.activateIgnoringOtherApps])
        usleep(300000)

        // Try to restore minimized windows using AppleScript
        let appNameEscaped = (app.localizedName ?? appName).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "\(appNameEscaped)"
            activate
            try
                set miniaturized of windows to false
            end try
        end tell
        """

        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)

        usleep(300000)

        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "success": true,
                "app": app.localizedName ?? "",
                "pid": app.processIdentifier
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print("Activated '\(app.localizedName ?? appName)'")
        }
        exit(0)
    } else {
        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "success": false,
                "error": "App not running",
                "search_term": appName
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print("Error: App '\(appName)' is not running")
            print("Cannot activate an app that is not running.")
            print("Use 'open -a \(appName)' to launch it first, or use wait-for-app-launch.")
        }
        exit(1)
    }

case "debug-window":
    guard arguments.count >= 3 else {
        print("Error: debug-window requires app name")
        print("Usage: claude-click debug-window <app>")
        exit(1)
    }
    let appName = arguments[2]
    let hasWindow = hasVisibleWindow(appName: appName, debug: true)
    print("\nResult: hasVisibleWindow = \(hasWindow)")
    exit(hasWindow ? 0 : 1)

case "app-running":
    guard arguments.count >= 3 else {
        print("Error: app-running requires app name")
        print("Usage: claude-click app-running <app> [--json]")
        exit(1)
    }
    let appName = arguments[2]
    var jsonOutput = false

    for i in 3..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        }
    }

    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var foundApp: String? = nil
    var pid: Int32? = nil

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        let bundleIdentifier = app.bundleIdentifier ?? ""

        if localizedName.lowercased().contains(appName.lowercased()) ||
           bundleIdentifier.lowercased().contains(appName.lowercased()) {
            foundApp = localizedName
            pid = app.processIdentifier
            break
        }
    }

    if let app = foundApp {
        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "running": true,
                "app": app,
                "pid": pid ?? 0,
                "search_term": appName
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print("\(appName) is running")
        }
        exit(0)
    } else {
        if jsonOutput {
            let jsonData = try! JSONSerialization.data(withJSONObject: [
                "running": false,
                "search_term": appName
            ], options: .prettyPrinted)
            print(String(data: jsonData, encoding: .utf8)!)
        } else {
            print("\(appName) is not running")
        }
        exit(1)
    }

case "dump-all-attributes":
    guard arguments.count >= 3 else {
        print("Error: dump-all-attributes requires app name and output base name")
        print("Usage: claude-click dump-all-attributes <app> <output-base>")
        print("Example: claude-click dump-all-attributes Reminders reminders-all-attrs")
        print("  Creates: /tmp/reminders-all-attrs.json")
        print("  This will show ALL accessibility attributes including those VoiceOver uses")
        exit(1)
    }
    let appName = arguments[2]
    let outputBaseName = arguments[3]

    dumpAllAttributes(appName: appName, outputBaseName: outputBaseName)

case "wait-for-element":
    guard arguments.count >= 4 else {
        print("Error: wait-for-element requires element name and app name")
        print("Usage: claude-click wait-for-element <element> <app> [timeout] [--json]")
        exit(1)
    }
    let elementName = arguments[2]
    let appName = arguments[3]
    var timeout = 10.0
    var jsonOutput = false

    for i in 4..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        } else if let timeoutValue = Double(arguments[i]) {
            timeout = timeoutValue
        }
    }

    let startTime = Date()
    let found = waitForElement(name: elementName, appName: appName, timeout: timeout)
    let duration = Date().timeIntervalSince(startTime)

    if jsonOutput {
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "found": found,
            "element": elementName,
            "app": appName,
            "timeout": timeout,
            "time_taken_ms": Int(duration * 1000)
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
    }

    exit(found ? 0 : 1)


case "find-text-ocr":
    guard arguments.count >= 4 else {
        print("Error: find-text-ocr requires text and app name")
        print("Usage: claude-click find-text-ocr <text> <app> [--double]")
        exit(1)
    }
    let searchText = arguments[2]
    let appName = arguments[3]
    let isDouble = arguments.contains("--double")

    print("Searching for '\(searchText)' in \(appName) using OCR...")

    if let point = findTextWithOCR(searchText: searchText, appName: appName) {
        let x = Int(point.x)
        let y = Int(point.y)
        print("Found '\(searchText)' at (\(x), \(y))")

        if isDouble {
            print("Double-clicking at: x=\(x), y=\(y)")
            doubleClickMouse(x: x, y: y)
        } else {
            print("Clicking at: x=\(x), y=\(y)")
            clickMouse(x: x, y: y)
        }
    } else {
        print("Text not found: '\(searchText)'")
        exit(1)
    }

case "dump":
    guard arguments.count >= 3 else {
        print("Error: dump requires target and output base name")
        print("Usage: claude-click dump <app|screen> <output-base>")
        print("Example: claude-click dump Safari safari-dump")
        print("  Creates: /tmp/safari-dump.json + /tmp/safari-dump.png")
        print("Example: claude-click dump screen screen-dump")
        print("  Creates: /tmp/screen-dump.json + /tmp/screen-dump.png")
        exit(1)
    }
    let target = arguments[2]
    let outputBaseName = arguments[3]

    if target.lowercased() == "screen" {
        dumpAllScreenElements(outputBaseName: outputBaseName)
    } else {
        dumpElements(appName: target, outputBaseName: outputBaseName)
    }

case "focused-app":
    // Get focused app directly via NSWorkspace (no daemon needed)
    let workspace = NSWorkspace.shared
    if let activeApp = workspace.frontmostApplication {
        let appName = activeApp.localizedName ?? "Unknown"
        print(appName)
    } else {
        print("Error: Could not determine focused app")
        exit(1)
    }

case "list-apps":
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications

    var filterString: String? = nil
    var jsonOutput = false

    for i in 2..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        } else if arguments[i] == "--filter" && i + 1 < arguments.count {
            filterString = arguments[i + 1].lowercased()
        }
    }

    var foundApps: [String] = []
    for app in runningApps {
        guard let appName = app.localizedName, app.activationPolicy == .regular else { continue }

        if let filter = filterString {
            if appName.lowercased().contains(filter) {
                foundApps.append(appName)
            }
        } else {
            foundApps.append(appName)
        }
    }

    if jsonOutput {
        let sortedApps = foundApps.sorted()
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "count": sortedApps.count,
            "apps": sortedApps
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
        exit(sortedApps.isEmpty ? 1 : 0)
    } else {
        if foundApps.isEmpty {
            if let filter = filterString {
                print("No apps found matching '\(filter)'")
            } else {
                print("No running apps found")
            }
            exit(1)
        } else {
            for app in foundApps.sorted() {
                print(app)
            }
        }
    }

case "quick-screenshot":
    var appName: String? = nil
    var filename: String = "quick-screenshot.jpg"

    if arguments.count >= 3 {
        let firstArg = arguments[2]
        if !firstArg.hasSuffix(".jpg") && !firstArg.hasSuffix(".jpeg") && !firstArg.hasSuffix(".png") {
            appName = firstArg
            filename = arguments.count >= 4 ? arguments[3] : "quick-screenshot.jpg"
        } else {
            filename = firstArg
        }
    }

    let suppressingIndicator = beginScreenshotSuppressionIfNeeded()
    takeQuickScreenshot(appName: appName, filename: filename)
    endScreenshotSuppression(suppressingIndicator)

case "xcode-build-run-app":
    guard arguments.count >= 4 else {
        print("Error: xcode-build-run-app requires project path and app name")
        print("Usage: claude-click xcode-build-run-app <project-path> <app-name> [timeout] [--xcode XcodeVersion]")
        print("Example: claude-click xcode-build-run-app ~/Desktop/MyProject.xcodeproj MyApp")
        print("Example: claude-click xcode-build-run-app ~/Desktop/MyProject.xcodeproj MyApp 120")
        print("Example: claude-click xcode-build-run-app ~/Desktop/MyProject.xcodeproj MyApp 60 --xcode Xcode3")
        exit(1)
    }

    let projectPath = arguments[2]
    let appName = arguments[3]
    var xcodeApp = "Xcode"
    var timeout = 60.0

    // Parse optional timeout and --xcode flag
    var i = 4
    while i < arguments.count {
        if arguments[i] == "--xcode" && i + 1 < arguments.count {
            xcodeApp = arguments[i + 1]
            i += 2
        } else if let timeoutValue = Double(arguments[i]) {
            timeout = timeoutValue
            i += 1
        } else {
            i += 1
        }
    }

    print("Opening \(projectPath) in \(xcodeApp)...")

    // Open project in specified Xcode version
    let openProcess = Process()
    openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    openProcess.arguments = ["-a", xcodeApp, projectPath]

    do {
        try openProcess.run()
        openProcess.waitUntilExit()

        if openProcess.terminationStatus != 0 {
            print("Error: Failed to open project in \(xcodeApp)")
            exit(1)
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }

    // Wait for Xcode to launch
    print("Waiting for Xcode to be ready...")
    sleep(3)

    // Activate Xcode
    let workspace = NSWorkspace.shared
    if let xcode = workspace.runningApplications.first(where: {
        ($0.localizedName ?? "").lowercased().contains("xcode")
    }) {
        xcode.activate(options: [.activateIgnoringOtherApps])
        usleep(500000)
    }

    // Click Run button using keyboard shortcut (more reliable)
    print("Starting build (Cmd+R)...")
    let cmdRDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x0F, keyDown: true)
    cmdRDown?.flags = .maskCommand
    cmdRDown?.post(tap: .cghidEventTap)
    usleep(50000)
    let cmdRUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x0F, keyDown: false)
    cmdRUp?.flags = .maskCommand
    cmdRUp?.post(tap: .cghidEventTap)

    // Monitor build and wait for app to launch
    print("Monitoring build for \(appName) (timeout: \(timeout)s)...")
    let result = monitorBuildWithErrors(appName: appName, timeout: timeout, activate: true)

    if result.launched {
        print("✓ Build succeeded and \(appName) is running")
        exit(0)
    } else if !result.errors.isEmpty {
        print("❌ Build failed with \(result.errors.count) error(s)")
        for error in result.errors {
            print("  • \(error)")
        }
        exit(1)
    } else {
        print("⚠ Timeout reached - app did not launch")
        exit(1)
    }

case "xcode-run":
    guard arguments.count >= 4 else {
        print("Error: xcode-run requires project path and app name")
        print("Usage: claude-click xcode-run <project-path> <app-name> [--xcode XcodeVersion]")
        print("Example: claude-click xcode-run ~/Desktop/MyProject.xcodeproj MyApp")
        print("Example: claude-click xcode-run ~/Desktop/MyProject.xcodeproj MyApp --xcode Xcode3")
        exit(1)
    }

    let projectPath = arguments[2]
    let appName = arguments[3]
    var xcodeApp = "Xcode"

    // Check for --xcode flag
    if arguments.count >= 6 && arguments[4] == "--xcode" {
        xcodeApp = arguments[5]
    }

    print("Opening \(projectPath) in \(xcodeApp)...")

    // Open project in specified Xcode version
    let openProcess = Process()
    openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    openProcess.arguments = ["-a", xcodeApp, projectPath]

    do {
        try openProcess.run()
        openProcess.waitUntilExit()

        if openProcess.terminationStatus != 0 {
            print("Error: Failed to open project in \(xcodeApp)")
            exit(1)
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }

    // Wait for Xcode to launch
    print("Waiting for Xcode to be ready...")
    sleep(3) // Give Xcode time to open project

    // Click Run button (try find-click first, fall back to coordinates)
    // Note: All Xcode versions show up as "Xcode" in accessibility
    print("Clicking Run button...")
    let findProcess = Process()
    findProcess.executableURL = URL(fileURLWithPath: "\(NSHomeDirectory())/bin/claude-click")
    findProcess.arguments = ["find-click", "Run", "Xcode"]

    do {
        try findProcess.run()
        findProcess.waitUntilExit()

        if findProcess.terminationStatus != 0 {
            // Fall back to coordinate click (common Run button position)
            print("find-click failed, using coordinate click...")
            let coordProcess = Process()
            coordProcess.executableURL = URL(fileURLWithPath: "\(NSHomeDirectory())/bin/claude-click")
            coordProcess.arguments = ["click", "303", "60"]
            try coordProcess.run()
            coordProcess.waitUntilExit()
        }
    } catch {
        print("Error clicking Run: \(error)")
        exit(1)
    }

    // Wait for app to launch
    print("Waiting for \(appName) to launch...")
    let waitProcess = Process()
    waitProcess.executableURL = URL(fileURLWithPath: "\(NSHomeDirectory())/bin/claude-click")
    waitProcess.arguments = ["wait-for-app-launch", appName, "60"]

    do {
        try waitProcess.run()
        waitProcess.waitUntilExit()

        if waitProcess.terminationStatus == 0 {
            print("✓ Successfully launched \(appName)")
        } else {
            print("⚠ Warning: \(appName) did not launch within timeout")
            print("  Check Xcode for build errors")
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }

case "read-xcode-console":
    if let console = readXcodeConsole() {
        print(console)
    } else {
        exit(1)
    }

case "watch-xcode-console":
    watchXcodeConsole()

case "xcode-get-build-errors":
    var jsonOutput = false
    for i in 2..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        }
    }

    let errors = getBuildErrors()

    if jsonOutput {
        let jsonData = try! JSONSerialization.data(withJSONObject: [
            "success": errors.isEmpty,
            "error_count": errors.count,
            "errors": errors
        ], options: .prettyPrinted)
        print(String(data: jsonData, encoding: .utf8)!)
    } else {
        if errors.isEmpty {
            print("No build errors found")
        } else {
            for error in errors {
                print(error)
            }
        }
    }

    exit(errors.isEmpty ? 0 : 1)

case "xcode-test-results":
    var jsonOutput = false
    for i in 2..<arguments.count {
        if arguments[i] == "--json" {
            jsonOutput = true
        }
    }

    if let results = getXcodeTestResults() {
        if jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let jsonData = try? encoder.encode(results),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            print("Test Results:")
            print("  Passed: \(results.passed)")
            print("  Failed: \(results.failed)")
            print("  Total: \(results.total)")
            if !results.failures.isEmpty {
                print("\nFailures:")
                for failure in results.failures {
                    print("  - \(failure)")
                }
            }
            print("\nStatus: \(results.success ? "SUCCESS" : "FAILED")")
        }
        exit(results.success ? 0 : 1)
    } else {
        if jsonOutput {
            let errorData = try! JSONSerialization.data(withJSONObject: [
                "error": "No test results found",
                "message": "Make sure tests have been run in Xcode and the Test Navigator is visible (Cmd+6)"
            ], options: .prettyPrinted)
            print(String(data: errorData, encoding: .utf8)!)
        } else {
            print("Error: No test results found")
            print("Make sure:")
            print("  1. Xcode is running")
            print("  2. Tests have been run (Cmd+U)")
            print("  3. Test Navigator is visible (Cmd+6)")
        }
        exit(1)
    }

case "debug-scroll-children":
    guard arguments.count >= 3 else {
        print("Error: debug-scroll-children requires app name")
        print("Usage: claude-click debug-scroll-children <app>")
        exit(1)
    }

    let appName = arguments[2]
    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var targetApp: NSRunningApplication?

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased().contains(appName.lowercased()) {
            targetApp = app
            break
        }
    }

    guard let app = targetApp else {
        print("Error: Could not find running app '\(appName)'")
        exit(1)
    }

    let pid = app.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)

    // Find scroll area at x=564, y=104
    func findScrollArea(_ element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 15 { return nil }

        var roleValue: CFTypeRef?
        var posValue: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)

        if let role = roleValue as? String, role == "AXScrollArea",
           let pos = posValue {
            var point = CGPoint.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &point)
            if abs(point.x - 564) < 10 && abs(point.y - 104) < 10 {
                return element
            }
        }

        var childrenValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)

        if let children = childrenValue as? [AXUIElement] {
            for child in children {
                if let found = findScrollArea(child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    guard let scrollArea = findScrollArea(appElement) else {
        print("Scroll area not found at x=564, y=104")
        exit(1)
    }

    print("Found scroll area, inspecting children...")

    var childrenValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(scrollArea, kAXChildrenAttribute as CFString, &childrenValue)

    if result == .success, let children = childrenValue as? [AXUIElement] {
        print("Number of direct children: \(children.count)")

        for (i, child) in children.enumerated() {
            var roleValue: CFTypeRef?
            var titleValue: CFTypeRef?
            var descValue: CFTypeRef?
            var posValue: CFTypeRef?
            var sizeValue: CFTypeRef?

            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
            AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posValue)
            AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeValue)

            let role = roleValue as? String ?? "unknown"
            let title = titleValue as? String ?? ""
            let desc = descValue as? String ?? ""

            var posStr = ""
            if let pos = posValue {
                var point = CGPoint.zero
                AXValueGetValue(pos as! AXValue, .cgPoint, &point)
                posStr = "(\(Int(point.x)), \(Int(point.y)))"
            }

            var sizeStr = ""
            if let size = sizeValue {
                var sz = CGSize.zero
                AXValueGetValue(size as! AXValue, .cgSize, &sz)
                sizeStr = "\(Int(sz.width))x\(Int(sz.height))"
            }

            print("\(i+1). [\(role)] title='\(title)' desc='\(desc)' pos=\(posStr) size=\(sizeStr)")

            // Check grandchildren
            var grandchildrenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &grandchildrenValue)
            if let grandchildren = grandchildrenValue as? [AXUIElement], grandchildren.count > 0 {
                print("   -> Has \(grandchildren.count) grandchildren")

                // Show first few grandchildren
                for (j, gc) in grandchildren.prefix(5).enumerated() {
                    var gcRole: CFTypeRef?
                    var gcTitle: CFTypeRef?
                    var gcDesc: CFTypeRef?
                    AXUIElementCopyAttributeValue(gc, kAXRoleAttribute as CFString, &gcRole)
                    AXUIElementCopyAttributeValue(gc, kAXTitleAttribute as CFString, &gcTitle)
                    AXUIElementCopyAttributeValue(gc, kAXDescriptionAttribute as CFString, &gcDesc)

                    let gcRoleStr = gcRole as? String ?? "unknown"
                    let gcTitleStr = gcTitle as? String ?? ""
                    let gcDescStr = gcDesc as? String ?? ""

                    print("      \(j+1). [\(gcRoleStr)] title='\(gcTitleStr)' desc='\(gcDescStr)'")
                }
                if grandchildren.count > 5 {
                    print("      ... and \(grandchildren.count - 5) more")
                }
            }
        }
    } else {
        print("Failed to get children of scroll area")
    }

case "xcode-open-file":
    guard arguments.count >= 3 else {
        print("Error: xcode-open-file requires a filename")
        print("Usage: claude-click xcode-open-file <filename> [--line <number>]")
        exit(1)
    }

    let filename = arguments[2]
    var lineNumber: Int? = nil

    if arguments.count >= 5 && arguments[3] == "--line" {
        lineNumber = Int(arguments[4])
    }

    print("Opening \(filename) in Xcode...")

    let workspace = NSWorkspace.shared
    let runningApps = workspace.runningApplications
    var xcodeApp: NSRunningApplication?

    for app in runningApps {
        let localizedName = app.localizedName ?? ""
        if localizedName.lowercased().contains("xcode") {
            xcodeApp = app
            break
        }
    }

    guard let xcode = xcodeApp else {
        print("Error: Xcode is not running")
        exit(1)
    }

    xcode.activate(options: [.activateIgnoringOtherApps])
    usleep(500000)

    // Open Quick Open dialog (Cmd+Shift+O)
    let cmdShiftODown = CGEvent(keyboardEventSource: nil, virtualKey: 0x1F, keyDown: true)
    cmdShiftODown?.flags = [.maskCommand, .maskShift]
    cmdShiftODown?.post(tap: .cghidEventTap)

    let cmdShiftOUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x1F, keyDown: false)
    cmdShiftOUp?.flags = [.maskCommand, .maskShift]
    cmdShiftOUp?.post(tap: .cghidEventTap)

    usleep(800000)

    // Use AX API to find and click the search field
    let pid = xcode.processIdentifier
    let appElement = AXUIElementCreateApplication(pid)
    var elements: [DumpedElement] = []
    var elementId = 1
    collectElements(appElement, elements: &elements, elementId: &elementId, depth: 0, maxDepth: 10)

    // Look for the search field in the Quick Open dialog
    for element in elements {
        if element.role == "AXTextField" {
            let centerX = CGFloat(element.x) + CGFloat(element.width) / 2.0
            let centerY = CGFloat(element.y) + CGFloat(element.height) / 2.0
            clickMouse(x: Int(centerX), y: Int(centerY))
            usleep(300000)
            break
        }
    }

    typeText(filename)
    usleep(200000)

    pressKey("return")
    usleep(500000)

    if let line = lineNumber {
        print("Jumping to line \(line)...")

        // Open Jump to Line dialog (Cmd+L)
        let cmdLDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x25, keyDown: true)
        cmdLDown?.flags = .maskCommand
        cmdLDown?.post(tap: .cghidEventTap)

        let cmdLUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x25, keyDown: false)
        cmdLUp?.flags = .maskCommand
        cmdLUp?.post(tap: .cghidEventTap)

        usleep(800000)

        // Find and click the line number field
        var lineElements: [DumpedElement] = []
        var lineElementId = 1
        collectElements(appElement, elements: &lineElements, elementId: &lineElementId, depth: 0, maxDepth: 10)

        for element in lineElements {
            if element.role == "AXTextField" {
                let centerX = CGFloat(element.x) + CGFloat(element.width) / 2.0
                let centerY = CGFloat(element.y) + CGFloat(element.height) / 2.0
                clickMouse(x: Int(centerX), y: Int(centerY))
                usleep(300000)
                break
            }
        }

        typeText(String(line))
        usleep(100000)

        pressKey("return")
        usleep(200000)

        print("Opened \(filename) at line \(line)")
    } else {
        print("Opened \(filename)")
    }

case "teach-task", "search-tasks", "list-tasks", "forget-task", "record-success", "record-failure", "add-note":
    let taskArgs = Array(arguments.dropFirst())
    Task {
        await handleTaskCommand(taskArgs)
        exit(0)
    }
    RunLoop.main.run()

default:
    print("Error: Unknown command '\(command)'")
    printUsage()
    exit(1)
}
