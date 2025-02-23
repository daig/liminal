import Foundation
import Speech
import Observation

@Observable
final class VoiceCommandHandler: NSObject, SFSpeechRecognizerDelegate, Codable {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let openAIClient: OpenAIClient
    
    var isRecording = false
    var errorMessage: String?
    var commandResponse: String?
    var isProcessing = false
    var relevantFiles: [String] = []
    var recognizedText: String?
    var partialResult: String = ""
    
    enum CodingKeys: String, CodingKey {
        case isRecording, errorMessage, commandResponse, isProcessing, relevantFiles, recognizedText, partialResult
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRecording = try container.decode(Bool.self, forKey: .isRecording)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        commandResponse = try container.decodeIfPresent(String.self, forKey: .commandResponse)
        isProcessing = try container.decode(Bool.self, forKey: .isProcessing)
        relevantFiles = try container.decode([String].self, forKey: .relevantFiles)
        recognizedText = try container.decodeIfPresent(String.self, forKey: .recognizedText)
        partialResult = try container.decode(String.self, forKey: .partialResult)
        
        openAIClient = OpenAIClient(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
        super.init()
        speechRecognizer.delegate = self
    }
    
    init(openAIClient: OpenAIClient) {
        self.openAIClient = openAIClient
        super.init()
        speechRecognizer.delegate = self
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isRecording, forKey: .isRecording)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(commandResponse, forKey: .commandResponse)
        try container.encode(isProcessing, forKey: .isProcessing)
        try container.encode(relevantFiles, forKey: .relevantFiles)
        try container.encode(recognizedText, forKey: .recognizedText)
        try container.encode(partialResult, forKey: .partialResult)
    }
    
    func startRecording() async throws {
        print("Starting recording...")
        partialResult = ""
        
        // Request authorization
        guard await requestAuthorization() else {
            print("Speech recognition not authorized")
            throw NSError(domain: "VoiceCommandError", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"])
        }
        
        // Cancel any ongoing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create and configure recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        print("Recording started successfully")
        
        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            // Handle cancellation separately from other errors
            if let error = error as NSError?, error.code == 216 {  // Cancellation error code
                print("Recognition cancelled (expected)")
                return
            }
            
            if let error {
                print("Speech recognition error: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                if self.isRecording {
                    self.stopRecording()
                }
                return
            }
            
            if let result {
                let text = result.bestTranscription.formattedString
                self.partialResult = text
                print("Speech recognized: \(text)")
                
                if result.isFinal {
                    print("Final result received")
                    self.recognizedText = text
                    if self.isRecording {
                        self.processCommand(text)
                        self.stopRecording()
                    }
                }
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        print("Stopping recording...")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        print("Recording stopped")
    }
    
    private func requestAuthorization() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }
    
    private func processCommand(_ command: String) {
        Task {
            do {
                isProcessing = true
                commandResponse = nil
                relevantFiles = []
                
                // Get list of files in workspace
                let fileManager = FileManager.default
                let files = try fileManager.contentsOfDirectory(atPath: FileManager.default.currentDirectoryPath)
                    .filter { $0.hasSuffix(".swift") }
                
                // Analyze which files are relevant
                relevantFiles = try await openAIClient.analyzeCommand(command: command, availableFiles: files)
                
                // Read content of relevant files
                var fileContexts: [String: String] = [:]
                for file in relevantFiles {
                    if let content = try? String(contentsOfFile: file, encoding: .utf8) {
                        fileContexts[file] = content
                    }
                }
                
                // Execute command with file contexts
                let result = try await openAIClient.executeCommand(command: command, fileContexts: fileContexts)
                commandResponse = result
                
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
} 
