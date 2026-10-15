//
//  CameraManager.swift
//  MyApp
//
//
import AVFoundation

final class CameraManager {
    // Create the capture session
    let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    
    func configure() {
        captureSession.beginConfiguration()
        guard
            let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                      for: .video,
                                                      position: .back),
            let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
            captureSession.canAddInput(videoDeviceInput)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(videoDeviceInput)
        captureSession.commitConfiguration()
    }
    
    func start() {
        sessionQueue.async {
            self.configure()
            self.captureSession.startRunning()
        }
    }
}
