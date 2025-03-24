import Foundation
import Carbon

// MARK: - Configuration Model
struct KwisperConfig: Codable {
    var openAIAPIKey: String
    var recordingShortcut: KeyboardShortcut
    var maxRecordingDurationSeconds: Double
    var transcriptionLanguage: String
    var transcriptionPrompt: String
    
    static let defaultConfig = KwisperConfig(
        openAIAPIKey: "",
        recordingShortcut: KeyboardShortcut(keyCode: 0, modifiers: 0),
        maxRecordingDurationSeconds: 60.0,
        transcriptionLanguage: "en",
        transcriptionPrompt: ""
    )
}

// MARK: - Keyboard Shortcut Model
struct KeyboardShortcut: Codable {
    var keyCode: UInt16
    var modifiers: UInt
    
    var description: String {
        let modifierStrings = getModifierStrings()
        let keyString = getKeyString()
        
        return modifierStrings.joined(separator: "+") + (modifierStrings.isEmpty ? "" : "+") + keyString
    }
    
    private func getModifierStrings() -> [String] {
        var strings: [String] = []
        
        if modifiers & 0x01 != 0 { strings.append("⇧") }
        if modifiers & 0x02 != 0 { strings.append("⌃") }
        if modifiers & 0x04 != 0 { strings.append("⌥") }
        if modifiers & 0x08 != 0 { strings.append("⌘") }
        
        return strings
    }
    
    private func getKeyString() -> String {
        // Comprehensive key code dictionary that works across layouts
        let keyCodes: [UInt16: String] = [
            // Letters
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X",
            0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
            0x10: "Y", 0x11: "T", 0x1F: "O", 0x20: "U", 0x22: "I", 0x23: "P", 0x25: "L", 
            0x26: "J", 0x28: "K", 0x2D: "N", 0x2E: "M",
            
            // Numbers
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 
            0x1C: "8", 0x19: "9", 0x1D: "0",
            
            // Function Keys
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6",
            0x62: "F7", 0x64: "F8", 0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            
            // Special Characters
            0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\",
            0x2B: ",", 0x2C: "/", 0x2F: ".", 0x32: "`",
            
            // Control Keys
            0x24: "Return", 0x30: "Tab", 0x31: "Space", 0x33: "Delete", 0x35: "Escape",
            0x37: "Command", 0x38: "Shift", 0x39: "CapsLock", 0x3A: "Option", 0x3B: "Control",
            0x3C: "RightShift", 0x3D: "RightOption", 0x3E: "RightControl", 0x3F: "Function",
            
            // Arrow Keys
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
            
            // Keypad
            0x41: "Keypad.", 0x43: "Keypad*", 0x45: "Keypad+", 0x47: "KeypadClear",
            0x4B: "Keypad/", 0x4C: "KeypadEnter", 0x4E: "Keypad-", 0x51: "Keypad=",
            0x52: "Keypad0", 0x53: "Keypad1", 0x54: "Keypad2", 0x55: "Keypad3",
            0x56: "Keypad4", 0x57: "Keypad5", 0x58: "Keypad6", 0x59: "Keypad7",
            0x5B: "Keypad8", 0x5C: "Keypad9"
        ]
        
        // First try to get the character from the system
        if let character = getSystemCharacterForKeyCode() {
            return character.uppercased()
        }
        
        // Fall back to our dictionary
        return keyCodes[keyCode, default: "Key:\(keyCode)"]
    }
    
    private func getSystemCharacterForKeyCode() -> String? {
        // For simplicity and compatibility, we'll use a mapping approach rather than using the 
        // Carbon API directly, which can be tricky
        
        // We'll handle certain common international keyboard layouts by special-casing them
        let currentKeyboardLayout = getCurrentKeyboardLayout()
        print("KeyboardShortcut: Current keyboard layout is \(currentKeyboardLayout)")
        
        // For special handling of common international keyboards
        if currentKeyboardLayout.contains("French") {
            print("KeyboardShortcut: Using French keyboard mapping for key \(keyCode)")
            // Handle French-specific keys (AZERTY layout)
            let frenchKeyMap: [UInt16: String] = [
                0x00: "Q", 0x01: "S", 0x02: "D", 0x0D: "A", 0x0C: "A", // AZERTY layout differences
                0x06: "W", 0x07: "X", 0x09: "V", 0x08: "C", 0x0B: "B"
            ]
            if let mapped = frenchKeyMap[keyCode] {
                return mapped
            }
        } else if currentKeyboardLayout.contains("German") {
            print("KeyboardShortcut: Using German keyboard mapping for key \(keyCode)")
            // Handle German-specific keys (QWERTZ layout)
            let germanKeyMap: [UInt16: String] = [
                0x10: "Z", 0x06: "Y" // German layout swaps Y and Z
            ]
            if let mapped = germanKeyMap[keyCode] {
                return mapped
            }
        } else if currentKeyboardLayout.contains("Spanish") {
            print("KeyboardShortcut: Using Spanish keyboard mapping for key \(keyCode)")
            // Handle Spanish-specific keys if needed
        }
        
        print("KeyboardShortcut: Using default QWERTY mapping for key \(keyCode)")
        // Default to American layout for everything else
        return nil
    }
    
    private func getCurrentKeyboardLayout() -> String {
        // Get the current keyboard layout name
        if let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let localizedName = TISGetInputSourceProperty(inputSource, kTISPropertyLocalizedName) {
            let cfLocalizedName = Unmanaged<CFString>.fromOpaque(localizedName).takeUnretainedValue()
            return cfLocalizedName as String
        }
        return "Unknown"
    }
}

// MARK: - Transcription Model
struct TranscriptionResult: Codable {
    let text: String
}

// MARK: - Error Types
enum KwisperError: Error {
    case audioRecordingError(String)
    case transcriptionError(String)
    case configurationError(String)
    case keyboardMonitoringError(String)
}