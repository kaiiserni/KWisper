import SwiftUI
import AppKit

// Class to handle keyboard shortcut recording globally
class ShortcutRecorder: ObservableObject {
    @Published var isRecording: Bool = false
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    
    func startRecording(completion: @escaping (KeyboardShortcut) -> Void) {
        onShortcutRecorded = completion
        isRecording = true
        
        // Use both local and global monitors to catch all key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }
        
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }
    
    func stopRecording() {
        isRecording = false
        
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        guard isRecording else { return }
        
        // Skip Escape as it's often used to cancel operations
        if event.keyCode == 53 { // Escape key code
            stopRecording()
            return
        }
        
        // Print detailed info about the key event - useful for debugging
        print("ShortcutRecorder: Key event detected - keyCode=\(event.keyCode), characters=\(event.characters ?? "nil"), charactersIgnoringModifiers=\(event.charactersIgnoringModifiers ?? "nil")")
        
        // Ensure we have an actual key, not just modifiers
        guard event.keyCode != 0x37 && // Command (left/right)
              event.keyCode != 0x38 && // Shift (left)
              event.keyCode != 0x3C && // Shift (right)
              event.keyCode != 0x3A && // Option (left)
              event.keyCode != 0x3D && // Option (right)
              event.keyCode != 0x3B && // Control (left)
              event.keyCode != 0x3E    // Control (right)
        else { 
            print("ShortcutRecorder: Ignoring modifier-only key event")
            return 
        }
        
        // Extract modifiers
        let hasCommand = event.modifierFlags.contains(.command)
        let hasOption = event.modifierFlags.contains(.option)
        let hasControl = event.modifierFlags.contains(.control)
        let hasShift = event.modifierFlags.contains(.shift)
        
        print("ShortcutRecorder: Modifiers - command=\(hasCommand), option=\(hasOption), control=\(hasControl), shift=\(hasShift)")
        
        // Require at least one modifier key (command, option, or control)
        guard hasCommand || hasOption || hasControl else {
            print("ShortcutRecorder: No modifier key detected, rejecting shortcut")
            
            // Show feedback that a modifier is required
            return
        }
        
        // Convert to our internal format
        var modifiers: UInt = 0
        if hasShift   { modifiers |= 0x01 }
        if hasControl { modifiers |= 0x02 }
        if hasOption  { modifiers |= 0x04 }
        if hasCommand { modifiers |= 0x08 }
        
        print("ShortcutRecorder: Internal modifiers format = \(modifiers)")
        
        // Create and report the shortcut
        let shortcut = KeyboardShortcut(
            keyCode: event.keyCode,
            modifiers: modifiers
        )
        
        print("ShortcutRecorder: Recorded new shortcut: \(shortcut.description)")
        
        onShortcutRecorded?(shortcut)
        stopRecording()
    }
    
    deinit {
        stopRecording()
    }
}

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var isRecordingShortcut: Bool = false
    @State private var shortcutText: String = "Command+Option+V"
    @StateObject private var shortcutRecorder = ShortcutRecorder()
    @State private var maxRecordingDuration: Double = 60
    @State private var transcriptionLanguage: String = "en"
    @State private var transcriptionPrompt: String = ""
    
    private let durationOptions = [30.0, 60.0, 120.0, 300.0]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Text("Kwisper Settings")
                .font(.headline)
                .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                SecureField("Enter your OpenAI API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                
                if ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil {
                    Text("Using API key from environment variable")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Get your API key from openai.com or set OPENAI_API_KEY environment variable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcut")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Button(action: {
                        if !shortcutRecorder.isRecording {
                            isRecordingShortcut = true
                            shortcutRecorder.startRecording { shortcut in
                                DispatchQueue.main.async {
                                    self.shortcutText = shortcut.description
                                    self.isRecordingShortcut = false
                                    
                                    // Directly update KeyboardMonitor
                                    print("SettingsView: Captured new shortcut \(shortcut.description)")
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("KwisperSettingsChanged"),
                                        object: KwisperConfig(
                                            openAIAPIKey: apiKey,
                                            recordingShortcut: shortcut,
                                            maxRecordingDurationSeconds: maxRecordingDuration,
                                            transcriptionLanguage: transcriptionLanguage,
                                            transcriptionPrompt: transcriptionPrompt
                                        )
                                    )
                                    
                                    // Save immediately to update the system
                                    self.saveSettings()
                                }
                            }
                        } else {
                            shortcutRecorder.stopRecording()
                            isRecordingShortcut = false
                        }
                    }) {
                        Text(isRecordingShortcut ? "Press any key combination..." : shortcutText)
                    }
                    .buttonStyle(.bordered)
                    .padding(.vertical, 4)
                    .foregroundColor(isRecordingShortcut ? .blue : .primary)
                    
                    if isRecordingShortcut {
                        Button("Cancel") {
                            shortcutRecorder.stopRecording()
                            isRecordingShortcut = false
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Maximum Recording Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Duration", selection: $maxRecordingDuration) {
                    ForEach(durationOptions, id: \.self) { duration in
                        Text(formatDuration(duration)).tag(duration)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("Language:")
                    Picker("Language", selection: $transcriptionLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                        Text("German").tag("de")
                        Text("Italian").tag("it")
                        Text("Japanese").tag("ja")
                        Text("Auto-detect").tag("")
                    }
                    .frame(maxWidth: 150)
                }
                
                Text("Prompt (optional)")
                    .font(.caption)
                
                TextField("Enter an optional prompt for the transcription", text: $transcriptionPrompt)
                    .textFieldStyle(.roundedBorder)
                
                Text("A prompt can help guide the model to transcribe domain-specific terms correctly")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            }
            .padding()
            .frame(width: 330) // Slightly smaller to account for scroll bar
        }
        .onAppear {
            loadSettings()
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            return "\(Int(seconds / 60))m"
        }
    }
    
    private func loadSettings() {
        // Load settings from UserDefaults or config file
        if let config = loadConfigFromFile() {
            apiKey = config.openAIAPIKey
            shortcutText = config.recordingShortcut.description
            maxRecordingDuration = config.maxRecordingDurationSeconds
            transcriptionLanguage = config.transcriptionLanguage
            transcriptionPrompt = config.transcriptionPrompt
        }
    }
    
    private func saveSettings() {
        // Save settings to UserDefaults or config file
        // This is a simplified implementation
        let config = KwisperConfig(
            openAIAPIKey: apiKey,
            recordingShortcut: parseShortcut(shortcutText),
            maxRecordingDurationSeconds: maxRecordingDuration,
            transcriptionLanguage: transcriptionLanguage,
            transcriptionPrompt: transcriptionPrompt
        )
        
        saveConfigToFile(config)
    }
    
    private func loadConfigFromFile() -> KwisperConfig? {
        // First check UserDefaults
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig") {
            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(KwisperConfig.self, from: savedData)
                print("Loaded settings from UserDefaults")
                return config
            } catch {
                print("Error decoding settings from UserDefaults: \(error)")
            }
        }
        
        // Fall back to the bundled config (first run, or if UserDefaults fails)
        guard let configURL = Bundle.main.url(forResource: "config", withExtension: "json") else {
            print("Could not find config.json in the app bundle")
            return KwisperConfig.defaultConfig
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(KwisperConfig.self, from: data)
            print("Loaded initial settings from bundle config file")
            
            // Save to UserDefaults for future use
            saveConfigToUserDefaults(config)
            
            return config
        } catch {
            print("Error loading config from bundle: \(error)")
            return KwisperConfig.defaultConfig
        }
    }
    
    private func saveConfigToFile(_ config: KwisperConfig) {
        // Save to UserDefaults instead of trying to write to the bundle
        saveConfigToUserDefaults(config)
    }
    
    private func saveConfigToUserDefaults(_ config: KwisperConfig) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(config)
            UserDefaults.standard.set(data, forKey: "KwisperConfig")
            UserDefaults.standard.synchronize()
            
            // Post a notification so other components can update their settings
            NotificationCenter.default.post(name: NSNotification.Name("KwisperSettingsChanged"), object: config)
        } catch {
            // Silent error handling
        }
    }
    
    private func parseShortcut(_ shortcutString: String) -> KeyboardShortcut {
        // If we're already recording a new shortcut, the shortcutText will
        // be updated with a proper KeyboardShortcut.description
        
        // This is a fallback that preserves the default keyboard shortcut
        // if we can't parse the string (which should not happen with our UI)
        let defaultShortcut = KeyboardShortcut(keyCode: 0x09, modifiers: 0x0A) // Command+Option+V
        
        // Try to load the current shortcut from UserDefaults
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig"),
           let config = try? JSONDecoder().decode(KwisperConfig.self, from: savedData) {
            return config.recordingShortcut
        }
        
        return defaultShortcut
    }
}