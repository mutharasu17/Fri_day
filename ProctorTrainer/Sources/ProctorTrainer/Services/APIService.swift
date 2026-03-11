import Foundation

@MainActor
class APIService {
    private let apiKey: String = "AIzaSyBZZK64t9TTXtqx2_gYwCrNNkbDbP1DGyY"
    private let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    
    func generateResponse(prompt: String, history: [ChatMessage] = [], imageBase64: String? = nil) async throws -> String {
        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            throw NSError(domain: "Invalid URL", code: 0, userInfo: nil)
        }
        
        let systemPrompt = "You are FRIDAY, a highly efficient, witty, and professional AI executive assistant. You have access to the user's proctoring status. Speak concisely."
        
        // Define "MCP" style Tools/Functions
        let tools: [[String: Any]] = [
            [
                "function_declarations": [
                    [
                        "name": "get_proctor_status",
                        "description": "Returns the current proctoring anomaly score and violation status.",
                        "parameters": ["type": "object", "properties": [:] ]
                    ],
                    [
                        "name": "get_current_time",
                        "description": "Returns the current local time.",
                        "parameters": ["type": "object", "properties": [:] ]
                    ],
                    [
                        "name": "tell_joke",
                        "description": "Tells a random joke to entertain the user.",
                        "parameters": ["type": "object", "properties": [:] ]
                    ],
                    [
                        "name": "toggle_camera",
                        "description": "Turns the webcam on or off.",
                        "parameters": ["type": "object", "properties": [:] ]
                    ],
                    [
                        "name": "control_system",
                        "description": "Controls system volume, brightness, or locks the screen.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "action": ["type": "string", "enum": ["volume_up", "volume_down", "brightness_up", "brightness_down", "lock_screen"]]
                            ]
                        ]
                    ],
                    [
                        "name": "read_screen",
                        "description": "Takes a screenshot and analyzes what's on screen.",
                        "parameters": ["type": "object", "properties": [:] ]
                    ],
                    [
                        "name": "launch_application",
                        "description": "Launches an application on the Mac.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "app_name": ["type": "string", "description": "Name of the application to launch"]
                            ]
                        ]
                    ],
                    [
                        "name": "click_at",
                        "description": "Clicks at the specified screen coordinates.",
                        "parameters": [
                            "type": "object",
                            "properties": [
                                "x": ["type": "number"],
                                "y": ["type": "number"]
                            ],
                            "required": ["x", "y"]
                        ]
                    ]
                ]
            ]
        ]
        
        // Prepare contents with history for RAG context
        var contents: [[String: Any]] = []
        
        // Simple RAG: Include last 5 messages in context
        let recentHistory = history.suffix(5)
        for msg in recentHistory {
            contents.append([
                "role": msg.isUser ? "user" : "model",
                "parts": [["text": msg.text]]
            ])
        }
        
        var userParts: [[String: Any]] = [["text": "\(systemPrompt)\n\nUser: \(prompt)"]]
        if let base64 = imageBase64 {
            userParts.append([
                "inline_data": [
                    "mime_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        contents.append([
            "role": "user",
            "parts": userParts
        ])
        
        let body: [String: Any] = [
            "contents": contents,
            "tools": tools,
            "generationConfig": ["temperature": 0.7]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Handle Function Calling (MCP)
        if let candidates = json?["candidates"] as? [[String: Any]],
           let content = candidates.first?["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let functionCall = parts.first?["functionCall"] as? [String: Any] {
            
            let functionName = functionCall["name"] as? String ?? ""
            let arguments = functionCall["args"] as? [String: Any] ?? [:]
            return try await handleFunctionCall(name: functionName, arguments: arguments, originalPrompt: prompt)
        }
        
        // Standard text response
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        return parts?.first?["text"] as? String ?? "I'm sorry, I couldn't process that."
    }
    
    private func handleFunctionCall(name: String, arguments: [String: Any], originalPrompt: String) async throws -> String {
        switch name {
        case "get_proctor_status":
            let score = SharedState.shared.lastAnomalyScore
            let status = SharedState.shared.isViolation ? "Violation Detected" : "Secure"
            return try await generateResponse(prompt: "Step status: \(status), Score: \(score). Result for user: \(originalPrompt)")
            
        case "get_current_time":
            let time = Date().formatted()
            return try await generateResponse(prompt: "Time is \(time). Proceed: \(originalPrompt)")
            
        case "tell_joke":
            let jokes = [
                "I asked my computer for a joke. It said: 'Your internet connection'. Humor is subjective, I suppose.",
                "Why was the cell phone wearing glasses? It lost its contacts.",
                "Why did the web developer walk out of a restaurant? Because of the table layout.",
                "How many programmers does it take to change a light bulb? None, that's a hardware problem."
            ]
            let joke = jokes.randomElement() ?? "Humor is still downloading."
            return try await generateResponse(prompt: "Joke: \(joke). Finish: \(originalPrompt)")
            
        case "toggle_camera":
            // In a real app we'd toggle AVFoundation, here we update state
            let current = SharedState.shared.cache["camera_enabled"] as? Bool ?? true
            await SharedState.shared.setCameraEnabled(!current)
            return "Camera has been toggled to \(!current ? "ON" : "OFF")."
            
        case "control_system":
            let action = arguments["action"] as? String ?? ""
            var message = "Adjusting system..."
            
            if action == "volume_up" { AppleScriptManager.shared.setVolume(80); message = "Volume increased." }
            else if action == "volume_down" { AppleScriptManager.shared.setVolume(20); message = "Volume decreased." }
            else if action == "brightness_up" { AppleScriptManager.shared.setBrightness(100); message = "Brightness maximized." }
            else if action == "brightness_down" { AppleScriptManager.shared.setBrightness(20); message = "Brightness lowered." }
            else if action == "lock_screen" { AppleScriptManager.shared.lockScreen(); message = "Locking screen." }
            
            return message
            
        case "read_screen":
            if let base64 = await ScreenManager.shared.captureScreenBase64() {
                return try await generateResponse(prompt: "Vision data received. Analyze screen for query: \(originalPrompt)", imageBase64: base64)
            }
            return "Optical sensors are temporarily offline."
            
        case "launch_application":
            let appName = arguments["app_name"] as? String ?? "Safari"
            AppleScriptManager.shared.launchApp(appName)
            return "Launching \(appName) as requested, Boss."
            
        case "click_at":
            let x = arguments["x"] as? Double ?? 0
            let y = arguments["y"] as? Double ?? 0
            AppleScriptManager.shared.clickAt(x: x, y: y)
            return "Clicking at coordinates {\(x), \(y)} now."
            
        default:
            return "I have recognized the command but I'm refining my execution protocols for \(name)."
        }
    }
}
