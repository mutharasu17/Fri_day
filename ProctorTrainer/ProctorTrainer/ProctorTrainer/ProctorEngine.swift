import Foundation
import Combine

@MainActor
class ProctorEngine {
    private let faceDetector = SimpleFaceDetector()
    private let voiceMonitor = VoiceMonitor()
    
    // 🔑 Using Pearl's Gemini API Key
    private let geminiApiKey: String = "YOUR_GEMINI_API_KEY"
    private let geminiEndpoint: String = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    
    // 🤖 OpenAI API Key for ChatGPT integration
    private let chatGPTApiKey: String = "YOUR_OPENAI_API_KEY"
    private let chatGPTEndpoint: String = "https://api.openai.com/v1/chat/completions"
    
    func train() {
        // Training not needed with Vision framework
        print("[ProctorEngine] Vision-based face detection ready")
    }
    
    func start() {
        print("[ProctorEngine] Starting Vision-based Monitoring...")
        print("[ProctorEngine] Face detector: \(faceDetector)")
        print("[ProctorEngine] Voice monitor: \(voiceMonitor)")
        
        // Check camera state first
        guard SharedState.shared.isCameraEnabled else {
            print("[ProctorEngine] Camera not enabled - skipping start")
            return
        }
        
        // Setup face detection callbacks
        faceDetector.onFaceDetected = { [weak self] count in
            Task { @MainActor in
                SharedState.shared.updateFaceCount(count)
                print("[FaceDetector] Detected \(count) face(s)")
            }
        }
        
        faceDetector.onExpressionDetected = { [weak self] expression in
            Task { @MainActor in
                print("[FaceDetector] Expression: \(expression)")
                // Trigger FRIDAY response based on expression
                self?.respondToExpression(expression)
            }
        }
        
        print("[ProctorEngine] Starting face detection...")
        // Start face detection
        faceDetector.startDetection()
        
        // Start voice monitoring (delayed to avoid conflicts)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("[ProctorEngine] Starting voice monitoring...")
            self.voiceMonitor.startMonitoring()
        }
    }
    
    func stop() {
        print("[ProctorEngine] Stopping Vision-based Monitoring...")
        faceDetector.stopDetection()
        voiceMonitor.stopMonitoring()
        print("[ProctorEngine] Camera and monitoring stopped")
    }
    
    private func respondToExpression(_ expression: String) {
        // 🤖 Use both Gemini and ChatGPT for intelligent expression responses
        Task {
            // Try Gemini first (primary AI)
            let geminiResponse = await getGeminiResponse(for: expression)
            print("[FRIDAY] \(geminiResponse)")
            
            // Optionally, also get ChatGPT response for comparison
            let chatGPTResponse = await getChatGPTResponse(for: expression)
            print("[FRIDAY] ChatGPT says: \(chatGPTResponse)")
        }
        
        // Fallback responses for immediate feedback
        switch expression {
        case "smiling":
            print("[FRIDAY] I see you're smiling, Pearl! Everything going well?")
        case "serious":
            print("[FRIDAY] You look serious, Pearl. Need help with something?")
        case "neutral":
            print("[FRIDAY] Looking focused, Pearl. Keep up the good work!")
        default:
            break
        }
    }
    
    // 🔮 Gemini Integration for Expression Analysis
    private func getGeminiResponse(for expression: String) async -> String {
        let prompt = """
        You are FRIDAY, a loyal AI assistant for Pearl. 
        Pearl is showing a '\(expression)' facial expression while working on their FRIDAY AI assistant project.
        Provide an appropriate, supportive response based on this expression.
        Consider that Pearl might be coding, debugging, or working on AI features.
        Keep responses brief (1-2 sentences) and friendly.
        """
        
        let url = URL(string: geminiEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(geminiApiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 50
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let candidates = json?["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("[ProctorEngine] Gemini error: \(error)")
        }
        
        // Fallback responses
        switch expression {
        case "smiling":
            return "I see you're smiling, Pearl! Everything going well?"
        case "serious":
            return "You look serious, Pearl. Need help with something?"
        case "neutral":
            return "Looking focused, Pearl. Keep up the good work!"
        default:
            return "I'm here to help, Pearl!"
        }
    }
    
    // 🤖 ChatGPT Integration for Expression Analysis
    private func getChatGPTResponse(for expression: String) async -> String {
        let systemPrompt = """
        You are FRIDAY, a loyal AI assistant for Pearl. 
        You analyze facial expressions and provide context-aware, supportive responses.
        Keep responses brief (1-2 sentences) and friendly.
        """
        
        let userPrompt = """
        Pearl is showing a '\(expression)' facial expression while working on their FRIDAY AI assistant project.
        Provide an appropriate, supportive response based on this expression.
        Consider that Pearl might be coding, debugging, or working on AI features.
        """
        
        let url = URL(string: chatGPTEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(chatGPTApiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 50,
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let choices = json?["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    return content.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("[ProctorEngine] ChatGPT error: \(error)")
        }
        
        // Fallback responses
        switch expression {
        case "smiling":
            return "I see you're smiling, Pearl! Everything going well?"
        case "serious":
            return "You look serious, Pearl. Need help with something?"
        case "neutral":
            return "Looking focused, Pearl. Keep up the good work!"
        default:
            return "I'm here to help, Pearl!"
        }
    }
}
