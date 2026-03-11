import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
class VoiceManager: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
        print("[Voice] Initializing FRIDAY Voice Engine...")
        requestPermissions()
        setupAudioSession()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                print("[Voice] Authorization Status: \(status.rawValue)")
                switch status {
                case .authorized:
                    print("[Voice] ✅ Speech permission GRANTED. Ready to listen.")
                case .denied:
                    print("[Voice] ❌ SPEECH RECOGNITION IS DENIED!")
                    print("[Voice] ❌ Go to Settings → Privacy & Security → Speech Recognition → Enable this app.")
                    // Removed double-speak to avoid overlapping
                case .restricted:
                    print("[Voice] ⚠️ Speech recognition is restricted.")
                case .notDetermined:
                    print("[Voice] ⏳ Speech permission not yet determined.")
                @unknown default:
                    break
                }
            }
            #if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                print("[Voice] Mic Permission: \(granted)")
            }
            #endif
        }
    }
    
    private func setupAudioSession() {
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            #endif
            print("[Voice] Audio session configured ✅")
        } catch {
            print("[Voice] Session Error: \(error)")
        }
    }
    
    func startListening() async throws {
        // 🚨 FIRST: Check if we actually have permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            print("[Voice] ❌ Cannot listen: Speech auth status = \(authStatus.rawValue). Grant permission in Settings.")
            return
        }
        
        // Availability check
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[Voice] Recognizer not available")
            return
        }
        
        // 2. Kill everything first
        stopListening()
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        print("[Voice] Starting Listen...")
        
        // 3. Setup Session
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        
        // 4. Setup Audio Tap
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.recognitionRequest?.append(buffer)
            
            // Fast amplitude update
            let rms = self.calculateRMS(buffer: buffer)
            DispatchQueue.main.async {
                self.amplitude = Double(rms)
                // If she hears anything, change status to show she is active
                if self.amplitude > 0.01 && self.transcript.isEmpty {
                    // Update this to show we are hearing "something"
                }
            }
        }
        
        // 5. Start Engine
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        
        // 6. Start Recognizer
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.transcript = text
                    print("[Heard] \"\(text)\"")
                    
                    let lowerText = text.lowercased()
                    let wakes = ["friday", "hey friday", "fridy", "fryday", "prieday"]
                    let foundWake = wakes.first { lowerText.contains($0) }
                    
                    if self.isWakeMode && foundWake != nil {
                        print("[Wake] Found: \(foundWake!)")
                        self.stopListening()
                        self.isWakeMode = false
                        self.onWakeWordDetected?()
                    } else if !self.isWakeMode {
                        self.resetSilenceTimer()
                    }
                }
                
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.stopListening()
                        self.onFinalTranscript?(text)
                    }
                }
            }
            
            if let error = error {
                let ns = error as NSError
                if ns.code != 203 && ns.code != 1110 {
                    print("[Voice] Error \(ns.code): \(error.localizedDescription)")
                }
                if !self.isWakeMode {
                    DispatchQueue.main.async { self.stopListening() }
                }
            }
        }
        print("[Voice] Ready.")
    }
    
    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        silenceTimer?.invalidate()
    }
    
    func resetToWakeMode() {
        self.isWakeMode = true
        self.transcript = ""
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            try? await self.startListening()
        }
    }
    
    func startCommandListening() {
        self.isWakeMode = false
        self.transcript = ""
        Task {
            try? await self.startListening()
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.isListening && !self.transcript.isEmpty {
                    let text = self.transcript
                    self.stopListening()
                    self.onFinalTranscript?(text)
                }
            }
        }
    }
    
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let data = channelData.pointee
        var sum: Float = 0
        let len = Int(buffer.frameLength)
        for i in 0..<len {
            let s = data[i]
            sum += s * s
        }
        return sqrt(sum / Float(len))
    }
    
    func speak(_ text: String) {
        print("[Voice] Speech: \(text)")
        stopListening()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = 0.52
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
    
    func isSpeaking() -> Bool { return synthesizer.isSpeaking }
}
