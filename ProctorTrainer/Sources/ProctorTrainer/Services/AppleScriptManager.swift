import Foundation
import AppKit

@MainActor
class AppleScriptManager {
    static let shared = AppleScriptManager()
    
    private init() {}
    
    func run(_ script: String) -> String? {
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        let result = appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("AppleScript error: \(error)")
            return nil
        }
        
        return result?.stringValue
    }
    
    func setVolume(_ volume: Int) {
        _ = run("set volume output volume \(volume)")
    }
    
    func setBrightness(_ brightness: Double) {
        // Simple brightness control via shell/applescript (requires permissions)
        _ = run("tell application \"System Events\" to set value of attribute \"AXValue\" of slider 1 of group 1 of tab group 1 of window 1 of process \"System Settings\" to \(brightness / 100.0)")
    }
    
    func lockScreen() {
        _ = run("tell application \"System Events\" to keystroke \"q\" using {control down, command down}")
    }
    
    func launchApp(_ name: String) {
        _ = run("tell application \"\(name)\" to activate")
    }
    
    func getSystemInfo() -> String {
        return run("get system info") ?? "Unknown"
    }
    
    func clickAt(x: Double, y: Double) {
        _ = run("tell application \"System Events\" to click at {\(x), \(y)}")
    }
}
