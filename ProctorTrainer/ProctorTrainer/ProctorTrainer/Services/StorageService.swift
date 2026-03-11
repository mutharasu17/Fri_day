import Foundation

@MainActor
class StorageService {
    static let shared = StorageService()
    
    private let fileManager = FileManager.default
    private var applicationSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let directory = paths[0].appendingPathComponent("FRIDAY")
        
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
    
    private var conversationFileURL: URL {
        return applicationSupportDirectory.appendingPathComponent("conversation_history.json")
    }
    
    func saveHistory(_ messages: [ChatMessage]) {
        // Only save the text and metadata, ID and Date are handled by ChatMessage
        let codableMessages = messages.map { ["text": $0.text, "isUser": $0.isUser, "timestamp": $0.timestamp.timeIntervalSince1970] }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: codableMessages, options: .prettyPrinted)
            try data.write(to: conversationFileURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    func loadHistory() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: conversationFileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        return json.compactMap { dict in
            guard let text = dict["text"] as? String,
                  let isUser = dict["isUser"] as? Bool,
                  let timestamp = dict["timestamp"] as? TimeInterval else { return nil }
            return ChatMessage(text: text, isUser: isUser) // In a real app we'd preserve the date better
        }
    }
}
