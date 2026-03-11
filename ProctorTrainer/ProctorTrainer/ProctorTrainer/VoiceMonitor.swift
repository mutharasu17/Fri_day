import Foundation
import Speech

@MainActor
class VoiceMonitor: NSObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    var currentTranscript = "silence"
    
    func startMonitoring() {
        // Commented out to prevent conflict with VoiceManager (Siri-mode)
        // requestAuth()
        // try? startRecording()
    }
    
    func stopMonitoring() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    private func requestAuth() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    private func startRecording() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, _) in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, _ in
            if let result = result {
                self.currentTranscript = result.bestTranscription.formattedString.lowercased()
                self.analyzeVoice(self.currentTranscript)
            }
        }
    }
    
    private func analyzeVoice(_ text: String) {
        let keywords = ["student", "exam", "id", "begin"]
        for word in keywords {
            if text.contains(word) {
                // High-level trigger logic could go here
            }
        }
    }
}
