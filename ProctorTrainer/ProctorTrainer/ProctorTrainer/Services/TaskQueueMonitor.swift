
// TaskQueueMonitor.swift — macOS only
// Polls SharedMemory.db for tasks written by the Python iMessage agent.
// This file is intentionally excluded from the iOS target.

#if os(macOS)

import Foundation
import AppKit
import UserNotifications
import SQLite3
import Combine

// MARK: - Task Queue Monitor
class TaskQueueMonitor: ObservableObject {

    static let shared = TaskQueueMonitor()

    private let dbPath: String = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("FRIDAY")
            .appendingPathComponent("SharedMemory.db")
            .path
    }()

    private var pollTimer: Timer?
    @Published var isRunning = false
    @Published var tasksCompleted = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        print("[TaskQueue] Monitor started → \(dbPath)")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollAndExecute()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isRunning = false
    }

    // MARK: - Poll loop

    private func pollAndExecute() {
        guard let db = openDB() else { return }
        defer { sqlite3_close(db) }
        let tasks = claimPendingTasks(db: db)
        for task in tasks {
            print("[TaskQueue] #\(task.id) \(task.taskType)(\(task.input.prefix(40)))")
            executeTask(task, db: db)
        }
    }

    private func executeTask(_ task: QueueTask, db: OpaquePointer) {
        switch task.taskType {
        case "open":
            markCompleted(db: db, taskId: task.id, result: openApp(named: task.input))
        case "close", "quit":
            markCompleted(db: db, taskId: task.id, result: closeApp(named: task.input))
        case "notify":
            showNotification(title: "FRIDAY", body: task.input)
            markCompleted(db: db, taskId: task.id, result: "Notification shown ✅")
        case "screenshot":
            markCompleted(db: db, taskId: task.id, result: takeScreenshot())
        default:
            markCompleted(db: db, taskId: task.id, result: "Unknown: \(task.taskType)")
        }
    }

    // MARK: - Native implementations

    private func openApp(named name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ws = NSWorkspace.shared
        
        // Modern approach: Try to find the app URL first
        if let appURL = ws.urlForApplication(withBundleIdentifier: clean) ?? 
                        ws.fullPath(forApplication: clean).map({ URL(fileURLWithPath: $0) }) {
            ws.open(appURL)
            return "Opened \(clean) ✅"
        }
        
        // Fallback: Use the 'open' shell command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", clean]
        do {
            try process.run()
            return "Sent open command for \(clean) ✅"
        } catch {
            return "Could not find '\(clean)': \(error.localizedDescription)"
        }
    }

    private func closeApp(named name: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = "tell application \"\(clean)\" to quit"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil ? "Closed \(clean) ✅" : "Could not close '\(clean)'"
    }

    private func showNotification(title: String, body: String) {
        let content      = UNMutableNotificationContent()
        content.title    = title
        content.body     = body
        content.sound    = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func takeScreenshot() -> String {
        let ts   = Int(Date().timeIntervalSince1970)
        let path = NSString(string: "~/Desktop/friday_\(ts).png").expandingTildeInPath
        
        // FIX: CGDisplayCreateImage is unavailable. 
        // We use the 'screencapture' CLI which is the most reliable way for automation.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", path] // -x means silent (no camera sound)
        
        do {
            try process.run()
            process.waitUntilExit()
            return "Screenshot saved to Desktop ✅"
        } catch {
            return "Screenshot failed: \(error.localizedDescription)"
        }
    }

    // MARK: - SQLite helpers

    private struct QueueTask { let id: Int; let taskType: String; let input: String; let chatGuid: String }

    private func openDB() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        return db
    }

    private func claimPendingTasks(db: OpaquePointer) -> [QueueTask] {
        var stmt: OpaquePointer?
        var tasks: [QueueTask] = []
        let sel = "SELECT id,task_type,input,chat_guid FROM task_queue WHERE status='PENDING' ORDER BY id ASC"
        guard sqlite3_prepare_v2(db, sel, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var ids: [Int] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            tasks.append(QueueTask(
                id:       id,
                taskType: String(cString: sqlite3_column_text(stmt, 1)),
                input:    String(cString: sqlite3_column_text(stmt, 2)),
                chatGuid: String(cString: sqlite3_column_text(stmt, 3))
            ))
            ids.append(id)
        }
        guard !ids.isEmpty else { return [] }
        let ph  = ids.map { _ in "?" }.joined(separator: ",")
        let upd = "UPDATE task_queue SET status='PROCESSING',updated=? WHERE id IN (\(ph))"
        var us: OpaquePointer?
        if sqlite3_prepare_v2(db, upd, -1, &us, nil) == SQLITE_OK {
            let ts = ISO8601DateFormatter().string(from: Date())
            sqlite3_bind_text(us, 1, ts, -1, nil)
            for (i, id) in ids.enumerated() { sqlite3_bind_int(us, Int32(i+2), Int32(id)) }
            sqlite3_step(us); sqlite3_finalize(us)
        }
        return tasks
    }

    private func markCompleted(db: OpaquePointer?, taskId: Int, result: String) {
        guard let db = db else { return }
        var s: OpaquePointer?
        let sql = "UPDATE task_queue SET status='COMPLETED',result=?,updated=? WHERE id=?"
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(s) }
        let ts = ISO8601DateFormatter().string(from: Date())
        sqlite3_bind_text(s, 1, result, -1, nil)
        sqlite3_bind_text(s, 2, ts,     -1, nil)
        sqlite3_bind_int (s, 3, Int32(taskId))
        sqlite3_step(s)
        DispatchQueue.main.async { self.tasksCompleted += 1 }
    }
}

#else

// Stub for iOS — TaskQueueMonitor does nothing on iPhone
import Foundation
import Combine

class TaskQueueMonitor: ObservableObject {
    static let shared = TaskQueueMonitor()
    
    @Published var isRunning = false
    @Published var tasksCompleted = 0
    
    func start() {}
    func stop()  {}
}

#endif
