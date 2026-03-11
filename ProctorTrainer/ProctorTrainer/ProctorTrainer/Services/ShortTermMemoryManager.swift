import Foundation
import Combine

// MARK: - Short-Term Memory Manager
class ShortTermMemoryManager: ObservableObject {
    // MARK: - Properties
    @Published var currentInteractions: [Interaction] = []
    @Published var currentContext: WorkContext
    @Published var activeTask: Task?
    @Published var recentErrors: [ErrorContext] = []
    
    private let maxInteractions = 50
    private let contextWindowMinutes = 30
    
    // MARK: - Data Models
    struct Interaction {
        var id: UUID
        var timestamp: Date
        var userInput: String
        var fridayResponse: String
        var context: WorkContext
        var success: Bool
        var sentiment: Sentiment
        var duration: TimeInterval
        var tags: [String]
    }
    
    struct WorkContext {
        var projectName: String
        var fileName: String
        var language: String
        var ideType: String
        var timestamp: Date
        var task: String?
        var selectedText: String
    }
    
    struct Task {
        var id: UUID
        var type: TaskType
        var description: String
        var startTime: Date
        var duration: TimeInterval
        var files: [String]
        var status: TaskStatus
        var progress: Double // 0.0 to 1.0
    }
    
    struct ErrorContext {
        var id: UUID
        var message: String
        var type: String
        var file: String
        var line: Int?
        var severity: Severity
        var timestamp: Date
        var attemptedFixes: [String]
        var resolved: Bool
    }
    
    struct Sentiment {
        var score: Double // -1.0 to 1.0
        var confidence: Double // 0.0 to 1.0
        var emotions: [String: Double]
    }
    
    enum TaskType: String, CaseIterable {
        case debugging = "debugging"
        case coding = "coding"
        case refactoring = "refactoring"
        case learning = "learning"
        case documentation = "documentation"
        case testing = "testing"
        case review = "review"
        
        var displayName: String {
            switch self {
            case .debugging: return "Debugging"
            case .coding: return "Coding"
            case .refactoring: return "Refactoring"
            case .learning: return "Learning"
            case .documentation: return "Documentation"
            case .testing: return "Testing"
            case .review: return "Review"
            }
        }
    }
    
    enum TaskStatus: String, CaseIterable {
        case active = "active"
        case paused = "paused"
        case completed = "completed"
        case failed = "failed"
        
        var displayName: String {
            switch self {
            case .active: return "Active"
            case .paused: return "Paused"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }
    
    enum Severity: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case critical = "critical"
        
        var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        self.currentContext = WorkContext(
            projectName: "",
            fileName: "",
            language: "",
            ideType: "",
            timestamp: Date(),
            task: nil,
            selectedText: ""
        )
    }
    
    // MARK: - Interaction Management
    
    /// Add a new interaction to short-term memory
    func addInteraction(
        userInput: String,
        fridayResponse: String,
        context: WorkContext,
        success: Bool = true,
        duration: TimeInterval = 0.0
    ) {
        let interaction = Interaction(
            id: UUID(),
            timestamp: Date(),
            userInput: userInput,
            fridayResponse: fridayResponse,
            context: context,
            success: success,
            sentiment: analyzeSentiment(userInput),
            duration: duration,
            tags: extractTags(from: userInput)
        )
        
        currentInteractions.append(interaction)
        
        // Maintain size limit
        if currentInteractions.count > maxInteractions {
            currentInteractions.removeFirst()
        }
        
        // Update current context
        updateContext(context)
        
        print("[ShortTerm] Added interaction: \(userInput.prefix(50))...")
    }
    
    /// Get recent interactions within time window
    func getRecentInteractions(minutes: Int = 30) -> [Interaction] {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return currentInteractions.filter { $0.timestamp > cutoff }
    }
    
    /// Get interactions by context
    func getInteractions(for project: String? = nil, file: String? = nil) -> [Interaction] {
        return currentInteractions.filter { interaction in
            let projectMatch = project == nil || interaction.context.projectName == project
            let fileMatch = file == nil || interaction.context.fileName == file
            return projectMatch && fileMatch
        }
    }
    
    /// Get session summary
    func getSessionSummary() -> ShortTermSessionSummary {
        let recentInteractions = getRecentInteractions(minutes: 60)
        
        let successRate = recentInteractions.isEmpty ? 1.0 : 
            Double(recentInteractions.filter { $0.success }.count) / Double(recentInteractions.count)
        
        let averageSentiment = recentInteractions.isEmpty ? 0.0 :
            recentInteractions.map { $0.sentiment.score }.reduce(0, +) / Double(recentInteractions.count)
        
        let projects = Set(recentInteractions.map { $0.context.projectName })
        let files = Set(recentInteractions.map { $0.context.fileName })
        
        return ShortTermSessionSummary(
            duration: Date().timeIntervalSince(recentInteractions.first?.timestamp ?? Date()),
            interactionCount: recentInteractions.count,
            successRate: successRate,
            averageSentiment: averageSentiment,
            projectsWorkedOn: Array(projects),
            filesWorkedOn: Array(files),
            activeTask: activeTask,
            errorCount: recentErrors.count
        )
    }
    
    // MARK: - Task Management
    
    /// Start a new task
    func startTask(type: TaskType, description: String, files: [String] = []) {
        let task = Task(
            id: UUID(),
            type: type,
            description: description,
            startTime: Date(),
            duration: 0,
            files: files,
            status: .active,
            progress: 0.0
        )
        
        activeTask = task
        
        print("[ShortTerm] Started task: \(type.displayName) - \(description)")
    }
    
    /// Update current task progress
    func updateTaskProgress(progress: Double) {
        if var task = activeTask {
            task.progress = min(max(progress, 0.0), 1.0)
            activeTask = task
        }
    }
    
    /// Complete current task
    func completeTask(success: Bool = true) {
        guard var task = activeTask else { return }
        
        task.duration = Date().timeIntervalSince(task.startTime)
        task.status = success ? .completed : .failed
        task.progress = 1.0
        
        activeTask = nil
        
        print("[ShortTerm] Completed task: \(task.type.displayName) - Success: \(success)")
    }
    
    /// Pause current task
    func pauseTask() {
        if var task = activeTask {
            task.status = .paused
            activeTask = task
        }
    }
    
    /// Resume task
    func resumeTask() {
        if var task = activeTask {
            task.status = .active
            activeTask = task
        }
    }
    
    // MARK: - Error Management
    
    /// Add an error to recent errors
    func addError(
        message: String,
        type: String,
        file: String,
        line: Int? = nil,
        severity: Severity = .medium
    ) {
        let error = ErrorContext(
            id: UUID(),
            message: message,
            type: type,
            file: file,
            line: line,
            severity: severity,
            timestamp: Date(),
            attemptedFixes: [],
            resolved: false
        )
        
        recentErrors.append(error)
        
        // Keep only recent errors (last 20)
        if recentErrors.count > 20 {
            recentErrors.removeFirst()
        }
        
        print("[ShortTerm] Added error: \(message.prefix(50))...")
    }
    
    /// Mark error as resolved
    func resolveError(errorId: UUID, solution: String) {
        if let index = recentErrors.firstIndex(where: { $0.id == errorId }) {
            recentErrors[index].resolved = true
            recentErrors[index].attemptedFixes.append(solution)
        }
    }
    
    /// Get recent errors
    func getRecentErrors(minutes: Int = 30) -> [ErrorContext] {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return recentErrors.filter { $0.timestamp > cutoff }
    }
    
    /// Get unresolved errors
    func getUnresolvedErrors() -> [ErrorContext] {
        return recentErrors.filter { !$0.resolved }
    }
    
    // MARK: - Context Management
    
    /// Update current work context
    func updateContext(_ context: WorkContext) {
        currentContext = context
        
        // Auto-detect task type based on context
        if activeTask == nil {
            let detectedTask = detectTaskType(from: context)
            if detectedTask != nil {
                startTask(type: detectedTask!, description: "Auto-detected task")
            }
        }
    }
    
    /// Get current context
    func getCurrentContext() -> WorkContext {
        return currentContext
    }
    
    /// Clear session
    func clearSession() {
        currentInteractions.removeAll()
        recentErrors.removeAll()
        activeTask = nil
        
        print("[ShortTerm] Session cleared")
    }
    
    // MARK: - Private Helper Methods
    
    private func analyzeSentiment(_ text: String) -> Sentiment {
        // Simple sentiment analysis
        let positiveWords = ["good", "great", "excellent", "thanks", "perfect", "awesome", "love", "helpful"]
        let negativeWords = ["bad", "terrible", "awful", "hate", "wrong", "error", "failed", "broken"]
        
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let positiveCount = words.filter { positiveWords.contains($0) }.count
        let negativeCount = words.filter { negativeWords.contains($0) }.count
        
        let score = Double(positiveCount - negativeCount) / Double(max(words.count, 1))
        let confidence = min(abs(score) * 2.0, 1.0)
        
        return Sentiment(
            score: score,
            confidence: confidence,
            emotions: ["positive": Double(positiveCount), "negative": Double(negativeCount)]
        )
    }
    
    private func extractTags(from text: String) -> [String] {
        var tags: [String] = []
        
        // Extract common keywords
        let keywords = ["error", "solution", "fix", "help", "code", "function", "class", "variable", "import", "build"]
        
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        for keyword in keywords {
            if words.contains(keyword) {
                tags.append(keyword)
            }
        }
        
        return tags
    }
    
    private func detectTaskType(from context: WorkContext) -> TaskType? {
        let text = "\(context.task ?? "") \(context.selectedText)".lowercased()
        
        if text.contains("error") || text.contains("fix") || text.contains("debug") {
            return .debugging
        } else if text.contains("function") || text.contains("class") || text.contains("code") {
            return .coding
        } else if text.contains("refactor") || text.contains("improve") {
            return .refactoring
        } else if text.contains("learn") || text.contains("explain") {
            return .learning
        } else if text.contains("test") {
            return .testing
        } else if text.contains("review") {
            return .review
        }
        
        return nil
    }
}

// MARK: - Supporting Types
struct ShortTermSessionSummary {
    let duration: TimeInterval
    let interactionCount: Int
    let successRate: Double
    let averageSentiment: Double
    let projectsWorkedOn: [String]
    let filesWorkedOn: [String]
    let activeTask: ShortTermMemoryManager.Task?
    let errorCount: Int
}
