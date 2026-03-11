import Foundation
import AVFoundation
import Vision
import CoreImage
import Combine

@MainActor
class SimpleFaceDetector: NSObject, ObservableObject {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session", qos: .userInitiated)
    
    @Published var isDetecting = false
    @Published var faceCount = 0
    @Published var expression = "neutral"
    
    var onFaceDetected: ((Int) -> Void)?
    var onExpressionDetected: ((String) -> Void)?
    
    func startDetection() {
        sessionQueue.async { [weak self] in
            self?.setupCamera()
        }
    }
    
    func stopDetection() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
        }
        DispatchQueue.main.async {
            self.isDetecting = false
            self.faceCount = 0
        }
    }
    
    private func setupCamera() {
        // Check camera permission first
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("[FaceDetector] Camera permission status: \(authStatus.rawValue)")
        
        if authStatus == .notDetermined {
            print("[FaceDetector] Requesting camera permission...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("[FaceDetector] Camera permission granted!")
                        self.setupCamera()
                    } else {
                        print("[FaceDetector] Camera permission denied!")
                    }
                }
            }
            return
        }
        
        guard authStatus == .authorized else {
            print("[FaceDetector] Camera permission not granted. Status: \(authStatus)")
            print("[FaceDetector] Please go to System Preferences → Security & Privacy → Camera → Allow FRIDAY")
            return
        }
        
        let session = AVCaptureSession()
        session.sessionPreset = .low
        
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: frontCamera) else {
            print("[FaceDetector] Could not setup camera input")
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        
        self.videoOutput = output
        self.captureSession = session
        
        DispatchQueue.main.async {
            self.isDetecting = true
        }
        
        session.startRunning()
        print("[FaceDetector] Camera started for face detection")
    }
    
    private func detectFaces(in pixelBuffer: CVPixelBuffer) {
        let faceRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let faces = request.results as? [VNFaceObservation] {
                DispatchQueue.main.async {
                    self.faceCount = faces.count
                    self.onFaceDetected?(faces.count)
                    
                    // Simple expression detection based on facial landmarks
                    if let firstFace = faces.first, let landmarks = firstFace.landmarks {
                        self.detectExpression(from: landmarks)
                    }
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([faceRequest])
    }
    
    private func detectExpression(from landmarks: VNFaceLandmarks2D) {
        // Simple expression detection based on mouth position
        if let mouth = landmarks.outerLips {
            let mouthPoints = mouth.normalizedPoints
            let mouthHeight = mouthPoints.max(by: { $0.y < $1.y })!.y - mouthPoints.min(by: { $0.y < $1.y })!.y
            
            // Basic expression detection
            if mouthHeight > 0.15 {
                expression = "smiling"
                onExpressionDetected?("smiling")
            } else if mouthHeight < 0.05 {
                expression = "serious"
                onExpressionDetected?("serious")
            } else {
                expression = "neutral"
                onExpressionDetected?("neutral")
            }
        }
    }
}

extension SimpleFaceDetector: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        detectFaces(in: pixelBuffer)
    }
}
