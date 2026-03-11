#if os(macOS)
import Foundation
import Cocoa
import ScreenCaptureKit

class ScreenManager {
    static let shared = ScreenManager()
    
    func captureScreenBase64() async -> String? {
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = shareableContent.displays.first else { return nil }
            
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            
            // Optimization: Goal is ~720p for speed and memory efficiency
            let maxWidth: CGFloat = 1280
            let scale = min(1.0, maxWidth / CGFloat(display.width))
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            
            // Capture the screenshot
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                return nil
            }
            return pngData.base64EncodedString()
        } catch {
            print("[ScreenManager] Error capturing screen: \(error)")
            return nil
        }
    }
}
#else
import Foundation

class ScreenManager {
    static let shared = ScreenManager()
    func captureScreenBase64() async -> String? {
        return nil
    }
}
#endif // os(macOS)
