import Foundation
import Combine

@MainActor
class SharedState: ObservableObject {
    static let shared = SharedState()
    
    @Published var lastAnomalyScore: Double = 0.0
    @Published var isViolation: Bool = false
    @Published var lastTranscript: String = ""
    
    /// Thread-safe cache managed by the MainActor
    var cache: [String: Any] = [:]
    
    private init() {}
    
    func updateInference(score: Double, isPass: Bool) {
        self.lastAnomalyScore = score
        self.isViolation = !isPass
    }
    
    func updateTranscript(_ text: String) {
        self.lastTranscript = text
    }
    
    func setCameraEnabled(_ enabled: Bool) async {
        // This is a placeholder for actual AVFoundation camera control
        // For now, it just updates the internal state.
        self.cache["camera_enabled"] = enabled
        print("Camera enabled state set to: \(enabled)")
    }
}
