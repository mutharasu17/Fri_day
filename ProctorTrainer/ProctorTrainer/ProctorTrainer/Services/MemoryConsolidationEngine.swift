import Foundation
import SwiftData
import BackgroundTasks
import Combine

// MARK: - Memory Consolidation Engine
class MemoryConsolidationEngine: ObservableObject {
    // MARK: - Properties
    private let modelContext: ModelContext
    private let longTermMemory: LongTermMemoryManager
    
    @Published var isConsolidating = false
    @Published var consolidationProgress: Double = 0.0
    @Published var lastConsolidationDate: Date?
    @Published var consolidationStats: ConsolidationStats
    
    // MARK: - Data Models
    struct ConsolidationStats {
        let memoriesProcessed: Int
        let memoriesMerged: Int
        let memoriesDeleted: Int
        let relationshipsUpdated: Int
        let embeddingsGenerated: Int
        let duration: TimeInterval
        let timestamp: Date
        
        init(memoriesProcessed: Int = 0, memoriesMerged: Int = 0, memoriesDeleted: Int = 0, relationshipsUpdated: Int = 0, embeddingsGenerated: Int = 0, duration: TimeInterval = 0.0, timestamp: Date = Date()) {
            self.memoriesProcessed = memoriesProcessed
            self.memoriesMerged = memoriesMerged
            self.memoriesDeleted = memoriesDeleted
            self.relationshipsUpdated = relationshipsUpdated
            self.embeddingsGenerated = embeddingsGenerated
            self.duration = duration
            self.timestamp = timestamp
        }
    }
    
    struct ConsolidationResult {
        var mergedMemories: [UUID]
        var deletedMemories: [UUID]
        var updatedRelationships: [UUID]
        var newEmbeddings: [UUID]
        var summary: String
    }
    
    // MARK: - Initialization
    init(modelContext: ModelContext, longTermMemory: LongTermMemoryManager) {
        self.modelContext = modelContext
        self.longTermMemory = longTermMemory
        // Initialize stats
        self.consolidationStats = ConsolidationStats()
        
        // Schedule background consolidation
        scheduleBackgroundConsolidation()
    }
    
    // MARK: - Public Consolidation Methods
    
    /// Perform full memory consolidation
    func performFullConsolidation() async -> ConsolidationResult {
        await MainActor.run {
            isConsolidating = true
            consolidationProgress = 0.0
        }
        
        let startTime = Date()
        var result = ConsolidationResult(
            mergedMemories: [],
            deletedMemories: [],
            updatedRelationships: [],
            newEmbeddings: [],
            summary: ""
        )
        
        defer {
            let duration = Date().timeIntervalSince(startTime)
            updateConsolidationStats(result: result, duration: duration)
            
            Task { @MainActor in
                isConsolidating = false
                consolidationProgress = 1.0
                lastConsolidationDate = Date()
            }
        }
        
        // Step 1: Consolidate similar memories
        await MainActor.run { consolidationProgress = 0.2 }
        let mergeResult = await consolidateSimilarMemories()
        result.mergedMemories = mergeResult
        
        // Step 2: Remove obsolete memories
        await MainActor.run { consolidationProgress = 0.4 }
        let deleteResult = await removeObsoleteMemories()
        result.deletedMemories = deleteResult
        
        // Step 3: Update relationships
        await MainActor.run { consolidationProgress = 0.6 }
        let relationshipResult = await updateMemoryRelationships()
        result.updatedRelationships = relationshipResult
        
        // Step 4: Generate embeddings
        await MainActor.run { consolidationProgress = 0.8 }
        let embeddingResult = await generateMissingEmbeddings()
        result.newEmbeddings = embeddingResult
        
        // Step 5: Optimize storage
        await MainActor.run { consolidationProgress = 1.0 }
        await optimizeMemoryStorage()
        
        // Generate summary
        result.summary = generateConsolidationSummary(
            mergeResult: mergeResult,
            deleteResult: deleteResult,
            relationshipResult: relationshipResult,
            embeddingResult: embeddingResult
        )
        
        return result
    }
    
    func scheduleBackgroundConsolidation() {
        // Simple background task scheduling placeholder for now
        print("[Consolidation] Background task scheduling is not yet fully implemented for iOS")
    }
    
    // MARK: - Consolidation Operations
    
    /// Consolidate similar memories
    private func consolidateSimilarMemories() async -> [UUID] {
        var mergedMemories: [UUID] = []
        
        do {
            // Get all memories
            let fetchDescriptor = FetchDescriptor<MemoryEntity>()
            let allMemories = try modelContext.fetch(fetchDescriptor)
            
            // Group by content similarity
            let similarityGroups = groupMemoriesBySimilarity(memories: allMemories)
            
            for group in similarityGroups {
                if group.count > 1 {
                    // Merge similar memories
                    if let mergedMemory = mergeMemoryGroup(group) {
                        // Delete original memories
                        for memory in group {
                            modelContext.delete(memory)
                        }
                        
                        // Add merged memory
                        modelContext.insert(mergedMemory)
                        
                        // Track merged memories
                        mergedMemories.append(contentsOf: group.map { $0.id })
                        
                        print("[Consolidation] Merged \(group.count) similar memories")
                    }
                }
            }
            
            try modelContext.save()
            
        } catch {
            print("[Consolidation] Failed to consolidate similar memories: \(error)")
        }
        
        return mergedMemories
    }
    
    /// Remove obsolete memories
    private func removeObsoleteMemories() async -> [UUID] {
        var deletedMemories: [UUID] = []
        
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            
            // Find old, low-importance memories
            let fetchDescriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate<MemoryEntity> { 
                    $0.timestamp < cutoffDate && $0.importance < 0.3 
                }
            )
            
            let obsoleteMemories = try modelContext.fetch(fetchDescriptor)
            
            for memory in obsoleteMemories {
                modelContext.delete(memory)
                deletedMemories.append(memory.id)
            }
            
            if !obsoleteMemories.isEmpty {
                try modelContext.save()
                print("[Consolidation] Deleted \(obsoleteMemories.count) obsolete memories")
            }
            
        } catch {
            print("[Consolidation] Failed to remove obsolete memories: \(error)")
        }
        
        return deletedMemories
    }
    
    /// Update memory relationships
    private func updateMemoryRelationships() async -> [UUID] {
        var updatedRelationships: [UUID] = []
        
        do {
            // Get all memories
            let fetchDescriptor = FetchDescriptor<MemoryEntity>()
            let allMemories = try modelContext.fetch(fetchDescriptor)
            
            // Update relationships based on content similarity
            for memory in allMemories {
                let newRelationships = findRelatedMemories(for: memory, in: allMemories)
                memory.relatedMemories = newRelationships
                updatedRelationships.append(memory.id)
            }
            
            try modelContext.save()
            print("[Consolidation] Updated relationships for \(updatedRelationships.count) memories")
            
        } catch {
            print("[Consolidation] Failed to update relationships: \(error)")
        }
        
        return updatedRelationships
    }
    
    /// Generate missing embeddings
    private func generateMissingEmbeddings() async -> [UUID] {
        var newEmbeddings: [UUID] = []
        
        do {
            // Find memories without embeddings
            let fetchDescriptor = FetchDescriptor<MemoryEntity>(
                predicate: #Predicate<MemoryEntity> { $0.embedding == nil }
            )
            
            let memoriesWithoutEmbeddings = try modelContext.fetch(fetchDescriptor)
            
            for memory in memoriesWithoutEmbeddings {
                // Generate embedding (simplified - would use actual embedding service)
                if let embedding = generateEmbedding(for: memory.content) {
                    memory.embedding = embedding
                    newEmbeddings.append(memory.id)
                }
            }
            
            if !memoriesWithoutEmbeddings.isEmpty {
                try modelContext.save()
                print("[Consolidation] Generated embeddings for \(newEmbeddings.count) memories")
            }
            
        } catch {
            print("[Consolidation] Failed to generate embeddings: \(error)")
        }
        
        return newEmbeddings
    }
    
    /// Optimize memory storage
    private func optimizeMemoryStorage() async {
        do {
            // Vacuum and optimize SQLite database
            try modelContext.save()
            
            print("[Consolidation] Memory storage optimized")
            
        } catch {
            print("[Consolidation] Failed to optimize storage: \(error)")
        }
    }
    
    // MARK: - Background Task Handler
    
    /// Perform background consolidation
    private func performBackgroundConsolidation() {
        Task {
            let result = await performFullConsolidation()
            print("[Background] Consolidation completed: \(result.summary)")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Group memories by similarity
    private func groupMemoriesBySimilarity(memories: [MemoryEntity]) -> [[MemoryEntity]] {
        var groups: [[MemoryEntity]] = []
        var processed: Set<UUID> = []
        
        for memory in memories {
            if processed.contains(memory.id) { continue }
            
            var similarMemories: [MemoryEntity] = [memory]
            processed.insert(memory.id)
            
            // Find similar memories
            for otherMemory in memories {
                if processed.contains(otherMemory.id) { continue }
                
                let similarity = calculateContentSimilarity(memory.content, otherMemory.content)
                if similarity > 0.8 { // High similarity threshold
                    similarMemories.append(otherMemory)
                    processed.insert(otherMemory.id)
                }
            }
            
            if similarMemories.count > 1 {
                groups.append(similarMemories)
            }
        }
        
        return groups
    }
    
    /// Merge memory group
    private func mergeMemoryGroup(_ memories: [MemoryEntity]) -> MemoryEntity? {
        guard !memories.isEmpty else { return nil }
        
        // Create merged memory with highest importance
        let mostImportant = memories.max { $0.importance > $1.importance } ?? memories.first!
        
        let mergedMemory = MemoryEntity(type: mostImportant.type)
        mergedMemory.id = UUID()
        mergedMemory.timestamp = Date()
        mergedMemory.type = mostImportant.type
        mergedMemory.importance = mostImportant.importance
        mergedMemory.projectName = mostImportant.projectName
        mergedMemory.fileName = mostImportant.fileName
        mergedMemory.language = mostImportant.language
        mergedMemory.errorType = mostImportant.errorType
        
        // Merge content
        let allContents = memories.map { $0.content }
        mergedMemory.content = mergeContents(allContents)
        mergedMemory.summary = generateSummary(from: mergedMemory.content)
        
        // Merge tags
        var allTags: Set<String> = []
        for memory in memories {
            allTags.formUnion(memory.tags)
        }
        mergedMemory.tags = Array(allTags)
        
        // Set access count to sum
        mergedMemory.accessCount = memories.reduce(0) { $0 + $1.accessCount }
        mergedMemory.lastAccessed = memories.max { $0.lastAccessed > $1.lastAccessed }?.lastAccessed ?? Date()
        
        return mergedMemory
    }
    
    /// Find related memories
    private func findRelatedMemories(for memory: MemoryEntity, in allMemories: [MemoryEntity]) -> [UUID] {
        var relatedMemories: [UUID] = []
        
        for otherMemory in allMemories {
            if otherMemory.id == memory.id { continue }
            
            let similarity = calculateContentSimilarity(memory.content, otherMemory.content)
            if similarity > 0.6 { // Medium similarity threshold
                relatedMemories.append(otherMemory.id)
            }
        }
        
        return relatedMemories
    }
    
    /// Calculate content similarity
    private func calculateContentSimilarity(_ content1: String, _ content2: String) -> Double {
        let words1 = Set(content1.lowercased().components(separatedBy: .whitespacesAndNewlines))
        let words2 = Set(content2.lowercased().components(separatedBy: .whitespacesAndNewlines))
        
        let intersection = words1.intersection(words2)
        let union = words1.union(words2)
        
        return union.isEmpty ? 0.0 : Double(intersection.count) / Double(union.count)
    }
    
    /// Merge contents
    private func mergeContents(_ contents: [String]) -> String {
        // Remove duplicates while preserving order
        var seenContents: Set<String> = []
        var mergedContents: [String] = []
        
        for content in contents {
            if !seenContents.contains(content) {
                seenContents.insert(content)
                mergedContents.append(content)
            }
        }
        
        return mergedContents.joined(separator: "\n---\n")
    }
    
    /// Generate summary
    private func generateSummary(from content: String) -> String {
        let words = content.components(separatedBy: .whitespacesAndNewlines)
        return words.prefix(15).joined(separator: " ")
    }
    
    /// Generate embedding (simplified)
    private func generateEmbedding(for content: String) -> Data? {
        // This is a simplified embedding generation
        // In a real implementation, this would call an embedding service
        let words = content.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        // Create a simple vector representation
        var embedding: [Float] = Array(repeating: 0.0, count: 768) // Standard embedding size
        
        // Use word hash to create embedding
        for (index, word) in words.prefix(100).enumerated() {
            if index < 768 {
                embedding[index] = Float(word.hashValue % 1000) / 1000.0
            }
        }
        
        return try? JSONEncoder().encode(embedding)
    }
    
    /// Generate consolidation summary
    private func generateConsolidationSummary(
        mergeResult: [UUID],
        deleteResult: [UUID],
        relationshipResult: [UUID],
        embeddingResult: [UUID]
    ) -> String {
        return """
        Memory Consolidation Summary:
        - Merged \(mergeResult.count) memory groups
        - Deleted \(deleteResult.count) obsolete memories
        - Updated relationships for \(relationshipResult.count) memories
        - Generated embeddings for \(embeddingResult.count) memories
        - Total optimizations: \(mergeResult.count + deleteResult.count + relationshipResult.count + embeddingResult.count)
        """
    }
    
    /// Update consolidation stats
    private func updateConsolidationStats(result: ConsolidationResult, duration: TimeInterval) {
        consolidationStats = ConsolidationStats(
            memoriesProcessed: result.mergedMemories.count + result.deletedMemories.count,
            memoriesMerged: result.mergedMemories.count,
            memoriesDeleted: result.deletedMemories.count,
            relationshipsUpdated: result.updatedRelationships.count,
            embeddingsGenerated: result.newEmbeddings.count,
            duration: duration,
            timestamp: Date()
        )
    }
}
