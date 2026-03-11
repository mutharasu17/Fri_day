import Foundation
import PythonKit

/*
 🤖 FRIDAY SYNC SERVICE
 Handles the bridge between the Python Agent's database and the Swift App.
*/

@MainActor
class DatabaseManager {
    static let shared = DatabaseManager()
    private var sqlite3: PythonObject?
    
    private init() {
        do {
            self.sqlite3 = try Python.import("sqlite3")
        } catch {
            print("❌ PythonKit Error: Could not import sqlite3. Make sure Python is available.")
        }
    }
    
    private var dbPath: String {
        let path = NSString(string: "~/Library/Application Support/FRIDAY/SharedMemory.db").expandingTildeInPath
        return path
    }
    
    func pollForSpeeches() -> [String] {
        guard let sqlite3 = sqlite3 else { return [] }
        var texts: [String] = []
        
        do {
            let conn = sqlite3.connect(dbPath)
            let cursor = conn.cursor()
            
            // 1. Check for Pending TTS requests
            cursor.execute("SELECT id, text FROM tts_queue WHERE status = 'PENDING' ORDER BY id ASC")
            let rows = cursor.fetchall()
            
            for row in rows {
                if let id = Int(row[0]), let text = String(row[1]) {
                    texts.append(text)
                    // 2. Mark as completed
                    cursor.execute("UPDATE tts_queue SET status = 'COMPLETED' WHERE id = \(id)")
                }
            }
            
            if !texts.isEmpty {
                conn.commit()
            }
            conn.close()
        } catch {
            print("⚠️ SQL Sync Error: \(error)")
        }
        
        return texts
    }
    
    func pollEmotionalState() -> String {
        guard let sqlite3 = sqlite3 else { return "NEUTRAL" }
        var state = "NEUTRAL"
        
        do {
            let conn = sqlite3.connect(dbPath)
            let cursor = conn.cursor()
            cursor.execute("SELECT state FROM emotional_state")
            let row = cursor.fetchone()
            if let result = String(row[0]) {
                state = result
            }
            conn.close()
        } catch {
            // Table might not exist yet if python hasn't run
        }
        
        return state
    }
}
