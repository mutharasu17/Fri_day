import Foundation
import AppKit
import Vision

@MainActor
class ScreenManager {
    static let shared = ScreenManager()
    
    private init() {}
    
    func captureScreenBase64() async -> String? {
        let tempPath = "/tmp/screen_capture.jpg"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "jpg", tempPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = try Data(contentsOf: URL(fileURLWithPath: tempPath))
            return data.base64EncodedString()
        } catch {
            print("Screen capture failed: \(error)")
            return nil
        }
    }
}
