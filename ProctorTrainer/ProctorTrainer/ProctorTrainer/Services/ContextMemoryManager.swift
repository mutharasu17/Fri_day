import Foundation
import Combine

// MARK: - Context Memory Manager
class ContextMemoryManager: ObservableObject {
    // MARK: - Properties
    @Published var currentProject: ProjectContext
    @Published var activeFile: FileContext
    @Published var workspaceState: WorkspaceState
    @Published var recentFiles: [FileContext] = []
    @Published var fileHistory: [FileTransition] = []
    
    private let maxRecentFiles = 10
    private let maxFileHistory = 50
    
    // MARK: - Nested Type Aliases
    // Swift can't find short names for types nested inside nested structs.
    // These aliases make them accessible throughout the class body.
    private typealias Position           = FileContext.Position
    private typealias TerminalState      = WorkspaceState.TerminalState
    private typealias DebugState         = WorkspaceState.DebugState
    private typealias GitState           = WorkspaceState.GitState
    private typealias GitStatus          = WorkspaceState.GitState.GitStatus
    typealias ProjectType        = ProjectContext.ProjectType
    typealias ArchitecturePattern = ProjectContext.ArchitecturePattern

    // MARK: - Data Models
    struct ProjectContext {
        let name: String
        let path: String
        let type: ProjectType
        let technologies: [String]
        let architecture: ArchitecturePattern
        let lastModified: Date
        let complexity: ProjectComplexity
        let gitBranch: String?
        let buildStatus: BuildStatus
        
        enum ProjectType: String, CaseIterable {
            case ios = "ios"
            case macos = "macos"
            case web = "web"
            case mobile = "mobile"
            case desktop = "desktop"
            case server = "server"
            case library = "library"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .ios: return "iOS App"
                case .macos: return "macOS App"
                case .web: return "Web App"
                case .mobile: return "Mobile App"
                case .desktop: return "Desktop App"
                case .server: return "Server App"
                case .library: return "Library/Framework"
                case .unknown: return "Unknown"
                }
            }
        }
        
        enum ArchitecturePattern: String, CaseIterable {
            case mvc = "mvc"
            case mvvm = "mvvm"
            case mvp = "mvp"
            case clean = "clean"
            case modular = "modular"
            case microservices = "microservices"
            case monolith = "monolith"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .mvc: return "MVC"
                case .mvvm: return "MVVM"
                case .mvp: return "MVP"
                case .clean: return "Clean Architecture"
                case .modular: return "Modular"
                case .microservices: return "Microservices"
                case .monolith: return "Monolith"
                case .unknown: return "Unknown"
                }
            }
        }
        
        enum ProjectComplexity: String, CaseIterable {
            case simple = "simple"
            case moderate = "moderate"
            case complex = "complex"
            case enterprise = "enterprise"
            
            var displayName: String {
                switch self {
                case .simple: return "Simple"
                case .moderate: return "Moderate"
                case .complex: return "Complex"
                case .enterprise: return "Enterprise"
                }
            }
        }
        
        enum BuildStatus: String, CaseIterable {
            case success = "success"
            case failed = "failed"
            case building = "building"
            case unknown = "unknown"
            
            var displayName: String {
                switch self {
                case .success: return "Build Successful"
                case .failed: return "Build Failed"
                case .building: return "Building"
                case .unknown: return "Unknown"
                }
            }
        }
    }
    
    struct FileContext {
        let name: String
        let path: String
        let language: String
        let content: String
        let cursorPosition: Position
        let selectedText: String
        let modifications: [Modification]
        let complexity: FileComplexity
        let functionScope: String?
        let classScope: String?
        let lastModified: Date
        
        struct Position {
            let line: Int
            let column: Int
            let offset: Int
        }
        
        struct Modification {
            let type: ModificationType
            let timestamp: Date
            let content: String
            let line: Int?
            
            enum ModificationType: String, CaseIterable {
                case insert = "insert"
                case delete = "delete"
                case replace = "replace"
                case format = "format"
                case refactor = "refactor"
                
                var displayName: String {
                    switch self {
                    case .insert: return "Insert"
                    case .delete: return "Delete"
                    case .replace: return "Replace"
                    case .format: return "Format"
                    case .refactor: return "Refactor"
                    }
                }
            }
        }
        
        enum FileComplexity: String, CaseIterable {
            case simple = "simple"
            case moderate = "moderate"
            case complex = "complex"
            
            var displayName: String {
                switch self {
                case .simple: return "Simple"
                case .moderate: return "Moderate"
                case .complex: return "Complex"
                }
            }
        }
    }
    
    struct WorkspaceState {
        let ideType: String
        let openTabs: [String]
        let activeTab: String?
        let terminalState: TerminalState
        let debugState: DebugState
        let gitState: GitState
        
        struct TerminalState {
            let isActive: Bool
            let currentDirectory: String
            let lastCommand: String?
            let output: String?
        }
        
        struct DebugState {
            let isDebugging: Bool
            let breakpoints: [Breakpoint]
            let currentStack: [StackFrame]
            let variables: [Variable]
            
            struct Breakpoint {
                let file: String
                let line: Int
                let enabled: Bool
                let condition: String?
            }
            
            struct StackFrame {
                let function: String
                let file: String
                let line: Int
            }
            
            struct Variable {
                let name: String
                let value: String
                let type: String
            }
        }
        
        struct GitState {
            let branch: String
            let status: GitStatus
            let stagedFiles: [String]
            let modifiedFiles: [String]
            let untrackedFiles: [String]
            
            enum GitStatus: String, CaseIterable {
                case clean = "clean"
                case modified = "modified"
                case staged = "staged"
                case conflict = "conflict"
                
                var displayName: String {
                    switch self {
                    case .clean: return "Clean"
                    case .modified: return "Modified"
                    case .staged: return "Staged"
                    case .conflict: return "Conflict"
                    }
                }
            }
        }
    }
    
    struct FileTransition {
        let fromFile: String?
        let toFile: String
        let timestamp: Date
        let reason: TransitionReason
        let duration: TimeInterval
        
        enum TransitionReason: String, CaseIterable {
            case userNavigation = "user_navigation"
            case errorJump = "error_jump"
            case search = "search"
            case debug = "debug"
            case refactoring = "refactoring"
            
            var displayName: String {
                switch self {
                case .userNavigation: return "User Navigation"
                case .errorJump: return "Error Jump"
                case .search: return "Search"
                case .debug: return "Debug"
                case .refactoring: return "Refactoring"
                }
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        self.currentProject = ProjectContext(
            name: "",
            path: "",
            type: .unknown,
            technologies: [],
            architecture: .unknown,
            lastModified: Date(),
            complexity: .simple,
            gitBranch: nil as String?,   // explicit type so nil resolves correctly
            buildStatus: .unknown
        )
        
        self.activeFile = FileContext(
            name: "",
            path: "",
            language: "",
            content: "",
            cursorPosition: FileContext.Position(line: 1, column: 1, offset: 0),
            selectedText: "",
            modifications: [],
            complexity: .simple,
            functionScope: nil as String?,
            classScope: nil as String?,
            lastModified: Date()
        )
        
        self.workspaceState = WorkspaceState(
            ideType: "",
            openTabs: [],
            activeTab: nil as String?,
            terminalState: WorkspaceState.TerminalState(
                isActive: false,
                currentDirectory: "",
                lastCommand: nil as String?,
                output: nil as String?
            ),
            debugState: WorkspaceState.DebugState(
                isDebugging: false,
                breakpoints: [],
                currentStack: [],
                variables: []
            ),
            gitState: WorkspaceState.GitState(
                branch: "",
                status: WorkspaceState.GitState.GitStatus.clean,
                stagedFiles: [],
                modifiedFiles: [],
                untrackedFiles: []
            )
        )
    }
    
    // MARK: - Project Context Management
    
    /// Update project context
    func updateProjectContext(
        name: String,
        path: String,
        type: ProjectType,
        technologies: [String],
        architecture: ArchitecturePattern = .unknown
    ) {
        let newContext = ProjectContext(
            name: name,
            path: path,
            type: type,
            technologies: technologies,
            architecture: architecture,
            lastModified: Date(),
            complexity: determineProjectComplexity(technologies: technologies, architecture: architecture),
            gitBranch: getGitBranch(path: path),
            buildStatus: currentProject.buildStatus
        )
        
        currentProject = newContext
        
        print("[Context] Updated project: \(name) (\(type.displayName))")
    }
    
    /// Update build status
    func updateBuildStatus(_ status: ProjectContext.BuildStatus) {
        currentProject = ProjectContext(
            name: currentProject.name,
            path: currentProject.path,
            type: currentProject.type,
            technologies: currentProject.technologies,
            architecture: currentProject.architecture,
            lastModified: currentProject.lastModified,
            complexity: currentProject.complexity,
            gitBranch: currentProject.gitBranch,
            buildStatus: status
        )
        
        print("[Context] Build status: \(status.displayName)")
    }
    
    // MARK: - File Context Management
    
    /// Update active file context
    func updateActiveFile(
        name: String,
        path: String,
        language: String,
        content: String,
        cursorLine: Int = 1,
        cursorColumn: Int = 1,
        selectedText: String = ""
    ) {
        let previousFile = activeFile
        
        let newFile = FileContext(
            name: name,
            path: path,
            language: language,
            content: content,
            cursorPosition: Position(line: cursorLine, column: cursorColumn, offset: 0),
            selectedText: selectedText,
            modifications: previousFile.modifications,
            complexity: determineFileComplexity(content: content, language: language),
            functionScope: extractFunctionScope(content: content, cursorLine: cursorLine),
            classScope: extractClassScope(content: content, cursorLine: cursorLine),
            lastModified: Date()
        )
        
        // Record file transition
        if previousFile.name != name {
            recordFileTransition(from: previousFile.name, to: name)
        }
        
        // Update recent files
        updateRecentFiles(newFile)
        
        activeFile = newFile
        
        print("[Context] Active file: \(name) (\(language))")
    }
    
    /// Record file modification
    func recordModification(
        type: FileContext.Modification.ModificationType,
        content: String,
        line: Int? = nil
    ) {
        let modification = FileContext.Modification(
            type: type,
            timestamp: Date(),
            content: content,
            line: line
        )
        
        var updatedModifications = activeFile.modifications
        updatedModifications.append(modification)
        
        // Keep only recent modifications (last 20)
        if updatedModifications.count > 20 {
            updatedModifications.removeFirst(updatedModifications.count - 20)
        }
        
        activeFile = FileContext(
            name: activeFile.name,
            path: activeFile.path,
            language: activeFile.language,
            content: activeFile.content,
            cursorPosition: activeFile.cursorPosition,
            selectedText: activeFile.selectedText,
            modifications: updatedModifications,
            complexity: activeFile.complexity,
            functionScope: activeFile.functionScope,
            classScope: activeFile.classScope,
            lastModified: Date()
        )
        
        print("[Context] File modification: \(type.displayName)")
    }
    
    // MARK: - Workspace State Management
    
    /// Update workspace state
    func updateWorkspaceState(
        ideType: String,
        openTabs: [String] = [],
        activeTab: String? = nil
    ) {
        workspaceState = WorkspaceState(
            ideType: ideType,
            openTabs: openTabs,
            activeTab: activeTab,
            terminalState: workspaceState.terminalState,
            debugState: workspaceState.debugState,
            gitState: workspaceState.gitState
        )
        
        print("[Context] IDE: \(ideType)")
    }
    
    /// Update terminal state
    func updateTerminalState(
        isActive: Bool,
        currentDirectory: String = "",
        lastCommand: String? = nil,
        output: String? = nil
    ) {
        workspaceState = WorkspaceState(
            ideType: workspaceState.ideType,
            openTabs: workspaceState.openTabs,
            activeTab: workspaceState.activeTab,
            terminalState: WorkspaceState.TerminalState(
                isActive: isActive,
                currentDirectory: currentDirectory,
                lastCommand: lastCommand,
                output: output
            ),
            debugState: workspaceState.debugState,
            gitState: workspaceState.gitState
        )
    }
    
    // MARK: - Context Retrieval
    
    /// Get current context summary
    func getCurrentContextSummary() -> ContextSummary {
        return ContextSummary(
            project: currentProject,
            activeFile: activeFile,
            workspace: workspaceState,
            recentFiles: recentFiles,
            sessionDuration: Date().timeIntervalSince(activeFile.lastModified),
            activityLevel: calculateActivityLevel()
        )
    }
    
    /// Get context for memory storage
    func getMemoryContext() -> String {
        return """
        Project: \(currentProject.name) (\(currentProject.type.displayName))
        File: \(activeFile.name) (\(activeFile.language))
        IDE: \(workspaceState.ideType)
        Task: Working on \(activeFile.functionScope ?? "unknown function")
        """
    }
    
    // MARK: - Private Helper Methods
    
    private func recordFileTransition(from: String?, to: String) {
        let transition = FileTransition(
            fromFile: from,
            toFile: to,
            timestamp: Date(),
            reason: .userNavigation,
            duration: 0.0
        )
        
        fileHistory.append(transition)
        
        // Keep only recent history
        if fileHistory.count > maxFileHistory {
            fileHistory.removeFirst()
        }
    }
    
    private func updateRecentFiles(_ file: FileContext) {
        // Remove if already exists
        recentFiles.removeAll { $0.name == file.name }
        
        // Add to front
        recentFiles.insert(file, at: 0)
        
        // Keep only recent files
        if recentFiles.count > maxRecentFiles {
            recentFiles.removeLast()
        }
    }
    
    private func determineProjectComplexity(
        technologies: [String],
        architecture: ProjectContext.ArchitecturePattern
    ) -> ProjectContext.ProjectComplexity {
        let techCount = technologies.count
        let archComplexity = architecture == .microservices ? 3 : 
                           architecture == .clean ? 2 : 1
        
        let score = techCount + archComplexity
        
        switch score {
        case 0...2: return .simple
        case 3...5: return .moderate
        case 6...8: return .complex
        default: return .enterprise
        }
    }
    
    private func determineFileComplexity(content: String, language: String) -> FileContext.FileComplexity {
        let lines = content.components(separatedBy: .newlines)
        let lineCount = lines.count
        
        // Count complexity indicators
        let nestedLoops = lines.filter { $0.contains("for") && $0.contains("for") }.count
        let conditionals = lines.filter { $0.contains("if") || $0.contains("switch") }.count
        let functions = lines.filter { $0.contains("func") || $0.contains("function") }.count
        
        let complexityScore = lineCount / 10 + nestedLoops * 2 + conditionals + functions
        
        switch complexityScore {
        case 0...5: return .simple
        case 6...15: return .moderate
        default: return .complex
        }
    }
    
    private func extractFunctionScope(content: String, cursorLine: Int) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard cursorLine > 0 && cursorLine <= lines.count else { return nil }
        
        // Search backwards from cursor line to find function
        for i in stride(from: cursorLine - 1, through: 0, by: -1) {
            let line = lines[i]
            if line.contains("func ") || line.contains("function ") {
                // Extract function name
                let components = line.components(separatedBy: .whitespacesAndNewlines)
                if let funcIndex = components.firstIndex(where: { $0.contains("func") || $0.contains("function") }) {
                    let funcComponent = components[funcIndex]
                    let nameParts = funcComponent.components(separatedBy: .whitespacesAndNewlines)
                    return nameParts.last?.replacingOccurrences(of: "(", with: "")
                }
            }
        }
        
        return nil
    }
    
    private func extractClassScope(content: String, cursorLine: Int) -> String? {
        let lines = content.components(separatedBy: .newlines)
        guard cursorLine > 0 && cursorLine <= lines.count else { return nil }
        
        // Search backwards from cursor line to find class
        for i in stride(from: cursorLine - 1, through: 0, by: -1) {
            let line = lines[i]
            if line.contains("class ") || line.contains("struct ") {
                // Extract class/struct name
                let components = line.components(separatedBy: .whitespacesAndNewlines)
                if let classIndex = components.firstIndex(where: { $0.contains("class") || $0.contains("struct") }) {
                    let classComponent = components[classIndex]
                    let nameParts = classComponent.components(separatedBy: .whitespacesAndNewlines)
                    return nameParts.last?.replacingOccurrences(of: ":", with: "")
                }
            }
        }
        
        return nil
    }
    
    private func getGitBranch(path: String) -> String? {
        // This would typically use git commands or Process to get current branch
        // For now, return nil as placeholder
        return nil
    }
    
    private func calculateActivityLevel() -> ContextSummary.ActivityLevel {
        let recentModifications = activeFile.modifications.filter { 
            $0.timestamp.timeIntervalSinceNow > -300 // Last 5 minutes
        }
        
        switch recentModifications.count {
        case 0...2: return .low
        case 3...8: return .medium
        case 9...15: return .high
        default: return .veryHigh
        }
    }
}

// MARK: - Supporting Types
struct ContextSummary {
    let project: ContextMemoryManager.ProjectContext
    let activeFile: ContextMemoryManager.FileContext
    let workspace: ContextMemoryManager.WorkspaceState
    let recentFiles: [ContextMemoryManager.FileContext]
    let sessionDuration: TimeInterval
    let activityLevel: ActivityLevel
    
    enum ActivityLevel: String, CaseIterable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        case veryHigh = "very_high"
        
        var displayName: String {
            switch self {
            case .low: return "Low Activity"
            case .medium: return "Medium Activity"
            case .high: return "High Activity"
            case .veryHigh: return "Very High Activity"
            }
        }
    }
}
