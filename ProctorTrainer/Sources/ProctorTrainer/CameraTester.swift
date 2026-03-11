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
        loadModel()
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
        let desktopPath = NSString(string: "~/Desktop/ProctorModel.mlpackage").expandingTildeInPath
        let url = URL(fileURLWithPath: desktopPath)
        
        do {
            // Compile model on the fly if needed, or use existing .mlmodelc
            // For now, assume it's there
            let compiledUrl = try MLModel.compileModel(at: url)
            let mlModel = try MLModel(contentsOf: compiledUrl)
            self.model = try VNCoreMLModel(for: mlModel)
        } catch {
            print("[Camera] Model load error: \(error). Using mock inference.")
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        
        guard let model = self.model else {
            // Mock inference if model not found
            let score = Double.random(in: 0.1...0.9)
            processResult(score: score)
            return
        }
        
        let request = VNCoreMLRequest(model: model) { (request, error) in
            guard let results = request.results as? [VNCoreMLFeatureValueObservation],
                  let score = results.first?.featureValue.multiArrayValue?[0].doubleValue else { return }
            self.processResult(score: score)
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
    
    private func processResult(score: Double) {
        let isPass = score < 0.5
        let status = isPass ? "✅ PASS" : "❌ VIOLATION"
        print("Frame \(frameCount): Anomaly=\(String(format: "%.2f", score)) \(status)")
        onInference?(score, isPass)
    }
}
