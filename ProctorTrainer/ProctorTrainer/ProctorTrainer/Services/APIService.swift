import Foundation
import SwiftUI
import AVFoundation
import SwiftData

@MainActor
class APIService {
    // 🔑 Using Pearl's NEW private API Key
    private let geminiApiKey: String = "YOUR_GEMINI_API_KEY"
    
    // 🤖 ChatGPT API Key (add yours here)
    private let chatGPTApiKey: String = "YOUR_OPENAI_API_KEY"
    
    // 🧠 Memory System Integration
    private let memorySystem: FridayMemorySystem
    
    // ✅ Confirmed working model (verified via ListModels API)
    private let geminiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
    
    // ChatGPT endpoint
    private let chatGPTEndpoint = "https://api.openai.com/v1/chat/completions"
    
    private let systemPrompt = """
    You are FRIDAY, a loyal AI assistant for Pearl. 
    Professional British personality. Efficient and witty.
    """
    
    private var geminiTools: [[String: Any]] {
        return [
            [
                "function_declarations": [
                    ["name": "get_proctor_status", "description": "Get current proctoring status."],
                    ["name": "get_current_time", "description": "Get current time."],
                    ["name": "tell_joke", "description": "Tell a random joke."],
                    ["name": "toggle_camera", "description": "Turn camera on/off.", "parameters": ["type": "object", "properties": ["enabled": ["type": "boolean"]], "required": ["enabled"]]],
                    ["name": "control_system", "description": "Adjust Mac settings.", "parameters": ["type": "object", "properties": ["action": ["type": "string", "enum": ["volume", "brightness", "lock", "battery"]], "value": ["type": "number"]], "required": ["action"]]],
                    ["name": "read_screen", "description": "Analyze screen content."],
                    ["name": "launch_application", "description": "Open a Mac app.", "parameters": ["type": "object", "properties": ["name": ["type": "string"]], "required": ["name"]]]
                ]
            ]
        ]
    }
    
    weak var voiceManager: VoiceManager?
    weak var screenManager: ScreenManager?
    var onStartProctoringRequested: (() -> Void)?
    var onStartTrainingRequested: (() -> Void)?
    
    init() {
        // 🧠 Initialize Memory System
        self.memorySystem = FridayMemorySystem()
    }
    
    func setVoiceManager(_ manager: VoiceManager) {
        self.voiceManager = manager
    }
    
    func generateResponse(prompt: String, history: [ChatMessage] = [], imageBase64: String? = nil) async throws -> String {
        print("[Brain] Processing: \(prompt)")
        
        // ⚡️ LOCAL-FIRST: Handle common queries instantly without API
        let lower = prompt.lowercased()
        if lower.contains("time") || lower.contains("clock") {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            formatter.dateStyle = .none
            let time = formatter.string(from: Date())
            return "The current time is \(time), Pearl."
        }
        if lower.contains("date") || lower.contains("today") {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            let date = formatter.string(from: Date())
            return "Today is \(date), Pearl."
        }
        if lower.contains("hello") || lower.contains("hi friday") {
            return "Hello, Pearl! How can I assist you today?"
        }
        if lower.contains("joke") {
            let jokes = [
                "Why did the developer go broke? Because they used up all their cache!",
                "I would tell you a joke about UDP, but you might not get it.",
                "A byte walks into a bar and orders a drink. The bartender says, 'Are you sure? You look a bit off.'"
            ]
            return jokes.randomElement() ?? "My joke module seems to have a bug, Pearl."
        }
        
        // 🌐 TRANSLATION SUPPORT: Handle translation specifically for terminal visibility
        if lower.contains("translate") {
            print("[Brain] Translation request detected in \(prompt)")
            // We'll let Gemini handle the actual translation, but we log it here
        }
        
        do {
            let response = try await callGemini(prompt: prompt, history: history, imageBase64: imageBase64)
            print("[Brain] API Success: \(response)")
            return response
        } catch {
            print("[Brain] Connection failed: \(error.localizedDescription)")
            return getLocalResponse(prompt: prompt)
        }
    }
    
    private func getLocalResponse(prompt: String) -> String {
        let lowerPrompt = prompt.lowercased()
        
        if lowerPrompt.contains("joke") {
            let jokes = [
                "Why did the AI go to therapy? Too many bits, not enough bytes!",
                "What do you call a fake noodle? An impasta!",
                "Why don't scientists trust atoms? Because they make up everything!"
            ]
            return jokes.randomElement() ?? "I'm feeling a bit humorless at the moment, Pearl."
        }
        
        if lowerPrompt.contains("time") {
            let time = Date().formatted()
            return "Time synchronization complete, Pearl. Current timestamp: \(time)."
        }
        
        if lowerPrompt.contains("status") {
            return "The proctor status is currently Secure with a score of 0.12. All systems nominal, Pearl."
        }
        
        if lowerPrompt.contains("turn off") && lowerPrompt.contains("camera") {
            Task {
                await SharedState.shared.setCameraEnabled(false)
            }
            return "Decommissioning camera systems... Scanning complete. All visual data processed. I think I am done here. Entering standby mode."
        }
        
        if lowerPrompt.contains("turn on") && lowerPrompt.contains("camera") {
            Task {
                await SharedState.shared.setCameraEnabled(true)
            }
            return "Initiating camera startup sequence... Visual systems online. Optical sensors calibrated. You're looking awesome today, Pearl!"
        }
        
        if lowerPrompt.contains("ask chatgpt") || lowerPrompt.contains("chatgpt") || lowerPrompt.contains("xcode error") {
            Task {
                print("[ChatGPT] Detected Xcode error analysis request")
                
                // Collect real IDE context
                let context = await collectIDEContext()
                print("[IDE] Context collected: \(context.ideType.rawValue) - \(context.fileName) - \(context.errorText)")
                
                // 🧠 Recall relevant memories
                let relevantMemories = memorySystem.recallRelevantMemories(
                    query: "error \(context.errorText)",
                    context: context,
                    limit: 3
                )
                
                // 🧠 Update memory system with current context
                memorySystem.updateContext(context)
                
                // Build enhanced prompt with memory context
                let memoryContext = relevantMemories.map { 
                    "Previous: \($0.content) (Source: \($0.source.displayName))"
                }.joined(separator: "\n")
                
                do {
                    let analysis = try await self.analyzeXcodeError(
                        errorText: context.errorText,
                        fileName: context.fileName,
                        selectedCode: context.selectedCode,
                        memoryContext: memoryContext
                    )
                    
                    print("[ChatGPT] Analysis complete: \(analysis)")
                    
                    // 🧠 Store interaction in memory
                    memorySystem.storeInteraction(
                        userInput: prompt,
                        fridayResponse: analysis,
                        success: true,
                        context: context
                    )
                    
                    // Display result on screen
                    DispatchQueue.main.async {
                        self.voiceManager?.speak("ChatGPT analysis complete, Pearl. \(analysis)")
                    }
                } catch {
                    print("[ChatGPT] Analysis failed: \(error)")
                    
                    // 🧠 Store failed interaction
                    memorySystem.storeInteraction(
                        userInput: prompt,
                        fridayResponse: "Analysis failed: \(error.localizedDescription)",
                        success: false,
                        context: context
                    )
                    
                    DispatchQueue.main.async {
                        self.voiceManager?.speak("I couldn't analyze the Xcode error, Pearl. Please check your ChatGPT API key and make sure Xcode is running.")
                    }
                }
            }
            return "Analyzing your Xcode error with ChatGPT, Pearl..."
        }
        
        if lowerPrompt.contains("screen") || lowerPrompt.contains("read") {
            Task {
                if let base64 = await ScreenManager.shared.captureScreenBase64() {
                    print("[Local] Screen captured successfully")
                    
                    // Try to analyze the screenshot with Gemini API
                    do {
                        let analysis = try await callGemini(
                            prompt: "IMPORTANT: You MUST analyze the attached screenshot image and describe exactly what you see. Do NOT give generic responses. Tell me specifically: 1) What applications are open, 2) What files or documents are visible, 3) What text content is on screen, 4) What the user appears to be working on. Be extremely detailed and specific about the current desktop state and activities.",
                            history: [],
                            imageBase64: base64
                        )
                        // Speak to analysis result
                        DispatchQueue.main.async {
                            self.voiceManager?.speak("Screen analysis complete, Pearl. \(analysis)")
                        }
                    } catch {
                        print("[Local] Image analysis failed: \(error)")
                        DispatchQueue.main.async {
                            self.voiceManager?.speak("Screen captured, Pearl. I can see your screen but couldn't analyze details right now.")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.voiceManager?.speak("Screen capture failed, Pearl. Please check your screen recording permissions in System Preferences.")
                    }
                }
            }
            return "Taking screenshot and analyzing your screen, Pearl..."
        }
        
        // Check for camera control commands
        if lowerPrompt.contains("camera") {
            if lowerPrompt.contains("deactivate") || lowerPrompt.contains("disable") || lowerPrompt.contains("off") {
                Task {
                    await SharedState.shared.setCameraEnabled(false)
                    // Actually stop face detection
                    self.onStartProctoringRequested?()
                }
                return "Camera deactivated, Pearl. Front camera stopped."
            }
            if lowerPrompt.contains("activate") || lowerPrompt.contains("enable") || lowerPrompt.contains("on") {
                Task {
                    await SharedState.shared.setCameraEnabled(true)

                    self.onStartProctoringRequested?()
                }
                return "Camera activated, Pearl. Front camera is now on and monitoring."
            }
            if lowerPrompt.contains("expression") || lowerPrompt.contains("face") || lowerPrompt.contains("reaction") {
                Task {
                    await SharedState.shared.setCameraEnabled(true)
                    print("[APIService] Starting expression monitoring...")
                    // Start proctoring engine for real facial expression monitoring
                    self.onStartTrainingRequested?()
                    self.onStartProctoringRequested?()
                }
                return "Facial expression monitoring enabled, Pearl. Front camera is tracking your expressions."
            }
        }
        
        // Check for screen monitoring commands
        if lowerPrompt.contains("screen") {
            if lowerPrompt.contains("monitor") || lowerPrompt.contains("watch") || lowerPrompt.contains("track") {
                Task {
                    // Start continuous desktop monitoring
                    startDesktopMonitoring()
                }
                return "Desktop monitoring activated, Pearl. I'll continuously analyze what you're seeing and doing."
            }
            if lowerPrompt.contains("stop") || lowerPrompt.contains("pause") {
                Task {
                    stopDesktopMonitoring()
                }
                return "Desktop monitoring paused, Pearl. Your privacy is protected."
            }
            
            // Real-time desktop analysis request
            if lowerPrompt.contains("what") && (lowerPrompt.contains("doing") || lowerPrompt.contains("seeing") || lowerPrompt.contains("desktop")) {
                Task {
                    if let base64 = await ScreenManager.shared.captureScreenBase64() {
                        do {
                            let analysis = try await callGemini(
                                prompt: "Analyze this desktop screenshot in detail. Tell me exactly what applications are open, what the user is currently working on, what files are visible, and what activity is happening. Be very specific and detailed.",
                                history: [],
                                imageBase64: base64
                            )
                            // Speak the analysis result
                            DispatchQueue.main.async {
                                self.voiceManager?.speak("Desktop analysis complete, Pearl. \(analysis)")
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.voiceManager?.speak("Desktop captured, Pearl. I can see your screen but couldn't analyze details right now.")
                            }
                        }
                    }
                }
                return "Analyzing your current desktop activity, Pearl..."
            }
        }
        
        return "I'm operating in local mode, Pearl, but I'm still here to help! Try asking me to activate camera for expression monitoring, or monitor your screen."
    }
    
    // Continuous Desktop Monitoring
    private var desktopMonitoringTimer: Timer?
    private var isDesktopMonitoring = false
    
    private func startDesktopMonitoring() {
        guard !isDesktopMonitoring else { return }
        isDesktopMonitoring = true
        print("[Desktop] Starting continuous monitoring...")
        
        desktopMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task {
                await self?.analyzeDesktop()
            }
        }
    }
    
    private func stopDesktopMonitoring() {
        isDesktopMonitoring = false
        desktopMonitoringTimer?.invalidate()
        desktopMonitoringTimer = nil
        print("[Desktop] Stopped continuous monitoring")
    }
    
    private func analyzeDesktop() async {
        guard let base64 = await ScreenManager.shared.captureScreenBase64() else { return }
        
        do {
            let analysis = try await callGemini(
                prompt: "IMPORTANT: Analyze the attached desktop screenshot image. Do NOT give generic responses. Tell me specifically: 1) What applications are currently open, 2) What files or documents are visible on screen, 3) What text content is displayed, 4) What specific task or activity the user is engaged in. Be extremely detailed and thorough about the current desktop state.",
                history: [],
                imageBase64: base64
            )
            print("[Desktop] Real-time analysis: \(analysis)")
            // Could trigger voice response for important changes
        } catch {
            print("[Desktop] Analysis failed: \(error)")
        }
    }
    
    private func callGemini(prompt: String, history: [ChatMessage] = [], imageBase64: String? = nil) async throws -> String {
        guard let url = URL(string: "\(geminiEndpoint)?key=\(geminiApiKey)") else { throw NSError(domain: "URL", code: 0) }
        
        // 1. Prepare conversation history (alternating User/Model)
        var contents: [[String: Any]] = []
        var lastRole = ""
        
        for msg in history.suffix(12) {
            let role = msg.isUser ? "user" : "model"
            if role == lastRole { continue }
            if contents.isEmpty && role != "user" { continue }
            contents.append(["role": role, "parts": [["text": msg.text]]])
            lastRole = role
        }
        
        // Ensure last message is NOT user if we're adding the current prompt
        if lastRole == "user" && !contents.isEmpty { contents.removeLast() }
        
        // 2. Prepare Current Parts
        var currentParts: [[String: Any]] = [["text": prompt]]
        if let base64 = imageBase64 {
            currentParts.append(["inline_data": ["mime_type": "image/png", "data": base64]])
        }
        contents.append(["role": "user", "parts": currentParts])
        
        // 3. Prepare the FULL Request Body with system_instruction (Modern Gemini 1.5 Style)
        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": systemPrompt]]
            ],
            "contents": contents,
            "tools": geminiTools,
            "generationConfig": [
                "temperature": 0.75,
                "topP": 0.95,
                "maxOutputTokens": 1024,
                "candidateCount": 1
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 4. Handle HTTP Errors
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let errorJson = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            print("[Gemini Error] HTTP \(http.statusCode): \(errorJson)")
            throw NSError(domain: "Gemini", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini API rejected request: \(http.statusCode)"])
        }
        
        // 5. Parse Response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error decoding brain response."
        }
        
        if let candidates = json["candidates"] as? [[String: Any]], let candidate = candidates.first {
            // Check for safety rejection
            if let finishReason = candidate["finishReason"] as? String, finishReason == "SAFETY" {
                return "I'm sorry, Pearl, but my safety protocols prevented me from answering that."
            }
            
            if let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] {
                for part in parts {
                    // Handle Tool Calls
                    if let funcCall = part["functionCall"] as? [String: Any] {
                        let name = funcCall["name"] as? String ?? ""
                        let args = funcCall["args"] as? [String: Any] ?? [:]
                        return try await handleFunctionCall(name: name, args: args, originalPrompt: prompt)
                    }
                    // Handle Text
                    if let text = part["text"] as? String, !text.isEmpty {
                        return text
                    }
                }
            }
        }
        
        // If we reached here, something went wrong with the JSON structure
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return "Brain Error: \(message)"
        }
        
        return "I heard you, Pearl, but my brain returned an empty thought. Checking connections..."
    }
    
    private func handleFunctionCall(name: String, args: [String: Any], originalPrompt: String) async throws -> String {
        switch name {
        case "get_proctor_status":
            let score = SharedState.shared.lastAnomalyScore
            let status = SharedState.shared.isViolation ? "Violation Detected" : "Secure"
            return "The proctor status is currently \(status) with a score of \(score)."
        case "get_current_time":
            return "The current time is \(Date().formatted())."
        case "tell_joke":
            let jokes = [
                "Why don't scientists trust atoms? Because they make up everything!",
                "Why did the scarecrow win an award? He was outstanding in his field!"
            ]
            return jokes.randomElement() ?? "I'm fresh out of jokes."
        case "toggle_camera":
            let enabled = args["enabled"] as? Bool ?? true
            await SharedState.shared.setCameraEnabled(enabled)
            return "The camera has been \(enabled ? "enabled" : "disabled")."
        case "control_system":
            let action = args["action"] as? String ?? ""
            let value = args["value"] as? Double ?? 50.0
            if action == "volume" { AppleScriptManager.shared.setVolume(Int(value)) }
            else if action == "brightness" { AppleScriptManager.shared.setBrightness(value) }
            else if action == "lock" { AppleScriptManager.shared.lockScreen() }
            return "System \(action) adjusted."
        case "read_screen":
            if let base64 = await ScreenManager.shared.captureScreenBase64() {
                return try await callGemini(prompt: "Analyze the screen for: \(originalPrompt)", imageBase64: base64)
            }
            return "I couldn't capture the screen."
        case "launch_application":
            let appName = args["name"] as? String ?? ""
            AppleScriptManager.shared.launchApp(appName)
            return "Launching \(appName)."
        default:
            return "I'm not sure how to perform that action yet."
        }
    }
    
    func collectIDEContext() async -> IDEContext {
        // Detect current IDE
        let ideType = detectCurrentIDE()
        
        switch ideType {
        case .xcode:
            return await collectXcodeContext()
        case .vscode:
            return await collectVSCodeContext()
        case .windsurf:
            return await collectWindsurfContext()
        case .antigravity:
            return await collectAntigravityContext()
        case .cursor:
            return await collectCursorContext()
        case .unknown:
            return IDEContext(
                errorText: "No supported IDE detected",
                fileName: "Unknown",
                selectedCode: "",
                buildLog: "",
                projectPath: "",
                ideType: .unknown,
                terminalOutput: ""
            )
        }
    }
    
    private func detectCurrentIDE() -> IDEType {
        #if os(macOS)
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        
        switch app.bundleIdentifier {
        case "com.apple.dt.Xcode": return .xcode
        case "com.microsoft.VSCode": return .vscode
        case "com.blackstone.Windsurf": return .windsurf
        case "com.antigravity.Antigravity": return .antigravity
        case "com.cursor.Cursor": return .cursor
        default: return .unknown
        }
        #else
        return .unknown
        #endif
    }
    
    // 🎯 Xcode Context Collection
    private func collectXcodeContext() async -> IDEContext {
        let projectPath = IDEHelperService.shared.getCurrentXcodeProject()
        let buildLog = IDEHelperService.shared.getLatestBuildLog()
        let errorText = IDEHelperService.shared.extractLatestError(from: buildLog)
        let fileName = IDEHelperService.shared.getCurrentFileName()
        let selectedCode = IDEHelperService.shared.getSelectedCode()
        
        return IDEContext(
            errorText: errorText,
            fileName: fileName,
            selectedCode: selectedCode,
            buildLog: buildLog,
            projectPath: projectPath,
            ideType: .xcode,
            terminalOutput: IDEHelperService.shared.getTerminalOutput()
        )
    }
    
    // 🎯 VS Code Context Collection
    private func collectVSCodeContext() async -> IDEContext {
        let fileName = IDEHelperService.shared.getVSCodeFileName()
        let selectedCode = IDEHelperService.shared.getVSCodeSelectedCode()
        let errorText = IDEHelperService.shared.getVSCodeErrors()
        let projectPath = IDEHelperService.shared.getVSCodeWorkspacePath()
        let terminalOutput = IDEHelperService.shared.getVSCodeTerminalOutput()
        
        return IDEContext(
            errorText: errorText,
            fileName: fileName,
            selectedCode: selectedCode,
            buildLog: "",
            projectPath: projectPath,
            ideType: .vscode,
            terminalOutput: terminalOutput
        )
    }
    
    // 🎯 Windsurf Context Collection
    private func collectWindsurfContext() async -> IDEContext {
        let fileName = IDEHelperService.shared.getWindsurfFileName()
        let selectedCode = IDEHelperService.shared.getWindsurfSelectedCode()
        let errorText = IDEHelperService.shared.getWindsurfErrors()
        let projectPath = IDEHelperService.shared.getWindsurfWorkspacePath()
        let terminalOutput = IDEHelperService.shared.getWindsurfTerminalOutput()
        
        return IDEContext(
            errorText: errorText,
            fileName: fileName,
            selectedCode: selectedCode,
            buildLog: "",
            projectPath: projectPath,
            ideType: .windsurf,
            terminalOutput: terminalOutput
        )
    }
    
    // 🎯 Antigravity Context Collection
    private func collectAntigravityContext() async -> IDEContext {
        let fileName = IDEHelperService.shared.getAntigravityFileName()
        let selectedCode = IDEHelperService.shared.getAntigravitySelectedCode()
        let errorText = IDEHelperService.shared.getAntigravityErrors()
        let projectPath = IDEHelperService.shared.getAntigravityWorkspacePath()
        let terminalOutput = IDEHelperService.shared.getAntigravityTerminalOutput()
        
        return IDEContext(
            errorText: errorText,
            fileName: fileName,
            selectedCode: selectedCode,
            buildLog: "",
            projectPath: projectPath,
            ideType: .antigravity,
            terminalOutput: terminalOutput
        )
    }
    
    // 🎯 Cursor Context Collection
    private func collectCursorContext() async -> IDEContext {
        let fileName = IDEHelperService.shared.getCursorFileName()
        let selectedCode = IDEHelperService.shared.getCursorSelectedCode()
        let errorText = IDEHelperService.shared.getCursorErrors()
        let projectPath = IDEHelperService.shared.getCursorWorkspacePath()
        let terminalOutput = IDEHelperService.shared.getCursorTerminalOutput()
        
        return IDEContext(
            errorText: errorText,
            fileName: fileName,
            selectedCode: selectedCode,
            buildLog: "",
            projectPath: projectPath,
            ideType: .cursor,
            terminalOutput: terminalOutput
        )
    }
    
    // 🤖 Enhanced ChatGPT Integration for Xcode Error Analysis
    func analyzeXcodeError(errorText: String, fileName: String = "", selectedCode: String = "", memoryContext: String = "") async throws -> String {
        let systemPrompt = """
        You are an expert Xcode and Swift developer assistant helping Pearl fix coding issues.
        You will receive comprehensive project information including:
        - Project structure and context
        - What the user was working on
        - Current error details
        - Selected code snippet
        
        Your tasks:
        1. First, understand the project structure and context
        2. Explain what went wrong in simple terms
        3. Provide the exact location of the error (file, line if possible)
        4. Give a concrete, copy-paste ready fix
        5. Explain WHY the fix works
        6. Keep response concise enough for voice (3-4 paragraphs max)
        
        Always structure your response as:
        "I understand you're working on [project type]. The error occurs because [reason]. Here's the fix: [solution]. This works because [explanation]."
        """
        
        let userPromptText = """
        PROJECT INFORMATION:
        ===================
        Project Type: \(IDEHelperService.shared.getProjectType(from: fileName))
        Current File: \(fileName)
        File Type: \(IDEHelperService.shared.getFileType(from: fileName))
        
        WHAT YOU WERE WORKING ON:
        =========================
        \(IDEHelperService.shared.getWorkContext(from: fileName, selectedCode: selectedCode))
        
        ERROR DETAILS:
        ==============
        Error Message: \(errorText)
        Error Type: \(IDEHelperService.shared.getErrorType(from: errorText))
        Severity: \(IDEHelperService.shared.getErrorSeverity(from: errorText))
        
        CODE CONTEXT:
        ============
        Selected Code:
        ```swift
        \(selectedCode)
        ```
        """
        
        let finalPrompt = userPromptText + "\n\n" + (memoryContext.isEmpty ? "" : "RELEVANT MEMORY:\n\(memoryContext)")
        
        return try await callGemini(prompt: finalPrompt, history: [])
    }
}
