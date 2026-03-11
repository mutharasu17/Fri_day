import Foundation
import Combine

@MainActor
class SharedState: ObservableObject {
    static let shared = SharedState()
    
    @Published var lastAnomalyScore: Double = 0.0
    @Published var isViolation: Bool = false
    @Published var lastTranscript: String = ""
    @Published var faceCount: Int = 0
    @Published var isCameraEnabled: Bool = true
    @Published var activeUI: DynamicUIContent? = nil
    
    /// Thread-safe cache managed by the MainActor
    var cache: [String: Any] = [:]
    
    private init() {}
    
    func setDynamicUI(_ content: DynamicUIContent?) {
        self.activeUI = content
    }
    
    func setCameraEnabled(_ enabled: Bool) {
        self.isCameraEnabled = enabled
    }
    
    func updateInference(score: Double, isPass: Bool) {
        self.lastAnomalyScore = score
        self.isViolation = !isPass
    }
    
    func updateFaceCount(_ count: Int) {
        self.faceCount = count
    }
    
    func updateTranscript(_ transcript: String) {
        self.lastTranscript = transcript
    }
}
