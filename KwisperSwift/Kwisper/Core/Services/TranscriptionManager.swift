import Foundation
import OpenAI

class TranscriptionManager {
    private static let sharedClient: OpenAI? = {
        var token: String?
        
        if let envAPIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envAPIKey.isEmpty {
            token = envAPIKey
        } else {
            if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig"),
               let config = try? JSONDecoder().decode(KwisperConfig.self, from: savedData),
               !config.openAIAPIKey.isEmpty {
                
                token = config.openAIAPIKey
            } else {
                if let configURL = Bundle.main.url(forResource: "config", withExtension: "json"),
                   let data = try? Data(contentsOf: configURL),
                   let config = try? JSONDecoder().decode(KwisperConfig.self, from: data),
                   !config.openAIAPIKey.isEmpty {
                    
                    token = config.openAIAPIKey
                } else {
                    return nil
                }
            }
        }
        
        if let token = token {
            let configuration = OpenAI.Configuration(
                token: token,
                organizationIdentifier: nil,
                timeoutInterval: 60.0
            )
            return OpenAI(configuration: configuration)
        }
        
        return nil
    }()
    
    init(apiKey: String? = nil) {
    }
    
    private func loadConfig() -> KwisperConfig? {
        if let savedData = UserDefaults.standard.data(forKey: "KwisperConfig") {
            do {
                let decoder = JSONDecoder()
                let config = try decoder.decode(KwisperConfig.self, from: savedData)
                return config
            } catch {
                print("Error decoding settings from UserDefaults: \(error)")
            }
        }
        
        guard let configURL = Bundle.main.url(forResource: "config", withExtension: "json") else {
            return KwisperConfig.defaultConfig
        }
        
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(KwisperConfig.self, from: data)
            return config
        } catch {
            return KwisperConfig.defaultConfig
        }
    }
    
    func transcribeAudio(at audioFileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let client = TranscriptionManager.sharedClient else {
            completion(.failure(KwisperError.configurationError("OpenAI client not initialized - API key missing")))
            return
        }
        
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            completion(.failure(KwisperError.audioRecordingError("Audio file not found")))
            return
        }
        
        do {
            let audioData = try Data(contentsOf: audioFileURL)
            let fileType: AudioTranscriptionQuery.FileType = .m4a
            let config = loadConfig() ?? KwisperConfig.defaultConfig
            
            let language = config.transcriptionLanguage.isEmpty ? nil : config.transcriptionLanguage
            let prompt = config.transcriptionPrompt.isEmpty ? nil : config.transcriptionPrompt
            
            let query = AudioTranscriptionQuery(
                file: Data(audioData),
                fileType: fileType,
                model: .whisper_1,
                prompt: prompt,
                language: language
            )
            
            client.audioTranscriptions(query: query) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let transcription):
                        print("✅ Transcription successful!")
                        completion(.success(transcription.text))
                            
                    case .failure(let error):
                        print("❌ Transcription failed with error: \(error)")
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            print("Error preparing audio data or creating query: \(error.localizedDescription)")
            completion(.failure(error))
        }
    }
}
