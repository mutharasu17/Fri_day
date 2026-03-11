import Foundation
import SwiftUI
import Combine

@MainActor
class FridayViewModel: ObservableObject {
    @Published var currentState: AgentState = .idle
    @Published var micAmplitude: Double = 0.0
    @Published var statusMessage: String = "Say 'Friday' or click to wake."
    @Published var proctorStatus: String = "STATUS: INITIALIZING"
    @Published var messages: [ChatMessage] = []
    
    private static var instanceCount = 0
    private var instanceId = 0
    private var hasWelcomed = false
    
    private let apiService: APIService
    private let voiceManager: VoiceManager
    private let proctorEngine: ProctorEngine
    private var cancellables = Set<AnyCancellable>()
    private var waitingForCommand = false
    
    var startProctoringWhenRequested: (() -> Void)?
    
    private func getTimeBasedWelcome() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        let greetings: [String]
        
        switch hour {
        case 5..<12:
            timeOfDay = "morning"
            greetings = [
                "Good morning, Pearl! The sun is rising and it's time to create something amazing today.",
                "Rise and shine, Pearl! A beautiful morning awaits with new possibilities.",
                "Good morning, Pearl! Coffee in hand and ready to conquer the day?",
                "Morning, Pearl! The world is waking up and so is your potential."
            ]
        case 12..<17:
            timeOfDay = "afternoon"
            greetings = [
                "Good afternoon, Pearl! Perfect time to tackle those challenges head-on.",
                "Afternoon greetings, Pearl! Hope your morning was productive.",
                "Good afternoon, Pearl! The day is young and full of opportunities.",
                "Afternoon, Pearl! Time to make some magic happen before evening."
            ]
        case 17..<21:
            timeOfDay = "evening"
            greetings = [
                "Good evening, Pearl! Time to wrap up the day with excellence.",
                "Evening greetings, Pearl! Hope you accomplished great things today.",
                "Good evening, Pearl! The stars are coming out to celebrate your work.",
                "Evening, Pearl! Time to reflect on today's achievements."
            ]
        default:
            timeOfDay = "night"
            greetings = [
                "Good evening, Pearl! Working late or just getting started with brilliance?",
                "Night owl mode activated, Pearl! The quiet hours are perfect for focus.",
                "Evening, Pearl! The night is young and full of coding possibilities.",
                "Late night greetings, Pearl! Your dedication is truly inspiring."
            ]
        }
        
        let randomGreeting = greetings.randomElement() ?? "Hello, Pearl!"
        return "\(randomGreeting) As your assistant FRIDAY, I'm here to help you make this \(timeOfDay) extraordinary. What can I assist you with?"
    }
    
    private func getLocalWelcome() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12:
            return "Good morning, Pearl! Ready to start an amazing day?"
        case 12..<17:
            return "Good afternoon, Pearl! Hope your day is going well."
        case 17..<21:
            return "Good evening, Pearl! Time to finish strong."
        default:
            return "Good evening, Pearl! Working late tonight?"
        }
    }
    
    init() {
        // Initialize all properties first
        self.messages = StorageService.shared.loadHistory()
        self.currentState = .idle
        self.micAmplitude = 0.0
        self.statusMessage = "Say 'Friday' or click to wake."
        self.proctorStatus = "STATUS: INITIALIZING"
        self.cancellables = Set<AnyCancellable>()
        self.waitingForCommand = false
        
        FridayViewModel.instanceCount += 1
        self.instanceId = FridayViewModel.instanceCount
        print("[ViewModel #\(instanceId)] Initializing...")
        
        // Initialize services
        self.apiService = APIService()
        self.voiceManager = VoiceManager()
        self.proctorEngine = ProctorEngine()
        
        // Now setup services
        setupVoiceHandlers()
        setupProctorObservation()
        
        apiService.onStartTrainingRequested = { [weak self] in
            print("[ViewModel] Starting ProctorEngine due to camera activation...")
            self?.proctorEngine.start()
        }
        
        apiService.onStartProctoringRequested = { [weak self] in
            print("[ViewModel] Proctoring requested - starting ProctorEngine...")
            self?.proctorEngine.start()
        }
        
        // Set voice manager reference for APIService
        apiService.setVoiceManager(voiceManager)
        
        welcomePearl()
    }
    
    private func saveHistory() {
        StorageService.shared.saveHistory(messages)
    }
    
    private func welcomePearl() {
        guard !hasWelcomed else { return }
        hasWelcomed = true
        
        print("[ViewModel #\(instanceId)] Starting Welcome Sequence...")
        self.updateState(.scanning)
        self.statusMessage = "Identifying user..."
        
        // Simulate a face scan delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.updateState(.recognized)
            self.statusMessage = "Face Verified: Pearl"
            
            // Get time-based beautiful welcome message
            let welcomeMessage = self.getTimeBasedWelcome()
            
            Task {
                // Use local welcome immediately
                let localWelcome = self.getLocalWelcome()
                self.messages.append(ChatMessage(text: "Face Recognized: Pearl", isUser: true))
                self.messages.append(ChatMessage(text: localWelcome, isUser: false))
                self.voiceManager.speak(localWelcome)
                self.updateState(.speaking)
            }
            
            // Start everything immediately, don't wait for greeting Task to finish
            // self.proctorEngine.start()  // Disabled to prevent camera model errors
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.voiceManager.resetToWakeMode()
            }
            
            // Add camera control function
            self.startProctoringWhenRequested = { [weak self] in
                self?.proctorEngine.start()
            }
        }
    }
    private func setupProctorObservation() {
        SharedState.shared.$isViolation
            .receive(on: RunLoop.main)
            .sink { [weak self] isViolation in
                if SharedState.shared.isCameraEnabled {
                    if isViolation {
                        self?.updateState(.error)
                        self?.statusMessage = "VIOLATION DETECTED"
                        self?.proctorStatus = "STATUS: VIOLATION (Score: \(String(format: "%.2f", SharedState.shared.lastAnomalyScore)))"
                    } else {
                        self?.proctorStatus = "STATUS: SECURE (Score: \(String(format: "%.2f", SharedState.shared.lastAnomalyScore)))"
                    }
                }
            }
            .store(in: &cancellables)
            
        SharedState.shared.$isCameraEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if !enabled {
                    self?.proctorStatus = "STATUS: PRIVACY MODE (Camera Off)"
                    self?.statusMessage = "Camera disabled at your request."
                    self?.updateState(.idle)
                } else {
                    self?.proctorStatus = "STATUS: SECURE"
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
            guard let self = self else { return }
            
            // Set flag so next time she stops speaking, she listens for command
            self.waitingForCommand = true
            
            self.updateState(.listening)
            self.statusMessage = "Yes, Pearl?"
            self.voiceManager.speak("Yes, Pearl?")
        }
        
        voiceManager.onFinalTranscript = { [weak self] transcript in
            Task {
                await self?.processUserQuery(transcript)
            }
        }
        
        // Security Monitoring: Alert if face count changes to unsafe state
        SharedState.shared.$faceCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                guard let self = self, self.currentState == .idle || self.currentState == .speaking else { return }
                if count > 1 && self.currentState != .error {
                   self.triggerSecurityAlert("Multiple people detected")
                }
            }
            .store(in: &cancellables)
            
        // Link mic amplitude to view
        voiceManager.$amplitude
            .receive(on: RunLoop.main)
            .assign(to: \.micAmplitude, on: self)
            .store(in: &cancellables)
            
        // NEW: Link live transcript to status message so Pearl sees "Translation"
        voiceManager.$transcript
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                if !text.isEmpty && (self.currentState == .listening || self.voiceManager.isWakeMode) {
                    self.statusMessage = text
                } else if self.currentState == .listening || self.voiceManager.isWakeMode {
                    self.statusMessage = "FRIDAY is listening..."
                }
            }
            .store(in: &cancellables)
            
        // Observe speaking state to update UI
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.voiceManager.isSpeaking() {
                    if self.currentState != .speaking {
                        self.updateState(.speaking)
                    }
                } else if self.currentState == .speaking {
                    // Done speaking
                    self.updateState(.idle)
                    
                    if self.waitingForCommand {
                        // Just acknowledged the wake word, now listen for the actual command
                        self.statusMessage = "Listening..."
                        self.voiceManager.startCommandListening()
                        self.waitingForCommand = false 
                    } else {
                        // Just answered a queston, go back to waiting for WAKE WORD
                        self.statusMessage = "Ready."
                        self.voiceManager.resetToWakeMode()
                    }
                }
            }
        }
        
        // Listening will be started after the welcome greeting is finished
        // Auto-start listening for wake word
        Task {
            do {
                try await voiceManager.startListening()
            } catch {
                print("Failed to start listening: \(error)")
            }
        }
    }
    
    private func triggerSecurityAlert(_ reason: String) {
        updateState(.error)
        statusMessage = "SECURITY ALERT: \(reason.uppercased())"
        Task {
            let alertPrompt = "A security violation occurred: \(reason). Alert the user calmly but firmly."
            do {
                let response = try await self.apiService.generateResponse(prompt: alertPrompt)
                self.voiceManager.speak(response)
            } catch {
                self.voiceManager.speak("Security alert. Unrecognized monitoring state.")
            }
        }
    }
    
    func toggleListening() {
        if voiceManager.isListening {
            voiceManager.stopListening()
            updateState(.idle)
        } else {
            Task {
                do {
                    try await voiceManager.startListening()
                    updateState(.listening)
                    statusMessage = "Listening..."
                } catch {
                    updateState(.error)
                    statusMessage = "Microphone error."
                }
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
            print("[CRITICAL] Brain Error Details: \(error.localizedDescription)")
            voiceManager.speak("I'm sorry, I encountered an error connecting to my brain.")
        }
    }
    
    func startSimulatingMic() {
        // No longer needed but kept for protocol compatibility if referenced elsewhere
    }
}
