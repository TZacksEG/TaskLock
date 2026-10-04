import AppKit
import ApplicationServices

/// The tap is process-scoped. It never changes HID mappings or persistent system settings.
final class InputGate {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private(set) var active = false
    private(set) var blockedEvents = 0
    private(set) var blockedKeyboardEvents = 0
    private(set) var acceptedClicks = 0
    var pointerAllowed = true
    var allowedRects: [Int: CGRect] = [:]
    private var acceptedMouseDown = false

    func start() -> Bool {
        if active { return true }
        guard AXIsProcessTrusted() else { return false }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let gate = Unmanaged<InputGate>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if gate.active, let tap = gate.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard gate.active else { return Unmanaged.passUnretained(event) }
            // Cursor movement is harmless. Only primary clicking/scrolling reaches the task UI.
            if type == .mouseMoved { return Unmanaged.passUnretained(event) }
            let point = CGPoint(x: event.location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - event.location.y)
            let inside = gate.pointerAllowed && gate.allowedRects.values.contains { $0.contains(point) }
            if type == .leftMouseDown {
                gate.acceptedMouseDown = inside
                if inside { gate.acceptedClicks += 1; return Unmanaged.passUnretained(event) }
            }
            if type == .leftMouseUp {
                let accepted = gate.acceptedMouseDown
                gate.acceptedMouseDown = false
                if accepted { return Unmanaged.passUnretained(event) }
            }
            if (type == .scrollWheel && inside) || (type == .leftMouseDragged && gate.acceptedMouseDown && gate.pointerAllowed) {
                return Unmanaged.passUnretained(event)
            }
            gate.blockedEvents += 1
            if type == .keyDown || type == .keyUp || type == .flagsChanged { gate.blockedKeyboardEvents += 1 }
            return nil
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask.max, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        guard let source else { CFMachPortInvalidate(created); tap = nil; return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        active = true
        blockedEvents = 0
        blockedKeyboardEvents = 0
        acceptedClicks = 0
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    func verify() -> Bool {
        guard active, AXIsProcessTrusted(), let tap, CFMachPortIsValid(tap) else { return false }
        if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        active = false
        acceptedMouseDown = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
    }
    deinit { stop() }
}
