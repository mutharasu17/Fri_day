import Foundation
import SwiftUI
import Combine

@MainActor
class FridayViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var micAmplitude: Double = 0.0
    @Published var statusMessage: String = "Say 'Friday' or click to wake."
    @Published var proctorStatus: String = "Monitoring Active"
    @Published var messages: [ChatMessage] = []
    @Published var emotionalState: String = "NEUTRAL"
    
    private let voiceManager = VoiceManager()
    private let apiService = APIService()
    private let proctorEngine = ProctorEngine()
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.messages = StorageService.shared.loadHistory()
        setupVoiceHandlers()
        setupProctorObservation()
        setupDatabaseSync()
        welcomePearl()
    }
    
    private func saveHistory() {
        StorageService.shared.saveHistory(messages)
    }
    
    private func welcomePearl() {
        updateState(.scanning)
        statusMessage = "Identifying user..."
        
        // Simulate a face scan delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.updateState(.recognized)
            self.statusMessage = "Face Verified: Pearl"
            
            Task {
                let welcomePrompt = "You just recognized your user, Pearl. Greet her warmly but wittily as her assistant FRIDAY."
                do {
                    let response = try await self.apiService.generateResponse(prompt: welcomePrompt)
                    self.messages.append(ChatMessage(text: "Face Recognized: Pearl", isUser: true))
                    self.messages.append(ChatMessage(text: response, isUser: false))
                    self.voiceManager.speak(response)
                    self.updateState(.speaking)
                    
                    // Start the proctor engine after welcome
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.proctorEngine.start()
                    }
                } catch {
                    self.voiceManager.speak("Welcome back, Pearl.")
                    self.proctorEngine.start()
                }
            }
        }
    }
    
    private func setupProctorObservation() {
        SharedState.shared.$isViolation
            .receive(on: RunLoop.main)
            .sink { [weak self] isViolation in
                if isViolation {
                    self?.updateState(.error)
                    self?.statusMessage = "VIOLATION DETECTED"
                    self?.proctorStatus = "STATUS: VIOLATION (Score: \(String(format: "%.2f", SharedState.shared.lastAnomalyScore)))"
                } else {
                    self?.proctorStatus = "STATUS: SECURE (Score: \(String(format: "%.2f", SharedState.shared.lastAnomalyScore)))"
                }
            }
            .store(in: &cancellables)
    }
    
    func updateState(_ newState: AgentState) {
        DispatchQueue.main.async {
            withAnimation(.spring()) {
                self.currentState = newState
            }
        }
    }
    
    private func setupVoiceHandlers() {
        voiceManager.onWakeWordDetected = { [weak self] in
            self?.updateState(.listening)
            self?.statusMessage = "Yes?"
        }
        
        voiceManager.onFinalTranscript = { [weak self] transcript in
            Task {
                await self?.processUserQuery(transcript)
            }
        }
        
        // Link mic amplitude to view
        voiceManager.$amplitude
            .receive(on: RunLoop.main)
            .assign(to: \.micAmplitude, on: self)
            .store(in: &cancellables)
            
        // Observe speaking state to update UI
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.voiceManager.isSpeaking() {
                    if self.currentState != .speaking {
                        self.updateState(.speaking)
                    }
                } else if self.currentState == .speaking {
                    self.updateState(.idle)
                    self.statusMessage = "Ready."
                }
            }
        }
        
        // Start listening for wake word automatically
        toggleListening()
    }
    
    private func setupDatabaseSync() {
        // Poll the shared SQLite DB for commands from the Python Agent
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                let newSpeeches = DatabaseManager.shared.pollForSpeeches()
                for text in newSpeeches {
                    print("🗣️ Received remote speech request: \(text)")
                    self.messages.append(ChatMessage(text: text, isUser: false))
                    self.voiceManager.speak(text)
                    self.updateState(.speaking)
                    self.saveHistory()
                }
                
                // Poll for Emotional State
                let newState = DatabaseManager.shared.pollEmotionalState()
                if self.emotionalState != newState {
                    self.emotionalState = newState
                    print("🧠 Emotional shift detected: \(newState)")
                }
            }
        }
    }
    
    func toggleListening() {
        if voiceManager.isListening {
            voiceManager.stopListening()
            updateState(.idle)
        } else {
            do {
                try voiceManager.startListening()
                updateState(.listening)
                statusMessage = "Listening..."
            } catch {
                updateState(.error)
                statusMessage = "Microphone error."
            }
        }
    }
    
    @MainActor
    private func processUserQuery(_ query: String) async {
        guard !query.isEmpty else { return }
        
        // Add User's task/message
        messages.append(ChatMessage(text: query, isUser: true))
        saveHistory()
        
        updateState(.processing)
        statusMessage = "Thinking..."
        
        do {
            let response = try await apiService.generateResponse(prompt: query, history: messages)
            statusMessage = response
            
            // Add Friday's response
            messages.append(ChatMessage(text: response, isUser: false))
            saveHistory()
            
            voiceManager.speak(response)
            updateState(.speaking)
        } catch {
            updateState(.error)
            statusMessage = "I encountered an error."
            voiceManager.speak("I'm sorry, I encountered an error connecting to my brain.")
        }
    }
    
    func startSimulatingMic() {
        // No longer needed but kept for protocol compatibility if referenced elsewhere
    }
}
