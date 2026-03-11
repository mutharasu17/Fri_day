import SwiftUI

@main
struct FRIDAYApp: App {
    init() {
        // Auto-configure Python for ProctorTrainer
        setenv("PYTHON_LIBRARY", "/Library/Frameworks/Python.framework/Versions/3.11/lib/libpython3.11.dylib", 1)
    }
    
    var body: some Scene {
        Window("FRIDAY", id: "main") {
            FridayCoreView()
                .background(TransparentWindowView())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 500, height: 600)
    }
}

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
