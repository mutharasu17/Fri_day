import Foundation
import SwiftData

// MARK: - Core Memory Entity
@Model
class MemoryEntity {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var type: MemoryEntity.MemoryType = MemoryEntity.MemoryType.conversation
    var content: String = ""
    var summary: String = ""
    var tags: [String] = []
    var embedding: Data?
    
    // Importance & Access
    var importance: Double = 0.0
    var accessCount: Int = 0
    var lastAccessed: Date = Date()
    
    // Context Information
    var projectName: String = ""
    var fileName: String = ""
    var language: String = ""
    var errorType: String = ""
    
    // Cognitive Metadata
    var sentiment: Double = 0.0
    var success: Bool = true
    var duration: TimeInterval = 0.0
    
    // Relationships
    var relatedMemories: [UUID] = []
    var parentMemory: UUID?
    
    init(timestamp: Date = Date(), type: MemoryType = .conversation, content: String = "", summary: String = "", tags: [String] = []) {
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.summary = summary
        self.tags = tags
        self.lastAccessed = Date()
    }
    
    enum MemoryType: String, CaseIterable, Codable {
        case errorSolution = "error_solution"
        case projectInfo = "project_info"
        case userPreference = "user_preference"
        case codePattern = "code_pattern"
        case workflow = "workflow"
        case conversation = "conversation"
        case learning = "learning"
        
        var displayName: String {
            switch self {
            case .errorSolution: return "Error Solution"
            case .projectInfo: return "Project Information"
            case .userPreference: return "User Preference"
            case .codePattern: return "Code Pattern"
            case .workflow: return "Workflow"
            case .conversation: return "Conversation"
            case .learning: return "Learning"
            }
        }
    }
}

// MARK: - Project Memory
@Model
class ProjectMemory {
    var id: UUID = UUID()
    var projectName: String = ""
    var projectPath: String = ""
    var projectType: String = ""
    var technologies: [String] = []
    var architecture: String = ""
    var lastAccessed: Date = Date()
    var errorHistory: [String] = []
    var solutionHistory: [String] = []
    var userPatterns: [String] = []
    var preferences: [String] = []
    var createdAt: Date = Date()
    var isActive: Bool = true
    
    init(projectName: String = "", projectPath: String = "", projectType: String = "", technologies: [String] = [], architecture: String = "") {
        self.projectName = projectName
        self.projectPath = projectPath
        self.projectType = projectType
        self.technologies = technologies
        self.architecture = architecture
        self.createdAt = Date()
        self.lastAccessed = Date()
    }
}

// MARK: - User Preference
@Model
class UserPreference {
    var id: UUID = UUID()
    var key: String = ""
    var value: String = ""
    var category: UserPreference.PreferenceCategory = UserPreference.PreferenceCategory.general
    var confidence: Double = 1.0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var accessCount: Int = 0
    
    init(key: String = "", value: String = "", category: UserPreference.PreferenceCategory = .general) {
        self.key = key
        self.value = value
        self.category = category
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    enum PreferenceCategory: String, CaseIterable, Codable {
        case responseStyle = "response_style"
        case codeStyle = "code_style"
        case errorHandling = "error_handling"
        case projectType = "project_type"
        case communication = "communication"
        case general = "general"
        
        var displayName: String {
            switch self {
            case .responseStyle: return "Response Style"
            case .codeStyle: return "Code Style"
            case .errorHandling: return "Error Handling"
            case .projectType: return "Project Type"
            case .communication: return "Communication"
            case .general: return "General"
            }
        }
    }
}

// MARK: - Error Solution Pair
@Model
class ErrorSolutionPair {
    var id: UUID = UUID()
    var errorMessage: String = ""
    var errorType: String = ""
    var fileName: String = ""
    var lineNumber: Int?
    var solution: String = ""
    var codeFix: String = ""
    var explanation: String = ""
    var projectName: String = ""
    var language: String = ""
    var successRate: Double = 1.0
    var usageCount: Int = 0
    var createdAt: Date = Date()
    var lastUsed: Date = Date()
    var tags: [String] = []
    
    init(errorMessage: String = "", errorType: String = "", fileName: String = "", solution: String = "", codeFix: String = "", explanation: String = "", projectName: String = "") {
        self.errorMessage = errorMessage
        self.errorType = errorType
        self.fileName = fileName
        self.solution = solution
        self.codeFix = codeFix
        self.explanation = explanation
        self.projectName = projectName
        self.createdAt = Date()
        self.lastUsed = Date()
    }
}

// MARK: - Code Pattern
@Model
class CodePattern {
    var id: UUID = UUID()
    var patternName: String = ""
    var patternType: CodePattern.PatternType = CodePattern.PatternType.architectural
    var code: String = ""
    var patternDescription: String = ""
    var useCase: String = ""
    var language: String = ""
    var projectName: String = ""
    var usageCount: Int = 0
    var successRate: Double = 1.0
    var tags: [String] = []
    var createdAt: Date = Date()
    var lastUsed: Date = Date()
    
    init(patternName: String = "", patternType: PatternType = .architectural, code: String = "", patternDescription: String = "", useCase: String = "", language: String = "", projectName: String = "") {
        self.patternName = patternName
        self.patternType = patternType
        self.code = code
        self.patternDescription = patternDescription
        self.useCase = useCase
        self.language = language
        self.projectName = projectName
        self.createdAt = Date()
        self.lastUsed = Date()
    }
    
    enum PatternType: String, CaseIterable, Codable {
        case architectural = "architectural"
        case design = "design"
        case idiomatic = "idiomatic"
        case optimization = "optimization"
        case errorHandling = "error_handling"
        
        var displayName: String {
            switch self {
            case .architectural: return "Architectural"
            case .design: return "Design"
            case .idiomatic: return "Idiomatic"
            case .optimization: return "Optimization"
            case .errorHandling: return "Error Handling"
            }
        }
    }
}

// MARK: - Workflow Memory
@Model
class WorkflowMemory {
    var id: UUID = UUID()
    var workflowName: String = ""
    var steps: [String] = []
    var context: String = ""
    var projectName: String = ""
    var frequency: Int = 0
    var successRate: Double = 1.0
    var averageDuration: TimeInterval = 0.0
    var lastUsed: Date = Date()
    var createdAt: Date = Date()
    var tags: [String] = []
    
    init(workflowName: String = "", steps: [String] = [], context: String = "", projectName: String = "") {
        self.workflowName = workflowName
        self.steps = steps
        self.context = context
        self.projectName = projectName
        self.createdAt = Date()
        self.lastUsed = Date()
    }
}

// MARK: - Session Summary
@Model
class SessionSummary {
    var id: UUID = UUID()
    var sessionDate: Date = Date()
    var duration: TimeInterval = 0.0
    var interactionCount: Int = 0
    var errorCount: Int = 0
    var solutionCount: Int = 0
    var projectWorkedOn: [String] = []
    var technologiesUsed: [String] = []
    var successRate: Double = 1.0
    var userSatisfaction: Double = 0.0
    var keyTopics: [String] = []
    var notes: String = ""
    
    init(sessionDate: Date = Date(), interactionCount: Int = 0, errorCount: Int = 0, solutionCount: Int = 0, notes: String = "") {
        self.sessionDate = sessionDate
        self.interactionCount = interactionCount
        self.errorCount = errorCount
        self.solutionCount = solutionCount
        self.notes = notes
    }
}
