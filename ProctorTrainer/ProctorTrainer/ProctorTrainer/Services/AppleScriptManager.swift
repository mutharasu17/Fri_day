#if os(macOS)
import Foundation
import Cocoa

class AppleScriptManager {
    static let shared = AppleScriptManager()
    
    @discardableResult
    func runScript(_ scriptSource: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            let output = script.executeAndReturnError(&error)
            if let err = error {
                print("[AppleScript] Error: \(err)")
                return "Error: \(err[NSAppleScript.errorMessage] ?? "Unknown error")"
            }
            return output.stringValue
        }
        return nil
    }
    
    func readRecentMessages() -> String {
        let script = """
        if application "Messages" is running then
            tell application "Messages"
                set recentMessages to ""
                try
                    set allChats to chats
                    repeat with i from 1 to (get count of allChats)
                        if i > 3 then exit repeat
                        set aChat to item i of allChats
                        set recentMsg to (get name of aChat) & ": " & (get text of last message of aChat)
                        set recentMessages to recentMessages & recentMsg & "\n"
                    end repeat
                on error
                    return "Could not read message contents."
                end try
                return recentMessages
            end tell
        else
            return "Messages app is not running."
        end if
        """
        return runScript(script) ?? "Could not access Messages."
    }
    
    func readRecentEmails() -> String {
        let script = """
        if application "Mail" is running then
            tell application "Mail"
                set recentEmails to ""
                try
                    set allMessages to messages of inbox
                    repeat with i from 1 to 3
                        if i > (count of allMessages) then exit repeat
                        set aMsg to item i of allMessages
                        set senderName to sender of aMsg
                        set subjectText to subject of aMsg
                        set recentEmails to recentEmails & "From: " & senderName & " - Subject: " & subjectText & "\n"
                    end repeat
                on error
                    return "Could not read inbox contents."
                end try
                return recentEmails
            end tell
        else
            return "Mail app is not running."
        end if
        """
        return runScript(script) ?? "Could not access Mail."
    }
    
    // --- System Control Actions ---
    
    func setVolume(_ percent: Int) {
        runScript("set volume output volume \(percent)")
    }
    
    func setBrightness(_ percent: Double) {
        // Brightness is 0.0 to 1.0, but percent is easier for AI
        runScript("tell application \"System Events\" to set value of attribute \"AXValue\" of slider 1 of group 1 of window 1 of process \"ControlCenter\" to \(percent/100.0)")
        // Simpler fallback for some models:
        runScript("do shell script \"brightness \(percent/100.0)\"") 
    }
    
    func launchApp(_ name: String) {
        runScript("tell application \"\(name)\" to activate")
    }
    
    func lockScreen() {
        runScript("tell application \"System Events\" to keystroke \"q\" using {command down, control down}")
    }
    
    func getSystemInfo() -> String {
        let script = "do shell script \"pmset -g batt\""
        return runScript(script) ?? "Battery info unavailable."
    }
}
#else
import Foundation

class AppleScriptManager {
    static let shared = AppleScriptManager()
    func runScript(_ scriptSource: String) -> String? { return nil }
    func readRecentMessages() -> String { return "" }
    func readRecentEmails() -> String { return "" }
    func setVolume(_ percent: Int) {}
    func setBrightness(_ percent: Double) {}
    func launchApp(_ name: String) {}
    func lockScreen() {}
    func getSystemInfo() -> String { return "" }
}
#endif // os(macOS)
