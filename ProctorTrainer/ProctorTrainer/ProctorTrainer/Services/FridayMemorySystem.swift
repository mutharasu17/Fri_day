import Foundation
import SwiftData
import Combine

// MARK: - Friday Memory System (Core Integration)
class FridayMemorySystem: ObservableObject {
    // MARK: - Core Components
    private let longTermMemory: LongTermMemoryManager
    private let shortTermMemory: ShortTermMemoryManager
    private let contextMemory: ContextMemoryManager
    
    // MARK: - Published State
    @Published var isInitialized = false
    @Published var currentSession: SessionInfo
    @Published var memoryStats: MemoryStats
    
    // MARK: - Initialization
    init() {
        self.longTermMemory = LongTermMemoryManager()
        self.shortTermMemory = ShortTermMemoryManager()
        self.contextMemory = ContextMemoryManager()
        
        self.currentSession = SessionInfo(
            startTime: Date(),
            interactionCount: 0,
            errorCount: 0,
            successRate: 1.0
        )
        
        self.memoryStats = MemoryStats()
        
        // Initialize system
        Task {
            await initializeMemorySystem()
        }
    }
    
    // MARK: - Core Memory Operations
    
    /// Store a complete interaction with full context
    func storeInteraction(
        userInput: String,
        fridayResponse: String,
        success: Bool = true,
        duration: TimeInterval = 0.0,
        context: IDEContext? = nil
    ) {
        // Build work context
        let workContext = buildWorkContext(from: context)
        
        // Store in short-term memory
        shortTermMemory.addInteraction(
            userInput: userInput,
            fridayResponse: fridayResponse,
            context: workContext,
            success: success,
            duration: duration
        )
        
        // Extract important information for long-term storage
        let extractedInfo = extractImportantInformation(
            userInput: userInput,
            response: fridayResponse,
            context: workContext,
            success: success
        )
        
        // Store important items in long-term memory
        for info in extractedInfo {
            switch info.type {
            case .errorSolution:
                longTermMemory.storeErrorSolution(
                    error: info.error ?? "",
                    errorType: info.errorType ?? "",
                    solution: info.solution ?? "",
                    explanation: info.explanation ?? "",
                    fileName: workContext.fileName,
                    projectName: workContext.projectName,
                    language: workContext.language
                )
                
            case .userPreference:
                if let preference = extractUserPreference(from: userInput) {
                    longTermMemory.storeUserPreference(
                        key: preference.key,
                        value: preference.value,
                        category: preference.category,
                        confidence: preference.confidence
                    )
                }
                
            case .projectInfo:
                if let projectInfo = extractProjectInfo(from: workContext) {
                    longTermMemory.storeProjectInfo(
                        name: projectInfo.name,
                        path: projectInfo.path,
                        type: projectInfo.type.rawValue,           // ✅ enum → String
                        technologies: projectInfo.technologies,
                        architecture: projectInfo.architecture.rawValue  // ✅ enum → String
                    )
                }
                
            case .codePattern:
                longTermMemory.storeMemory(
                    content: info.content ?? "",
                    type: .codePattern,
                    tags: info.tags,
                    projectName: workContext.projectName,
                    fileName: workContext.fileName,
                    language: workContext.language,
                    importance: info.importance
                )
                
            default:
                longTermMemory.storeMemory(
                    content: info.content ?? "",
                    type: info.type,
                    tags: info.tags,
                    projectName: workContext.projectName,
                    fileName: workContext.fileName,
                    language: workContext.language,
                    importance: info.importance
                )
            }
        }
        
        // Update session info
        updateSessionInfo(success: success)
        
        // Update context memory
        if let context = context {
            updateContextMemory(context)
        }
        
        print("[MemorySystem] Stored interaction: \(userInput.prefix(50))...")
    }
    
    /// Recall relevant memories for current context
    func recallRelevantMemories(
        query: String,
        context: IDEContext? = nil,
        limit: Int = 5
    ) -> [MemoryRecall] {
        let workContext = buildWorkContext(from: context)
        var relevantMemories: [MemoryRecall] = []
        
        // 1. Short-term: Recent interactions
        let recentInteractions = shortTermMemory.getRecentInteractions(minutes: 30)
        for interaction in recentInteractions {
            if interaction.userInput.lowercased().contains(query.lowercased()) ||
               interaction.fridayResponse.lowercased().contains(query.lowercased()) {
                relevantMemories.append(MemoryRecall(
                    id: interaction.id,
                    content: interaction.fridayResponse,
                    type: .conversation,
                    source: .shortTerm,
                    relevance: calculateRelevance(query: query, content: interaction.fridayResponse),
                    timestamp: interaction.timestamp,
                    context: "Recent interaction"
                ))
            }
        }
        
        // 2. Long-term: Search by content and context
        let longTermMemories = longTermMemory.searchMemories(
            query: query,
            projectName: workContext.projectName,
            limit: limit
        )
        
        for memory in longTermMemories {
            relevantMemories.append(MemoryRecall(
                id: memory.id,
                content: memory.content,
                type: memory.type,
                source: .longTerm,
                relevance: calculateRelevance(query: query, content: memory.content),
                timestamp: memory.timestamp,
                context: "Stored memory: \(memory.type.displayName)"
            ))
        }
        
        // 3. Error solutions: If query contains error terms
        if query.lowercased().contains("error") || query.lowercased().contains("fix") {
            let errorSolutions = longTermMemory.getErrorSolutions(
                for: query,
                projectName: workContext.projectName
            )
            
            for solution in errorSolutions {
                relevantMemories.append(MemoryRecall(
                    id: solution.id,
                    content: solution.solution,
                    type: .errorSolution,
                    source: .longTerm,
                    relevance: calculateRelevance(query: query, content: solution.errorMessage),
                    timestamp: solution.lastUsed,
                    context: "Error solution: \(solution.errorType)"
                ))
            }
        }
        
        // 4. User preferences: If query is about preferences
        if query.lowercased().contains("prefer") || query.lowercased().contains("like") {
            let preferences = longTermMemory.getUserPreferences()
            
            for preference in preferences {
                relevantMemories.append(MemoryRecall(
                    id: preference.id,
                    content: "\(preference.key): \(preference.value)",
                    type: .userPreference,
                    source: .longTerm,
                    relevance: calculateRelevance(query: query, content: "\(preference.key) \(preference.value)"),
                    timestamp: preference.updatedAt,
                    context: "User preference: \(preference.category.displayName)"
                ))
            }
        }
        
        // Sort by relevance and timestamp
        return relevantMemories
            .sorted { $0.relevance > $1.relevance }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Update current context from IDE information
    func updateContext(_ ideContext: IDEContext) {
        // Update context memory
        updateContextMemory(ideContext)
        
        // Auto-detect and store project info
        if !ideContext.projectPath.isEmpty {
            let projectInfo = extractProjectInfoFromIDE(ideContext)
            longTermMemory.storeProjectInfo(
                name: projectInfo.name,
                path: projectInfo.path,
                type: projectInfo.type.rawValue,          // ✅ enum → String
                technologies: projectInfo.technologies,
                architecture: projectInfo.architecture.rawValue  // ✅ enum → String
            )
        }
        
        // Auto-detect task type
        let detectedTask = detectCurrentTask(from: ideContext)
        if detectedTask != nil {
            shortTermMemory.startTask(
                type: detectedTask!,
                description: "Auto-detected from context"
            )
        }
    }
    
    /// Get comprehensive memory summary
    func getMemorySummary() -> MemorySummary {
        let shortTermSummary = shortTermMemory.getSessionSummary()
        let longTermStats = longTermMemory.getMemoryStats()
        let contextSummary = contextMemory.getCurrentContextSummary()
        
        return MemorySummary(
            session: shortTermSummary,
            longTerm: longTermStats,
            context: contextSummary,
            recommendations: generateRecommendations(
                session: shortTermSummary,
                stats: longTermStats,
                context: contextSummary
            )
        )
    }
    
    // MARK: - Memory Management
    
    /// Perform memory consolidation and cleanup
    func performMemoryMaintenance() {
        Task {
            // 1. Consolidate short-term to long-term
            await consolidateShortTermMemory()
            
            // 2. Clean up old memories
            longTermMemory.cleanupOldMemories(olderThan: 30)
            
            // 3. Update statistics
            await updateMemoryStats()
            
            print("[MemorySystem] Maintenance completed")
        }
    }
    
    /// Export memory data for backup
    func exportMemoryData() -> MemoryExport? {
        // Use the public export method instead of accessing private modelContext
        return longTermMemory.exportAllData()
    }
    
    // MARK: - Private Helper Methods
    
    private func initializeMemorySystem() async {
        // Wait for long-term memory to initialize
        while !longTermMemory.isInitialized {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }
        
        // Load user preferences
        await loadUserPreferences()
        
        // Update statistics
        await updateMemoryStats()
        
        isInitialized = true
        
        print("[MemorySystem] Initialized successfully")
    }
    
    private func buildWorkContext(from ideContext: IDEContext?) -> ShortTermMemoryManager.WorkContext {
        return ShortTermMemoryManager.WorkContext(
            projectName: ideContext?.projectPath.components(separatedBy: "/").last ?? "",
            fileName: ideContext?.fileName ?? "",
            language: detectLanguage(from: ideContext?.fileName ?? ""),
            ideType: ideContext?.ideType.rawValue ?? "",
            timestamp: Date(),
            task: shortTermMemory.activeTask?.type.displayName,
            selectedText: ideContext?.selectedCode ?? ""
        )
    }
    
    private func extractImportantInformation(
        userInput: String,
        response: String,
        context: ShortTermMemoryManager.WorkContext,
        success: Bool
    ) -> [ExtractedInfo] {
        var extracted: [ExtractedInfo] = []
        
        // Error solutions
        if userInput.lowercased().contains("error") && response.lowercased().contains("fix") {
            extracted.append(ExtractedInfo(
                type: .errorSolution,
                content: response,
                importance: 0.9,
                tags: ["error", "solution", context.language, context.fileName]
            ))
        }
        
        // User preferences
        if userInput.lowercased().contains("prefer") || userInput.lowercased().contains("like") {
            extracted.append(ExtractedInfo(
                type: .userPreference,
                content: userInput,
                importance: 0.8,
                tags: ["preference", "user"]
            ))
        }
        
        // Code patterns
        if response.contains("func ") || response.contains("class ") || response.contains("struct ") {
            extracted.append(ExtractedInfo(
                type: .codePattern,
                content: response,
                importance: 0.6,
                tags: ["pattern", "code", context.language]
            ))
        }
        
        // Learning moments
        if userInput.lowercased().contains("explain") || userInput.lowercased().contains("learn") {
            extracted.append(ExtractedInfo(
                type: .learning,
                content: response,
                importance: 0.7,
                tags: ["learning", "explanation", context.language]
            ))
        }
        
        return extracted
    }
    
    private func extractUserPreference(from userInput: String) -> UserPreferenceInfo? {
        let lowerInput = userInput.lowercased()
        
        // Extract preference patterns
        if lowerInput.contains("prefer") {
            let parts = userInput.components(separatedBy: "prefer")
            if parts.count > 1 {
                let preference = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return UserPreferenceInfo(
                    key: "response_style",
                    value: preference,
                    category: .responseStyle,
                    confidence: 0.8
                )
            }
        }
        
        return nil
    }
    
    private func extractProjectInfo(from context: ShortTermMemoryManager.WorkContext) -> ProjectInfo? {
        if !context.projectName.isEmpty {
            return ProjectInfo(
                name: context.projectName,
                path: "", // Would need to be provided by IDE context
                type: detectProjectType(from: context.fileName),
                technologies: detectTechnologies(from: context.language),
                architecture: detectArchitecture(from: context.fileName)
            )
        }
        return nil
    }
    
    private func extractProjectInfoFromIDE(_ ideContext: IDEContext) -> ProjectInfo {
        return ProjectInfo(
            name: ideContext.projectPath.components(separatedBy: "/").last ?? "",
            path: ideContext.projectPath,
            type: detectProjectType(from: ideContext.fileName),
            technologies: detectTechnologies(from: ideContext.fileName),
            architecture: detectArchitecture(from: ideContext.fileName)
        )
    }
    
    private func detectCurrentTask(from ideContext: IDEContext) -> ShortTermMemoryManager.TaskType? {
        let context = "\(ideContext.errorText) \(ideContext.selectedCode)".lowercased()
        
        if context.contains("error") || context.contains("fix") {
            return .debugging
        } else if context.contains("func") || context.contains("class") {
            return .coding
        } else if context.contains("refactor") {
            return .refactoring
        } else if context.contains("test") {
            return .testing
        }
        
        return nil
    }
    
    private func updateContextMemory(_ ideContext: IDEContext) {
        // Update project context
        contextMemory.updateProjectContext(
            name: ideContext.projectPath.components(separatedBy: "/").last ?? "",
            path: ideContext.projectPath,
            type: detectProjectType(from: ideContext.fileName),
            technologies: detectTechnologies(from: ideContext.fileName)
        )
        
        // Update active file
        contextMemory.updateActiveFile(
            name: ideContext.fileName,
            path: ideContext.projectPath + "/" + ideContext.fileName,
            language: detectLanguage(from: ideContext.fileName),
            content: ideContext.selectedCode,
            selectedText: ideContext.selectedCode
        )
        
        // Update workspace state
        contextMemory.updateWorkspaceState(
            ideType: ideContext.ideType.rawValue,
            activeTab: ideContext.fileName
        )
    }
    
    private func updateSessionInfo(success: Bool) {
        currentSession.interactionCount += 1
        if !success {
            currentSession.errorCount += 1
        }
        currentSession.successRate = Double(currentSession.interactionCount - currentSession.errorCount) / Double(currentSession.interactionCount)
    }
    
    @MainActor
    private func updateMemoryStats() {
        memoryStats = longTermMemory.getMemoryStats()
    }
    
    private func loadUserPreferences() async {
        let preferences = longTermMemory.getUserPreferences()
        // Apply preferences to system behavior
        for preference in preferences {
            print("[MemorySystem] Loaded preference: \(preference.key) = \(preference.value)")
        }
    }
    
    private func consolidateShortTermMemory() async {
        let interactions = shortTermMemory.getRecentInteractions(minutes: 60)
        
        for interaction in interactions {
            if interaction.success && interaction.sentiment.score > 0.5 {
                // Consolidate successful positive interactions
                longTermMemory.storeMemory(
                    content: interaction.fridayResponse,
                    type: .conversation,
                    tags: interaction.tags,
                    projectName: interaction.context.projectName,
                    fileName: interaction.context.fileName,
                    language: interaction.context.language,
                    importance: 0.6
                )
            }
        }
    }
    
    private func calculateRelevance(query: String, content: String) -> Double {
        let queryWords = query.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let contentWords = content.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        let matchingWords = queryWords.filter { contentWords.contains($0) }
        return Double(matchingWords.count) / Double(queryWords.count)
    }
    
    private func generateRecommendations(
        session: ShortTermSessionSummary,
        stats: MemoryStats,
        context: ContextSummary
    ) -> [String] {
        var recommendations: [String] = []
        
        // Based on error rate
        if session.errorCount > 3 {
            recommendations.append("Consider taking a break - error rate is high")
        }
        
        // Based on project complexity
        if context.project.complexity == .complex {
            recommendations.append("Project is complex - consider breaking down tasks")
        }
        
        // Based on memory usage
        if stats.totalMemories > 1000 {
            recommendations.append("Memory usage is high - consider cleanup")
        }
        
        return recommendations
    }
    
    // MARK: - Helper Detection Methods
    
    private func detectLanguage(from fileName: String) -> String {
        if fileName.hasSuffix(".swift") { return "Swift" }
        if fileName.hasSuffix(".ts") { return "TypeScript" }
        if fileName.hasSuffix(".tsx") { return "TypeScript React" }
        if fileName.hasSuffix(".js") { return "JavaScript" }
        if fileName.hasSuffix(".jsx") { return "JavaScript React" }
        if fileName.hasSuffix(".py") { return "Python" }
        if fileName.hasSuffix(".java") { return "Java" }
        return "Unknown"
    }
    
    private func detectProjectType(from fileName: String) -> ContextMemoryManager.ProjectContext.ProjectType {
        if fileName.contains("ViewController") || fileName.contains("View") {
            return .ios
        } else if fileName.hasSuffix(".swift") {
            return .macos
        } else if fileName.hasSuffix(".ts") || fileName.hasSuffix(".tsx") {
            return .web
        }
        return .unknown
    }
    
    private func detectTechnologies(from fileName: String) -> [String] {
        var technologies: [String] = []
        
        if fileName.hasSuffix(".swift") {
            technologies.append("Swift")
            if fileName.contains("UI") { technologies.append("SwiftUI") }
            if fileName.contains("Foundation") { technologies.append("Foundation") }
        }
        
        if fileName.hasSuffix(".ts") {
            technologies.append("TypeScript")
            if fileName.contains("React") { technologies.append("React") }
            if fileName.contains("Node") { technologies.append("Node.js") }
        }
        
        return technologies
    }
    
    private func detectArchitecture(from fileName: String) -> ContextMemoryManager.ProjectContext.ArchitecturePattern {
        if fileName.contains("ViewModel") { return .mvvm }
        if fileName.contains("Controller") { return .mvc }
        if fileName.contains("Service") { return .clean }
        return .unknown
    }
}

// MARK: - Supporting Types
struct MemoryRecall {
    let id: UUID
    let content: String
    let type: MemoryEntity.MemoryType
    let source: MemorySource
    let relevance: Double
    let timestamp: Date
    let context: String
    
    enum MemorySource: String, CaseIterable {
        case shortTerm = "short_term"
        case longTerm = "long_term"
        case contextual = "contextual"
        
        var displayName: String {
            switch self {
            case .shortTerm: return "Short-Term"
            case .longTerm: return "Long-Term"
            case .contextual: return "Contextual"
            }
        }
    }
}

struct ExtractedInfo {
    let type: MemoryEntity.MemoryType
    let content: String?
    let error: String?
    let errorType: String?
    let solution: String?
    let explanation: String?
    let importance: Double
    let tags: [String]
    
    // Default nil for optional fields so call sites don't need all parameters
    init(
        type: MemoryEntity.MemoryType,
        content: String? = nil,
        error: String? = nil,
        errorType: String? = nil,
        solution: String? = nil,
        explanation: String? = nil,
        importance: Double = 0.5,
        tags: [String] = []
    ) {
        self.type = type
        self.content = content
        self.error = error
        self.errorType = errorType
        self.solution = solution
        self.explanation = explanation
        self.importance = importance
        self.tags = tags
    }
}

struct UserPreferenceInfo {
    let key: String
    let value: String
    let category: UserPreference.PreferenceCategory
    let confidence: Double
}

struct ProjectInfo {
    let name: String
    let path: String
    let type: ContextMemoryManager.ProjectContext.ProjectType
    let technologies: [String]
    let architecture: ContextMemoryManager.ProjectContext.ArchitecturePattern
}

struct SessionInfo {
    let startTime: Date
    var interactionCount: Int
    var errorCount: Int
    var successRate: Double
}

struct MemorySummary {
    let session: ShortTermSessionSummary
    let longTerm: MemoryStats
    let context: ContextSummary
    let recommendations: [String]
}

struct MemoryExport {
    let memories: [MemoryEntity]
    let projects: [ProjectMemory]
    let preferences: [UserPreference]
    let exportDate: Date
}
