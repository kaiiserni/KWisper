import Cocoa

extension AppDelegate {
    // MARK: - Shortcut Recording
    
    func startRecordingShortcut(completion: @escaping (KeyboardShortcut) -> Void) {
        // Create a window to capture keyboard input
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        
        window.title = "Record Shortcut"
        window.center()
        
        // Create the content view
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        
        // Add a label
        let label = NSTextField(labelWithString: "Press a keyboard shortcut...")
        label.frame = NSRect(x: 50, y: 40, width: 200, height: 20)
        label.alignment = .center
        contentView.addSubview(label)
        
        window.contentView = contentView
        
        // Make the window key and order front
        window.makeKeyAndOrderFront(nil)
        
        // Start monitoring keyboard events
        let keyCodeDebugger = KeyCodeDebugger()
        keyCodeDebugger.startShortcutRecording { keyCode, modifiers in
            // Create a keyboard shortcut from the captured input
            let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
            
            // Call the completion handler with the shortcut
            completion(shortcut)
            
            // Close the window
            window.close()
        }
    }
    
    // MARK: - Preferences Management
    
    func loadPreferences() -> KwisperConfig {
        var config: KwisperConfig
        
        // Try to load from UserDefaults
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig") {
            do {
                let decoder = JSONDecoder()
                config = try decoder.decode(KwisperConfig.self, from: savedData)
            } catch {
                print("Error loading preferences from UserDefaults: \(error)")
                
                // Try to load from config file as a backup
                if let configURL = Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "Config") {
                    do {
                        let data = try Data(contentsOf: configURL)
                        let decoder = JSONDecoder()
                        config = try decoder.decode(KwisperConfig.self, from: data)
                    } catch {
                        print("Error loading config file: \(error)")
                        config = KwisperConfig.defaultConfig
                    }
                } else {
                    config = KwisperConfig.defaultConfig
                }
            }
        } else {
            // Try to load from config file as a backup
            if let configURL = Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "Config") {
                do {
                    let data = try Data(contentsOf: configURL)
                    let decoder = JSONDecoder()
                    config = try decoder.decode(KwisperConfig.self, from: data)
                } catch {
                    print("Error loading config file: \(error)")
                    config = KwisperConfig.defaultConfig
                }
            } else {
                config = KwisperConfig.defaultConfig
            }
        }
        
        // If environment variable is set for API key, use it (highest priority)
        if let envAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            config.openAIAPIKey = envAPIKey
            print("Using OpenAI API key from environment variable")
        }
        
        return config
    }
    
    func savePreferences(_ config: KwisperConfig) {
        // Create a copy of the config for saving
        var configToSave = config
        
        // If environment variable is set, don't save the API key to storage
        if ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil {
            // Save an empty string to avoid writing the env API key to disk
            configToSave.openAIAPIKey = ""
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configToSave)
            
            // Save to UserDefaults
            UserDefaults.standard.set(data, forKey: "KwisperConfig")
            
            // Try to save to config file as well
            if let configURL = Bundle.main.url(forResource: "config", withExtension: "json", subdirectory: "Config") {
                try data.write(to: configURL)
            }
        } catch {
            print("Error saving preferences: \(error)")
        }
    }
}