# ProctorTrainer 🛡️

A production-ready macOS CLI tool for training proctoring models (PyTorch MPS) and running real-time AI-driven monitoring.

## Setup Requirements
1. **Python Dependencies**:
   ```bash
   pip3 install torch torchvision coremltools
   ```
2. **Xcode**: Ensure you are using Xcode 16+ for Swift 6.0 features.

## Project Structure
- `Trainer.swift`: PyTorch (MPS) → TorchScript → Core ML pipeline.
- `CameraTester.swift`: Real-time AVFoundation + Core ML inference.
- `VoiceMonitor.swift`: Live SFSpeechRecognizer transcription.
- `ProctorEngine.swift`: Unified orchestrator.

## How to Run

### 1. Training & Export
This trains a synthetic CNN on MPS and saves `ProctorModel.mlmodel` to your Desktop.
```bash
swift run ProctorTrainer train
```

### 2. Live Monitoring
Starts the camera and microphone. Combines visual anomaly detection with voice analysis.
```bash
swift run ProctorTrainer test
```

## Security & Permissions (Fixing Crashes)
If the app crashes with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`, it's because macOS is blocking Camera/Mic access.

### 1. Running in Terminal
Go to **System Settings** > **Privacy & Security** > **Camera** (and **Microphone**) and ensure your **Terminal** is toggled **ON**.

### 2. Running in Xcode (Recommended)
When you open this project in Xcode, you MUST add the usage descriptions:
1. Select the **ProctorTrainer** project in the sidebar.
2. Go to **Package.swift** settings or the Target's **Info** tab.
3. Add these keys to the `Info.plist` (or Target "Info" properties):
   - `Privacy - Camera Usage Description`: "Used for real-time proctoring."
   - `Privacy - Microphone Usage Description`: "Used for voice keyword spotting."

## Technical Specs
- **Target**: macOS 15.0+
- **Model**: `.mlpackage` (Modern ML Program)
- **Inference**: CoreML / Vision @ 30 FPS
