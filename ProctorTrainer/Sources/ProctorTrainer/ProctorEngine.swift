import Foundation

@MainActor
class ProctorEngine {
    private let cameraTester = CameraTester()
    private let voiceMonitor = VoiceMonitor()
    
    func train() {
        let trainer = Trainer()
        trainer.runPipeline()
    }
    
    func start() {
        print("[ProctorEngine] Starting Unified Monitoring...")
        voiceMonitor.startMonitoring()
        
        cameraTester.onInference = { [weak self] score, isPass in
            guard let self = self else { return }
            Task { @MainActor in
                SharedState.shared.updateInference(score: score, isPass: isPass)
                SharedState.shared.updateTranscript(self.voiceMonitor.currentTranscript)
            }
        }
        
        cameraTester.startCapture()
    }
    
    func stop() {
        cameraTester.stopCapture()
    }
}
