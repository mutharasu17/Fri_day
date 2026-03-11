import Foundation
import SwiftData
import Combine
import CoreData

// MARK: - Core Long-Term Memory Manager
class LongTermMemoryManager: ObservableObject {
    // MARK: - Properties
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    @Published var isInitialized = false
    @Published var memoryCount = 0
    @Published var projectCount = 0
    
    // MARK: - Initialization
    init() {
        do {
            // ── SHARED BRAIN PATH ───────────────────────────────────────────────
            // Both the Mac app (SwiftData) and the Python iMessage agent (sqlite3)
            // read/write to this same file so FRIDAY has one memory across both.
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let fridayDir = appSupport.appendingPathComponent("FRIDAY")
            try? FileManager.default.createDirectory(
                at: fridayDir, withIntermediateDirectories: true
            )
            let sharedDBURL = fridayDir.appendingPathComponent("FridayMemory.sqlite")
            // ────────────────────────────────────────────────────────────────────
            
            let schema = Schema([
                MemoryEntity.self,
                ProjectMemory.self,
                UserPreference.self,
                ErrorSolutionPair.self,
                CodePattern.self,
                WorkflowMemory.self,
                SessionSummary.self
            ])
            
            // No CloudKit — keeps the file local & accessible to the Python agent
            let config = ModelConfiguration(
                "FridayMemory",
                schema: schema,
                url: sharedDBURL,
                cloudKitDatabase: .none
            )
            
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
            self.modelContext = modelContainer.mainContext
            
            print("[Memory] Shared brain: \(sharedDBURL.path)")
            
            setupNotifications()
            Task { await initializeDefaultData() }
            
        } catch {
            print("[Memory] Failed to initialize SwiftData: \(error)")
            fatalError("Could not initialize memory system: \(error)")
        }
    }
    
    // MARK: - Core Memory Operations
    
    /// Store a new memory entity
    func storeMemory(
        content: String,
        type: MemoryEntity.MemoryType,
        tags: [String] = [],
        projectName: String = "",
        fileName: String = "",
        language: String = "",
        errorType: String = "",
        importance: Double = 0.5
    ) {
        let memory = MemoryEntity(type: type, content: content)
        memory.content = content
        memory.type = type
        memory.tags = tags
        memory.projectName = projectName
        memory.fileName = fileName
        memory.language = language
        memory.errorType = errorType
        memory.importance = importance
        memory.summary = generateSummary(from: content)
        memory.timestamp = Date()
        memory.lastAccessed = Date()
        
        // Calculate importance if not provided
        if importance == 0.5 {
            memory.importance = calculateImportance(memory)
        }
        
        // Save to SwiftData
        modelContext.insert(memory)
        saveContext()
        
        print("[Memory] Stored \(type.displayName): \(content.prefix(50))...")
    }
    
    /// Store an error-solution pair
    func storeErrorSolution(
        error: String,
        errorType: String,
        solution: String,
        codeFix: String = "",
        explanation: String = "",
        fileName: String = "",
        projectName: String = "",
        language: String = ""
    ) {
        // Check if similar solution exists
        if let existing = findSimilarErrorSolution(error: error) {
            existing.usageCount += 1
            existing.lastUsed = Date()
            existing.successRate = (existing.successRate + 1.0) / 2.0
        } else {
            let errorSolution = ErrorSolutionPair(errorMessage: error, errorType: errorType, solution: solution)
            errorSolution.codeFix = codeFix
            errorSolution.explanation = explanation
            errorSolution.fileName = fileName
            errorSolution.projectName = projectName
            errorSolution.language = language
            errorSolution.createdAt = Date()
            errorSolution.lastUsed = Date()
            errorSolution.tags = generateErrorTags(error: error, fileName: fileName)
            modelContext.insert(errorSolution)
        }
        
        saveContext()
        print("[Memory] Stored error solution: \(error.prefix(50))...")
    }
    
    /// Store user preference
    func storeUserPreference(
        key: String,
        value: String,
        category: UserPreference.PreferenceCategory = .general,
        confidence: Double = 1.0
    ) {
        // Check if preference exists
        let fetchDescriptor = FetchDescriptor<UserPreference>(
            predicate: #Predicate<UserPreference> { $0.key == key }
        )
        
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            existing.value = value
            existing.updatedAt = Date()
            existing.accessCount += 1
            existing.confidence = (existing.confidence + confidence) / 2.0
        } else {
            let preference = UserPreference(key: key, value: value, category: category)
            preference.confidence = confidence
            preference.createdAt = Date()
            preference.updatedAt = Date()
            preference.accessCount = 1
            modelContext.insert(preference)
        }
        
        saveContext()
        print("[Memory] Stored preference: \(key) = \(value)")
    }
    
    /// Store project information
    func storeProjectInfo(
        name: String,
        path: String,
        type: String,
        technologies: [String],
        architecture: String = ""
    ) {
        // Check if project exists
        let fetchDescriptor = FetchDescriptor<ProjectMemory>(
            predicate: #Predicate<ProjectMemory> { $0.projectName == name }
        )
        
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            existing.lastAccessed = Date()
            existing.technologies = technologies
            existing.architecture = architecture
            existing.isActive = true
        } else {
            let project = ProjectMemory(projectName: name, projectPath: path, projectType: type)
            project.technologies = technologies
            project.architecture = architecture
            project.createdAt = Date()
            project.lastAccessed = Date()
            project.isActive = true
            modelContext.insert(project)
        }
        
        saveContext()
        print("[Memory] Stored project: \(name)")
    }
    
    // MARK: - Memory Retrieval
    
    /// Search memories by content and tags
    func searchMemories(
        query: String,
        type: MemoryEntity.MemoryType? = nil,
        projectName: String? = nil,
        limit: Int = 10
    ) -> [MemoryEntity] {
        let typeRaw = type?.rawValue
        let projectNameValue = projectName ?? ""
        
        var fetchDescriptor = FetchDescriptor<MemoryEntity>(
            predicate: #Predicate<MemoryEntity> { memory in
                (query == "" || memory.content.contains(query)) &&
                (projectNameValue == "" || memory.projectName == projectNameValue)
            },
            sortBy: [SortDescriptor(\.importance, order: .reverse), SortDescriptor(\.lastAccessed, order: .reverse)]
        )
        fetchDescriptor.fetchLimit = limit
        
        do {
            let memories = try modelContext.fetch(fetchDescriptor)
            for memory in memories {
                memory.accessCount += 1
                memory.lastAccessed = Date()
            }
            saveContext()
            return memories
        } catch {
            print("[Memory] Search failed: \(error)")
            return []
        }
    }
    
    /// Get error solutions for specific error
    func getErrorSolutions(for error: String, projectName: String? = nil) -> [ErrorSolutionPair] {
        let lowerError = error.lowercased()
        let projectNameValue = projectName ?? ""
        
        let fetchDescriptor = FetchDescriptor<ErrorSolutionPair>(
            predicate: #Predicate<ErrorSolutionPair> { solution in
                (projectNameValue == "" || solution.projectName == projectNameValue) &&
                solution.errorMessage.contains(lowerError)
            },
            sortBy: [SortDescriptor(\.successRate, order: .reverse), SortDescriptor(\.usageCount, order: .reverse)]
        )
        
        do {
            let solutions = try modelContext.fetch(fetchDescriptor)
            for solution in solutions {
                solution.usageCount += 1
                solution.lastUsed = Date()
            }
            saveContext()
            return solutions
        } catch {
            print("[Memory] Error solution search failed: \(error)")
            return []
        }
    }
    
    /// Get user preferences
    func getUserPreferences(category: UserPreference.PreferenceCategory? = nil) -> [UserPreference] {
        let fetchDescriptor = FetchDescriptor<UserPreference>(
            predicate: category != nil ? #Predicate<UserPreference> { $0.category == category! } : nil,
            sortBy: [SortDescriptor(\.accessCount, order: .reverse)]
        )
        
        do {
            return try modelContext.fetch(fetchDescriptor)
        } catch {
            print("[Memory] Preference fetch failed: \(error)")
            return []
        }
    }
    
    /// Get user preference by key
    func getUserPreference(key: String) -> UserPreference? {
        let fetchDescriptor = FetchDescriptor<UserPreference>(
            predicate: #Predicate<UserPreference> { $0.key == key }
        )
        
        do {
            return try modelContext.fetch(fetchDescriptor).first
        } catch {
            print("[Memory] Preference fetch failed: \(error)")
            return nil
        }
    }
    
    // MARK: - Memory Management
    
    /// Get memory statistics
    func getMemoryStats() -> MemoryStats {
        do {
            let allMemories = try modelContext.fetch(FetchDescriptor<MemoryEntity>())
            let allProjects = try modelContext.fetch(FetchDescriptor<ProjectMemory>())
            let allErrorSolutions = try modelContext.fetch(FetchDescriptor<ErrorSolutionPair>())
            
            return MemoryStats(
                totalMemories: allMemories.count,
                totalProjects: allProjects.count,
                totalErrorSolutions: allErrorSolutions.count,
                memoriesByType: Dictionary(grouping: allMemories) { $0.type },
                activeProjects: allProjects.filter { $0.isActive }.count
            )
        } catch {
            print("[Memory] Stats fetch failed: \(error)")
            return MemoryStats()
        }
    }
    
    /// Export all memory data
    func exportAllData() -> MemoryExport? {
        do {
            let memories    = try modelContext.fetch(FetchDescriptor<MemoryEntity>())
            let projects    = try modelContext.fetch(FetchDescriptor<ProjectMemory>())
            let preferences = try modelContext.fetch(FetchDescriptor<UserPreference>())
            return MemoryExport(
                memories: memories,
                projects: projects,
                preferences: preferences,
                exportDate: Date()
            )
        } catch {
            print("[Memory] Export failed: \(error)")
            return nil
        }
    }

    /// Clean up old memories
    func cleanupOldMemories(olderThan days: Int = 30) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        
        let oldMemoriesDescriptor = FetchDescriptor<MemoryEntity>(
            predicate: #Predicate<MemoryEntity> { 
                $0.timestamp < cutoffDate && $0.importance < 0.3 
            }
        )
        
        do {
            let oldMemories = try modelContext.fetch(oldMemoriesDescriptor)
            for memory in oldMemories {
                modelContext.delete(memory)
            }
            if !oldMemories.isEmpty {
                saveContext()
                print("[Memory] Cleaned up \(oldMemories.count) old memories")
            }
        } catch {
            print("[Memory] Cleanup failed: \(error)")
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("[Memory] Save failed: \(error)")
            modelContext.rollback()
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"))
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateStats()
                }
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    @MainActor
    private func updateStats() {
        let stats = getMemoryStats()
        memoryCount = stats.totalMemories
        projectCount = stats.totalProjects
        isInitialized = true
    }
    
    private func initializeDefaultData() async {
        let fetchDescriptor = FetchDescriptor<MemoryEntity>()
        let existingCount = (try? modelContext.fetch(fetchDescriptor).count) ?? 0
        if existingCount == 0 {
            await createDefaultPreferences()
        }
        await MainActor.run {
            updateStats()
        }
    }
    
    private func createDefaultPreferences() async {
        let defaultPreferences: [(key: String, value: String, category: UserPreference.PreferenceCategory)] = [
            ("response_style", "friendly", .responseStyle),
            ("code_style", "swift", .codeStyle),
            ("error_handling", "detailed", .errorHandling)
        ]
        for pref in defaultPreferences {
            storeUserPreference(key: pref.key, value: pref.value, category: pref.category)
        }
    }
    
    private func calculateImportance(_ memory: MemoryEntity) -> Double {
        var score = 0.0
        if memory.type == .errorSolution { score += 0.8 }
        if memory.type == .userPreference { score += 0.9 }
        if memory.type == .codePattern { score += 0.6 }
        if memory.type == .projectInfo { score += 0.7 }
        if memory.content.contains("error") && memory.content.contains("solution") { score += 0.3 }
        return min(score, 1.0)
    }
    
    private func generateSummary(from content: String) -> String {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        return words.prefix(10).joined(separator: " ")
    }
    
    private func generateErrorTags(error: String, fileName: String) -> [String] {
        var tags: [String] = []
        if error.contains("Cannot find") { tags.append("undefined") }
        if !fileName.isEmpty { tags.append(fileName) }
        return tags
    }
    
    private func findSimilarErrorSolution(error: String) -> ErrorSolutionPair? {
        let fetchDescriptor = FetchDescriptor<ErrorSolutionPair>(
            predicate: #Predicate<ErrorSolutionPair> { 
                $0.errorMessage.contains(error) || error.contains($0.errorMessage)
            },
            sortBy: [SortDescriptor(\.successRate, order: .reverse)]
        )
        return try? modelContext.fetch(fetchDescriptor).first
    }
}

// MARK: - Supporting Types
struct MemoryStats {
    let totalMemories: Int
    let totalProjects: Int
    let totalErrorSolutions: Int
    let memoriesByType: [MemoryEntity.MemoryType: [MemoryEntity]]
    let activeProjects: Int
    
    init(totalMemories: Int = 0, totalProjects: Int = 0, totalErrorSolutions: Int = 0, memoriesByType: [MemoryEntity.MemoryType: [MemoryEntity]] = [:], activeProjects: Int = 0) {
        self.totalMemories = totalMemories
        self.totalProjects = totalProjects
        self.totalErrorSolutions = totalErrorSolutions
        self.memoriesByType = memoriesByType
        self.activeProjects = activeProjects
    }
}

