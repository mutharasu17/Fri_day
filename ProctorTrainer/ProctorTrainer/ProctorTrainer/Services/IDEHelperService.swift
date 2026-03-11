import Foundation
import AppKit

class IDEHelperService {
    static let shared = IDEHelperService()
    
    // MARK: - Xcode Helpers
    func getCurrentXcodeProject() -> String {
        let script = """
        tell application "Xcode"
            try
                return path of active workspace document
            on error
                return ""
            end try
        end tell
        """
        return AppleScriptManager.shared.runScript(script) ?? ""
    }
    
    func getLatestBuildLog() -> String {
        // This is a simplified version - in a real app, you'd look for the latest log in DerivedData
        return "Build failed: Use of unresolved identifier 'IDEContext'"
    }
    
    func extractLatestError(from log: String) -> String {
        // Simple error extraction
        if let range = log.range(of: "error: ") {
            return String(log[range.lowerBound...])
        }
        return log
    }
    
    func getCurrentFileName() -> String {
        let script = """
        tell application "Xcode"
            try
                return name of active document
            on error
                return ""
            end try
        end tell
        """
        return AppleScriptManager.shared.runScript(script) ?? ""
    }
    
    func getSelectedCode() -> String {
        let script = """
        tell application "System Events"
            tell process "Xcode"
                keystroke "c" using {command down}
            end tell
        end tell
        """
        AppleScriptManager.shared.runScript(script)
        return NSPasteboard.general.string(forType: .string) ?? ""
    }
    
    func getTerminalOutput() -> String {
        return "Terminal output capture not implemented yet."
    }
    
    // MARK: - VS Code Helpers
    func getVSCodeFileName() -> String { return "" }
    func getVSCodeSelectedCode() -> String { return "" }
    func getVSCodeErrors() -> String { return "" }
    func getVSCodeWorkspacePath() -> String { return "" }
    func getVSCodeTerminalOutput() -> String { return "" }
    
    // MARK: - Windsurf Helpers
    func getWindsurfFileName() -> String { return "" }
    func getWindsurfSelectedCode() -> String { return "" }
    func getWindsurfErrors() -> String { return "" }
    func getWindsurfWorkspacePath() -> String { return "" }
    func getWindsurfTerminalOutput() -> String { return "" }
    
    // MARK: - Antigravity Helpers
    func getAntigravityFileName() -> String { return "" }
    func getAntigravitySelectedCode() -> String { return "" }
    func getAntigravityErrors() -> String { return "" }
    func getAntigravityWorkspacePath() -> String { return "" }
    func getAntigravityTerminalOutput() -> String { return "" }
    
    // MARK: - Cursor Helpers
    func getCursorFileName() -> String { return "" }
    func getCursorSelectedCode() -> String { return "" }
    func getCursorErrors() -> String { return "" }
    func getCursorWorkspacePath() -> String { return "" }
    func getCursorTerminalOutput() -> String { return "" }
    
    // MARK: - Analysis Helpers
    func getProjectType(from fileName: String) -> String {
        if fileName.hasSuffix(".swift") { return "Swift iOS/macOS Project" }
        return "Unknown Project"
    }
    
    func getFileType(from fileName: String) -> String {
        return URL(fileURLWithPath: fileName).pathExtension
    }
    
    func getWorkContext(from fileName: String, selectedCode: String) -> String {
        return "User is working on \(fileName)."
    }
    
    func getErrorType(from errorText: String) -> String {
        if errorText.contains("missing") { return "Missing Symbol" }
        return "Generic Error"
    }
    
    func getErrorSeverity(from errorText: String) -> String {
        return "High"
    }
}
