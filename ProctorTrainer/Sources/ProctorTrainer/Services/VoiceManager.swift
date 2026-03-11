import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class VoiceManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var isListening = false
    @Published var isWakeMode = true
    @Published var transcript = ""
    @Published var amplitude: Double = 0.0
    
    var onFinalTranscript: ((String) -> Void)?
    var onWakeWordDetected: (() -> Void)?
    
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5
    
    override init() {
        super.init()
        self.speechRecognizer?.delegate = self
        requestPermissions()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    print("Permissions - Speech: \(status), Mic: \(granted)")
                }
            }
        }
    }
    
    func startListening() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
            self.calculateAmplitude(buffer: buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isListening = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            Task { @MainActor in
                if let result = result {
                    let transcript = result.bestTranscription.formattedString.lowercased()
                    self.transcript = result.bestTranscription.formattedString
                    
                    // Wake word logic (supports "Hey Friday", "Friday", "Hey Fridy")
                    let wakeWords = ["hey friday", "friday", "hey fridy", "fridy"]
                    let detectedWake = wakeWords.first { transcript.contains($0) }
                    
                    if self.isWakeMode && detectedWake != nil {
                        self.isWakeMode = false
                        self.onWakeWordDetected?()
                        // Stop reporting transcripts until fresh start
                        return 
                    }
                    
                    if !self.isWakeMode {
                        self.resetSilenceTimer()
                    }
                    
                    if result.isFinal {
                        self.stopListening()
                        self.onFinalTranscript?(result.bestTranscription.formattedString)
                    }
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    self.stopListening()
                }
            }
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListening = false
        silenceTimer?.invalidate()
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { _ in
            Task { @MainActor in
                if self.isListening && !self.transcript.isEmpty {
                    self.stopListening()
                    self.onFinalTranscript?(self.transcript)
                }
            }
        }
    }
    
    private func calculateAmplitude(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelDataValue = channelData.pointee
        let channelDataArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }
        
        let rms = sqrt(channelDataArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        DispatchQueue.main.async {
            self.amplitude = Double(rms)
        }
    }
    
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Focus on British/Irish Female voices
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let preferredVoice = voices.first { $0.name.contains("Serena") || $0.name.contains("Moira") } 
                           ?? AVSpeechSynthesisVoice(language: "en-GB")
        
        utterance.voice = preferredVoice
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
    }
    
    func isSpeaking() -> Bool {
        return synthesizer.isSpeaking
    }
}
