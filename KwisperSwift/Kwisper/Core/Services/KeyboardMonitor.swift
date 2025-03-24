import Cocoa
import Carbon
import ApplicationServices

class KeyboardMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Made these internal instead of private so the callback can access them
    internal var shortcutPressed: Bool = false
    
    private var onPressCallback: (() -> Void)?
    private var onReleaseCallback: (() -> Void)?
    private var onEscapePressedCallback: (() -> Void)?
    
    private var shortcutKeyCode: UInt16 = 0x09
    private var shortcutModifiers: UInt = 0x0A
    private let escapeKeyCode: UInt16 = 0x35
    
    // To prevent key repeat issues
    private var lastKeyPressTime: TimeInterval = 0
    private let debounceInterval: TimeInterval = 1.0 // 1 second, more aggressive debouncing
    
    // Flag to block additional activations while handling an existing one
    internal var isProcessingShortcut: Bool = false
    
    deinit {
        stopMonitoring()
    }
    
    func configure(keyCode: UInt16, modifiers: UInt) {
        print("KeyboardMonitor: Configuring shortcut with keyCode=\(keyCode), modifiers=\(modifiers)")
        
        // Update our local values
        shortcutKeyCode = keyCode
        shortcutModifiers = modifiers
        
        // Save directly to UserDefaults for persistence and immediate effect
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig"),
           var config = try? JSONDecoder().decode(KwisperConfig.self, from: savedData) {
            print("KeyboardMonitor: Retrieved existing config from UserDefaults")
            
            let oldShortcut = config.recordingShortcut
            print("KeyboardMonitor: Old shortcut was keyCode=\(oldShortcut.keyCode), modifiers=\(oldShortcut.modifiers)")
            
            // Update with the new shortcut
            config.recordingShortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
            
            // Save back to UserDefaults
            if let encodedData = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(encodedData, forKey: "KwisperConfig")
                UserDefaults.standard.synchronize()
                print("KeyboardMonitor: Updated config in UserDefaults with new shortcut")
            }
        }
        
        // Show some debug information to help with troubleshooting
        let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        print("KeyboardMonitor: Shortcut display name: \(shortcut.description)")
    }
    
    func loadShortcutFromSettings() {
        print("KeyboardMonitor: Loading shortcut from settings")
        
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig") {
            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(KwisperConfig.self, from: savedData)
                
                let previousKeyCode = self.shortcutKeyCode
                let previousModifiers = self.shortcutModifiers
                
                self.shortcutKeyCode = config.recordingShortcut.keyCode
                self.shortcutModifiers = config.recordingShortcut.modifiers
                
                print("KeyboardMonitor: Loaded shortcut from UserDefaults: keyCode=\(shortcutKeyCode), modifiers=\(shortcutModifiers)")
                print("KeyboardMonitor: Shortcut display: \(config.recordingShortcut.description)")
                
                if previousKeyCode != shortcutKeyCode || previousModifiers != shortcutModifiers {
                    print("KeyboardMonitor: Shortcut changed from \(previousKeyCode)/\(previousModifiers) to \(shortcutKeyCode)/\(shortcutModifiers)")
                }
            } catch {
                print("KeyboardMonitor: Error decoding settings: \(error), falling back to default")
            }
        } else if let configURL = Bundle.main.url(forResource: "config", withExtension: "json"),
                 let data = try? Data(contentsOf: configURL),
                 let config = try? JSONDecoder().decode(KwisperConfig.self, from: data) {
            
            self.shortcutKeyCode = config.recordingShortcut.keyCode
            self.shortcutModifiers = config.recordingShortcut.modifiers
            
            print("KeyboardMonitor: Loaded shortcut from bundle config: keyCode=\(shortcutKeyCode), modifiers=\(shortcutModifiers)")
            print("KeyboardMonitor: Shortcut display: \(config.recordingShortcut.description)")
        } else {
            print("KeyboardMonitor: Could not load shortcut from settings, using defaults")
        }
    }
    
    func startMonitoring(onPress: @escaping () -> Void, onRelease: @escaping () -> Void, onEscapePressed: @escaping () -> Void = {}) {
        onPressCallback = onPress
        onReleaseCallback = onRelease
        onEscapePressedCallback = onEscapePressed
        
        loadShortcutFromSettings()
        
        if !checkAccessibilityPermissions() {
            requestAccessibilityPermissions()
        }
        
        // Make sure we're capturing all relevant events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.keyUp.rawValue) | 
                        (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap, // This ensures we get events before other applications
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            requestAccessibilityPermissions()
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        CFRunLoopRun()
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }
}

// MARK: - C Callback
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    let keyboardMonitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    
    switch type {
    case .flagsChanged:
        // Check if flags are part of our shortcut (only block if already in shortcut mode)
        if keyboardMonitor.shortcutPressed && keyboardMonitor.isProcessingShortcut {
            return nil // Block system from receiving modifier key events during our shortcut
        }
        keyboardMonitor.handleFlagsChanged(event: event)
        
    case .keyDown:
        if keyboardMonitor.isTargetShortcut(event: event) {
            keyboardMonitor.handleShortcutPressed()
            return nil
        } else if keyboardMonitor.isEscapeKey(event: event) {
            keyboardMonitor.handleEscapePressed()
        } else if keyboardMonitor.isOptionSpace(event: event) {
            // Block Option+Space specifically to prevent TextEdit from inserting spaces
            return nil
        }
        
    case .keyUp:
        if keyboardMonitor.isTargetShortcutKeyUp(event: event) {
            keyboardMonitor.handleShortcutReleased()
            return nil
        } else if keyboardMonitor.isOptionSpace(event: event) {
            // Block Option+Space key-up events too
            return nil
        }
        
    default:
        break
    }
    
    return Unmanaged.passRetained(event)
}

// MARK: - Private Methods
private extension KeyboardMonitor {
    func handleFlagsChanged(event: CGEvent) {
    }
    
    func isTargetShortcut(event: CGEvent) -> Bool {
        // Block if we're already processing a shortcut activation
        if isProcessingShortcut {
            return false
        }
        
        // Debounce repeated key events
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastKeyPressTime < debounceInterval {
            // Too soon after last press, likely a key repeat
            return false
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Extract key modifiers
        let hasCommand = event.flags.contains(.maskCommand)
        let hasOption = event.flags.contains(.maskAlternate)
        let hasControl = event.flags.contains(.maskControl)
        let hasShift = event.flags.contains(.maskShift)
        
        // Convert to our internal format
        var currentModifiers: UInt = 0
        if hasShift   { currentModifiers |= 0x01 }
        if hasControl { currentModifiers |= 0x02 }
        if hasOption  { currentModifiers |= 0x04 }
        if hasCommand { currentModifiers |= 0x08 }
        
        // Special case: If we're specifically looking for the B key with Cmd+Opt modifiers,
        // check for a more strict match
        if keyCode == 11 && shortcutKeyCode == 11 && currentModifiers == 12 && shortcutModifiers == 12 {
            return true
        }
        
        // Key code comparison
        let isTargetKey = keyCode == shortcutKeyCode
        
        // Strict modifier comparison - must match exactly
        let isTargetMod = (currentModifiers == shortcutModifiers)
        
        // Alternative matching method for international keyboards - if the key code doesn't match
        // but we're close, try character comparison too
        var useAlternateMatching = false
        if !isTargetKey && isTargetMod {
            // Try to determine if this is a close match (e.g., same key on different layouts)
            if let cgKeyChar = getCharFromKeyCode(keyCode),
               let targetChar = getCharFromKeyCode(shortcutKeyCode) {
                
                // If the characters match, this is likely the same key but on a different layout
                if cgKeyChar.uppercased() == targetChar.uppercased() {
                    useAlternateMatching = true
                }
            }
        }
        
        if isTargetKey && isTargetMod {
            return true
        } else if useAlternateMatching && isTargetMod {
            return true
        } else if isTargetKey && !isTargetMod {
            // No lenient matching - must match exactly
            return false
        }
        
        return false
    }
    
    // Helper method to get character for a key code
    private func getCharFromKeyCode(_ keyCode: UInt16) -> String? {
        // Using a static mapping of common keys
        let keyCodeMap: [UInt16: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x1F: "O", 0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L", 
            0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M"
        ]
        
        return keyCodeMap[keyCode]
    }
    
    func isTargetShortcutKeyUp(event: CGEvent) -> Bool {
        // We need to be in the shortcutPressed or isProcessingShortcut state
        guard shortcutPressed || isProcessingShortcut else { 
            return false 
        }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        
        // Special case for the B key issue with Option+Command modifiers
        // This targets the specific key combination we're having trouble with
        if keyCode == 11 { // B key
            let hasCommand = event.flags.contains(.maskCommand)
            let hasOption = event.flags.contains(.maskAlternate)
            
            // If this was likely the release of our shortcut key
            if hasCommand || hasOption || shortcutKeyCode == 11 || shortcutKeyCode == 9 {
                return true
            }
        }
        
        // Exact key code match
        if keyCode == shortcutKeyCode {
            return true
        }
        
        // Character-based match for international keyboards
        if let cgKeyChar = getCharFromKeyCode(keyCode),
           let targetChar = getCharFromKeyCode(shortcutKeyCode),
           cgKeyChar.uppercased() == targetChar.uppercased() {
            return true
        }
        
        // More lenient key up detection
        // If we're in the shortcut-pressed state and the key up is for a key very close to our shortcut key,
        // it might be the same key on a different layout
        if abs(Int(keyCode) - Int(shortcutKeyCode)) <= 3 {
            return true
        }
        
        return false
    }
    
    func handleShortcutPressed() {
        // Multiple validations to prevent duplicate triggers
        guard !shortcutPressed && !isProcessingShortcut else { 
            return 
        }
        
        // Set flags to block additional activations
        shortcutPressed = true
        isProcessingShortcut = true
        
        // Store the timestamp to prevent rapid re-triggering
        lastKeyPressTime = Date().timeIntervalSince1970
        
        onPressCallback?()
    }
    
    func handleShortcutReleased() {
        guard shortcutPressed else { 
            return 
        }
        
        shortcutPressed = false
        
        onReleaseCallback?()
        
        // Add a delay before allowing another shortcut activation
        // This ensures we don't get duplicate activations from the same press
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval/2) { [weak self] in
            self?.isProcessingShortcut = false
        }
    }
    
    func isEscapeKey(event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        return keyCode == escapeKeyCode
    }
    
    func isOptionSpace(event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let hasOption = event.flags.contains(.maskAlternate)
        
        // Space key is 0x31 (49)
        return keyCode == 0x31 && hasOption
    }
    
    func handleEscapePressed() {
        onEscapePressedCallback?()
    }
}