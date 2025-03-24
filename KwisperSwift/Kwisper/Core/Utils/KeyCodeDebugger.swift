import Cocoa
import Carbon
import ApplicationServices

class KeyCodeDebugger {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // Changed to internal (default) access level so it can be accessed from the callback function
    var shortcutCompletionHandler: ((UInt16, UInt) -> Void)?
    
    // Check if the app has the necessary accessibility permissions
    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // Request accessibility permissions
    private func requestAccessibilityPermissions() {
        print("⚠️ Accessibility Permissions Required")
        
        // Get the bundle path for the app
        let appPath = Bundle.main.bundlePath
        
        // Try to prompt silently without showing a dialog
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        if trusted {
            print("✅ App already has accessibility permissions!")
        } else {
            print("❌ App does not have accessibility permissions")
            print("To grant permissions manually, open System Settings > Privacy & Security > Accessibility")
            print("App location: \(appPath)")
            
            // No alert is shown, just logging instructions to console
        }
    }
    
    func startDebugging() {
        print("Starting Key Code Debugger...")
        print("Press any keys to see their key codes and modifiers")
        print("Press Escape to exit debugging mode")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: debugEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Run in the current run loop
        CFRunLoopRun()
    }
    
    func stopDebugging() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        CFRunLoopStop(CFRunLoopGetCurrent())
        print("Key Code Debugger stopped")
    }
    
    func startShortcutRecording(completion: @escaping (UInt16, UInt) -> Void) {
        shortcutCompletionHandler = completion
        
        // Check if we have accessibility permissions
        if !checkAccessibilityPermissions() {
            print("Accessibility permissions are required for shortcut recording")
            requestAccessibilityPermissions()
            return
        }
        
        print("Recording keyboard shortcut...")
        print("Press a key combination to record it as a shortcut")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: shortcutRecordingEventCallback, // Use the global callback function
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap for shortcut recording - Make sure Kwisper has accessibility permissions")
            requestAccessibilityPermissions()
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        // Run in the current run loop
        CFRunLoopRun()
    }
}

// MARK: - C Callbacks
private func debugEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    let debugger = Unmanaged<KeyCodeDebugger>.fromOpaque(userInfo).takeUnretainedValue()
    
    switch type {
    case .keyDown:
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags.rawValue
        
        print("Key Down - Key Code: 0x\(String(format: "%02X", keyCode)) (\(keyCode)), Modifiers: 0x\(String(format: "%02X", modifiers & 0xFF))")
        
        // Check for escape key to exit
        if keyCode == 0x35 {
            debugger.stopDebugging()
        }
        
    case .flagsChanged:
        let modifiers = event.flags.rawValue
        print("Flags Changed - Modifiers: 0x\(String(format: "%02X", modifiers & 0xFF))")
        print("  - Shift: \((modifiers & CGEventFlags.maskShift.rawValue) != 0)")
        print("  - Control: \((modifiers & CGEventFlags.maskControl.rawValue) != 0)")
        print("  - Option: \((modifiers & CGEventFlags.maskAlternate.rawValue) != 0)")
        print("  - Command: \((modifiers & CGEventFlags.maskCommand.rawValue) != 0)")
        
    default:
        break
    }
    
    return Unmanaged.passRetained(event)
}

private func shortcutRecordingEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    let debugger = Unmanaged<KeyCodeDebugger>.fromOpaque(userInfo).takeUnretainedValue()
    
    if type == .keyDown {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = UInt(event.flags.rawValue & 0xFF) // Only consider the modifier bits
        
        print("Recorded shortcut - Key Code: 0x\(String(format: "%02X", keyCode)), Modifiers: 0x\(String(format: "%02X", modifiers))")
        
        // Stop recording and call the completion handler
        debugger.stopDebugging()
        
        // Call the handler with the captured shortcut
        DispatchQueue.main.async {
            debugger.shortcutCompletionHandler?(keyCode, modifiers)
        }
        
        // Consume the event so it doesn't propagate
        return nil
    }
    
    return Unmanaged.passRetained(event)
}