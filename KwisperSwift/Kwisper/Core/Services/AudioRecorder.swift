import Foundation
import AVFoundation
import Cocoa

class AudioRecorder: NSObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioFileURL: URL?
    private let audioSessionLock = NSLock()
    private var maxDurationTimer: Timer?
    private var maxRecordingDuration: Double = 60.0 // Default 60 seconds
    private var recordingStartTime: Date?
    private let minimumRecordingDuration: Double = 0.5 // Minimum 0.5 seconds
    
    override init() {
        super.init()
        // Request microphone permissions on initialization
        requestMicrophonePermission()
        
        // Load max duration from settings
        loadMaxDurationFromSettings()
    }
    
    private func loadMaxDurationFromSettings() {
        // Try to load from UserDefaults
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig") {
            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(KwisperConfig.self, from: savedData)
                self.maxRecordingDuration = config.maxRecordingDurationSeconds
            } catch {
                // Silent error handling
            }
        } else if let configURL = Bundle.main.url(forResource: "config", withExtension: "json"),
                  let data = try? Data(contentsOf: configURL),
                  let config = try? JSONDecoder().decode(KwisperConfig.self, from: data) {
            self.maxRecordingDuration = config.maxRecordingDurationSeconds
        }
    }
    
    func updateMaxRecordingDuration(_ duration: Double) {
        maxRecordingDuration = duration
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.showMicrophonePermissionAlert()
                }
            }
        }
    }
    
    private func showMicrophonePermissionAlert() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
    
    private var isCurrentlyRecording = false
    
    func startRecording() {
        // Prevent multiple recording sessions
        guard !isCurrentlyRecording else {
            print("AudioRecorder: Already recording, ignoring duplicate call")
            return
        }
        
        isCurrentlyRecording = true
        
        checkMicrophonePermission { granted in
            if granted {
                self.setupRecording()
            } else {
                print("AudioRecorder: Microphone access denied")
                self.showMicrophonePermissionAlert()
                self.isCurrentlyRecording = false // Reset state so we can try again
            }
        }
    }
    
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func setupRecording() {
        audioSessionLock.lock()
        defer { audioSessionLock.unlock() }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
        audioFileURL = tempDir.appendingPathComponent(fileName)
        
        guard let fileURL = audioFileURL else { return }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            
            if let recorder = audioRecorder, recorder.prepareToRecord() {
                recorder.record()
                
                maxDurationTimer?.invalidate()
                maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingDuration, repeats: false) { [weak self] _ in
                    DispatchQueue.main.async {
                        _ = self?.stopRecording()
                    }
                }
            } else {
                audioFileURL = nil
            }
        } catch {
            audioFileURL = nil
        }
    }
    
    func stopRecording() -> URL? {
        audioSessionLock.lock()
        defer { 
            // Always reset the recording state when done
            isCurrentlyRecording = false
            audioSessionLock.unlock() 
        }
        
        guard isCurrentlyRecording, let recorder = audioRecorder, recorder.isRecording else {
            print("AudioRecorder: Not currently recording, nothing to stop")
            return nil
        }
        
        print("AudioRecorder: Stopping recording")
        recorder.stop()
        
        let url = audioFileURL
        
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        
        audioRecorder = nil
        
        return url
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            audioFileURL = nil
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        }
        audioFileURL = nil
    }
}
