import SwiftUI

@main
struct FRIDAYApp: App {
    init() {
        #if os(macOS)
        // Find the most likely Python path on macOS (Homebrew or System)
        let paths = [
            "/opt/homebrew/opt/python@3.11/Frameworks/Python.framework/Versions/3.11/Python",
            "/Library/Frameworks/Python.framework/Versions/3.11/lib/libpython3.11.dylib",
            "/usr/local/lib/libpython3.11.dylib"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                setenv("PYTHON_LIBRARY", path, 1)
                break
            }
        }

        // 🧠 Start Task Queue Monitor — bridges iMessage agent ↔ Swift Mac engine
        TaskQueueMonitor.shared.start()
        #endif
    }
    
    var body: some Scene {
        #if os(macOS)
        Window("FRIDAY", id: "main") {
            FridayCoreView()
                .background(TransparentWindowView())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 500, height: 600)
        #else
        WindowGroup {
            FridayCoreView()
        }
        #endif
    }
}

#if os(macOS)
struct TransparentWindowView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .floating
                window.hasShadow = false
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                
                // Allow dragging the window from anywhere
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#else
struct TransparentWindowView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        return UIView()
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
