import Cocoa
import SwiftUI
import AVFoundation
import CoreMedia

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarManagerDelegate {
    // Mutex locks for thread safety
    private static let startRecordingLock = NSLock()
    private static let stopRecordingLock = NSLock()
    
    private var statusBarItem: NSStatusItem!
    private var keyboardMonitor: KeyboardMonitor!
    private var audioRecorder: AudioRecorder!
    private var transcriptionManager: TranscriptionManager!
    private var statusBarManager: StatusBarManager!
    
    private var recordingStartedFromMenuBar = false
    private var isTranscribing = false
    private var activeTranscriptionTask: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyboardMonitor = KeyboardMonitor()
        audioRecorder = AudioRecorder()
        transcriptionManager = TranscriptionManager()
        
        statusBarManager = StatusBarManager()
        statusBarManager.delegate = self
        statusBarManager.setupStatusBar()
        
        setupKeyboardMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: NSNotification.Name("KwisperSettingsChanged"),
            object: nil
        )
    }
    
    @objc private func handleSettingsChanged(_ notification: Notification) {
        if let config = notification.object as? KwisperConfig {
            print("AppDelegate: Received settings update notification")
            
            // Update audio recorder max duration
            audioRecorder.updateMaxRecordingDuration(config.maxRecordingDurationSeconds)
            
            // Update keyboard monitor shortcut
            print("AppDelegate: Configuring new shortcut keyCode=\(config.recordingShortcut.keyCode), modifiers=\(config.recordingShortcut.modifiers)")
            keyboardMonitor.configure(
                keyCode: config.recordingShortcut.keyCode,
                modifiers: config.recordingShortcut.modifiers
            )
            
            // Update TranscriptionManager's language and prompt settings
            // This will happen automatically since it reads from UserDefaults each time
        }
    }

    private func setupKeyboardMonitoring() {
        keyboardMonitor.startMonitoring(
            onPress: { [weak self] in
                guard let self = self else { return }
                self.recordingStartedFromMenuBar = false
                self.startRecording()
            },
            onRelease: { [weak self] in
                self?.stopRecording()
            },
            onEscapePressed: { [weak self] in
                self?.cancelTranscription()
            }
        )
    }
    
    private func cancelTranscription() {
        // Check if we're transcribing or recording
        if isTranscribing {
            print("AppDelegate: Cancelling transcription")
            
            activeTranscriptionTask?.cancel()
            activeTranscriptionTask = nil
            
            isTranscribing = false
            
            statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: false)
            
        } else {
            // If we're not transcribing, we might be recording, so stop that too
            print("AppDelegate: Cancelling recording")
            stopRecording(cancelTranscription: true)
        }
    }
    
    private func startRecording() {
        // Check if we're already transcribing - if so, cancel the transcription
        if isTranscribing {
            print("AppDelegate: Transcription in progress, cancelling it")
            cancelTranscription()
            return
        }
        
        // Use a lock to prevent concurrent startRecording calls
        if !AppDelegate.startRecordingLock.try() {
            print("AppDelegate: startRecording already in progress, ignoring duplicate call")
            return
        }
        
        // Ensure we unlock when done
        defer { AppDelegate.startRecordingLock.unlock() }
        
        print("AppDelegate: Starting recording")
        statusBarManager.updateStatusBarIcon(isRecording: true)
        
        // Start the recording - this is where the audio recorder is initialized
        audioRecorder.startRecording()
        
        
    }
    
    private func stopRecording(cancelTranscription: Bool = false) {
        // Use a lock to prevent concurrent stopRecording calls
        if !AppDelegate.stopRecordingLock.try() {
            print("AppDelegate: stopRecording already in progress, ignoring duplicate call")
            return
        }
        
        // Ensure we unlock when done
        defer { AppDelegate.stopRecordingLock.unlock() }
        
        print("AppDelegate: Stopping recording")
        
        guard let audioFileURL = audioRecorder.stopRecording() else {
            print("AppDelegate: No audio file URL returned, can't transcribe")
            statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: false)
            return
        }
        
        // If we're cancelling, delete the audio file and return without transcribing
        if cancelTranscription {
            print("AppDelegate: Cancelling transcription, deleting audio file")
            try? FileManager.default.removeItem(at: audioFileURL)
            statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: false)
            
            return
        }
        
        do {
            let audioAsset = AVURLAsset(url: audioFileURL)
            // Use synchronous duration loading
            let audioDuration = CMTimeGetSeconds(audioAsset.duration)
            
            if audioDuration < 0.5 {
                statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: false)
                
                
                try? FileManager.default.removeItem(at: audioFileURL)
                return
            }
        } catch {
            print("Could not determine audio duration: \(error)")
        }
        
        isTranscribing = true
        statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: true)
        
        
        let urlToTranscribe = audioFileURL
        
        // Create a weak variable to hold the task
        weak var weakTask: DispatchWorkItem?
        
        // Create the task body closure
        let taskClosure: () -> Void = { [weak self, urlToTranscribe, weak weakTask] in
            // Check if this task was cancelled
            if weakTask?.isCancelled ?? false {
                try? FileManager.default.removeItem(at: urlToTranscribe)
                return
            }
            
            self?.transcriptionManager.transcribeAudio(at: urlToTranscribe) { [weak self, urlToTranscribe] result in
                try? FileManager.default.removeItem(at: urlToTranscribe)
                
                guard let self = self else { return }
                
                self.isTranscribing = false
                self.activeTranscriptionTask = nil
                
                DispatchQueue.main.async {
                    self.statusBarManager.updateStatusBarIcon(isRecording: false, isTranscribing: false)
                }
                    
                switch result {
                    case .success(let transcription):
                        // Always print the transcription result
                        print("Transcription result: \"\(transcription)\"")
                        
                        self.insertTranscribedText(transcription)
                        
                        
                    case .failure(let error):
                        // Print detailed error information
                        print("Transcription failed with error: \(error)")
                        print("Error description: \(error.localizedDescription)")
                        
                    }
                }
        }
        
        // Create the task with the closure
        let transcriptionTask = DispatchWorkItem(block: taskClosure)
        
        // Set the weak reference to point to the task
        weakTask = transcriptionTask
        
        // Store and execute the task
        activeTranscriptionTask = transcriptionTask
        DispatchQueue.global(qos: .userInitiated).async(execute: transcriptionTask)
    }
    
    
    private func insertTranscribedText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousClipboardContent = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        if recordingStartedFromMenuBar {
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if let previousContent = previousClipboardContent {
                    pasteboard.clearContents()
                    pasteboard.setString(previousContent, forType: .string)
                }
            }
        } else {
            let frontmostApp = NSWorkspace.shared.frontmostApplication
            
            NSApp.hide(nil)
            
            if let frontmostApp = frontmostApp {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    frontmostApp.activate(options: .activateIgnoringOtherApps)
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let source = CGEventSource(stateID: .combinedSessionState)
                        
                        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
                        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
                        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
                        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
                        
                        cmdDown?.flags = .maskCommand
                        vDown?.flags = .maskCommand
                        
                        let tapLocation = CGEventTapLocation.cgSessionEventTap
                        
                        cmdDown?.post(tap: tapLocation)
                        vDown?.post(tap: tapLocation)
                        vUp?.post(tap: tapLocation)
                        cmdUp?.post(tap: tapLocation)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if let previousContent = previousClipboardContent {
                                pasteboard.clearContents()
                                pasteboard.setString(previousContent, forType: .string)
                            }
                        }
                    }
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let previousContent = previousClipboardContent {
                        pasteboard.clearContents()
                        pasteboard.setString(previousContent, forType: .string)
                    }
                }
            }
        }
    }
    
    // MARK: - StatusBarManagerDelegate Methods
    
    func statusBarManagerDidRequestStartRecording() {
        recordingStartedFromMenuBar = true
        startRecording()
    }
    
    func statusBarManagerDidRequestStopRecording() {
        if isTranscribing {
            cancelTranscription()
        } else {
            stopRecording()
        }
    }
    
    func statusBarManagerDidRequestTogglePopover() {
        statusBarManager.togglePopover()
    }
    
    func statusBarManagerDidRequestQuit() {
        NSApp.terminate(nil)
    }
}
