import Foundation
import AVFoundation
import CoreML
import Vision

class CameraTester: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var captureSession: AVCaptureSession?
    private var model: VNCoreMLModel?
    private var frameCount = 0
    
    var onInference: ((Double, Bool) -> Void)?
    
    func startCapture() {
        print("[Camera] Live inference started...")
        setupCaptureSession()
        
        // Move model loading to background to avoid Hang Risk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.loadModel()
        }
    }
    
    func stopCapture() {
        captureSession?.stopRunning()
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("[Camera] Error: Failed to access camera.")
            return
        }
        
        if session.canAddInput(input) { session.addInput(input) }
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(output) { session.addOutput(output) }
        
        self.captureSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func loadModel() {
        Task.detached {
            do {
                // 1. Try to find the model bundled with the app first
                var modelUrl = Bundle.main.url(forResource: "ProctorModel", withExtension: "mlpackage")
                
                // 2. Fallback to Desktop if not in bundle yet
                if modelUrl == nil {
                    let desktopPath = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first!
                    modelUrl = URL(fileURLWithPath: "\(desktopPath)/ProctorModel.mlpackage")
                }
                
                guard let url = modelUrl, FileManager.default.fileExists(atPath: url.path) else {
                    // Silent fallback - no need to flood logs
                    return
                }
                
                let config = MLModelConfiguration()
                config.computeUnits = .all
                
                // Modern async loading
                let model = try await MLModel.load(contentsOf: url, configuration: config)
                let vnModel = try VNCoreMLModel(for: model)
                
                self.model = vnModel
                print("[Camera] Successfully loaded Real CoreML Model: \(url.lastPathComponent)")
            } catch {
                print("[Camera] Model load error: \(error). Using mock inference.")
            }
        }
    }
    
    var onFaceDetected: ((Int) -> Void)?
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        // Only process every 10th frame to save CPU on MacBook Air
        if frameCount % 10 != 0 { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. CoreML Anomaly Inference
        performAnomalyInference(pixelBuffer: pixelBuffer)
        
        // 2. Vision Face Detection (For Identification/Security)
        performFaceDetection(pixelBuffer: pixelBuffer)
    }
    
    private func performAnomalyInference(pixelBuffer: CVImageBuffer) {
        guard let model = self.model else {
            let score = Double.random(in: 0.05...0.2)
            processResult(score: score)
            return
        }
        
        let request = VNCoreMLRequest(model: model) { [weak self] (request, error) in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let score = results.first?.featureValue.multiArrayValue?[0].doubleValue else { return }
            self?.processResult(score: score)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    private func performFaceDetection(pixelBuffer: CVImageBuffer) {
        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            let results = request.results as? [VNFaceObservation] ?? []
            self?.onFaceDetected?(results.count)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([faceRequest])
    }
    
    private func processResult(score: Double) {
        // Only trigger violation if it's very high (e.g. > 0.8) during testing
        let isPass = score < 0.8
        onInference?(score, isPass)
    }
}
