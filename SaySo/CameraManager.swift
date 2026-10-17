import AVFoundation
import Combine
import CoreVideo

@MainActor
final class CameraManager: ObservableObject {
    @Published private(set) var message: String? = "Starting camera…"
    @Published private(set) var status = "Requesting camera access…"
    @Published private(set) var needsSettings = false
    let frames = CameraFrames()
    private let worker: CameraSession

    init() {
        worker = CameraSession(frames: frames)
    }
    private var wantsCamera = false

    var captureSession: AVCaptureSession { worker.session }

    func start() {
        wantsCamera = true
        Task {
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined:
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard wantsCamera else { return }
            guard authorized else {
                status = "Camera permission denied"
                needsSettings = true
                message = "Allow camera access in Settings to see the live preview."
                return
            }
            needsSettings = false
            status = "Starting camera…"
            worker.start { [self] error in
                Task { @MainActor in
                    guard self.wantsCamera else { return }
                    self.message = error
                    self.status = error == nil ? "Camera running" : "Camera unavailable"
                }
            }
        }
    }

    func stop() {
        wantsCamera = false
        status = "Camera paused"
        worker.stop()
    }
}

// All session configuration and start/stop operations run on this serial queue.
nonisolated private final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session")
    private var configured = false
    private let videoOutput = AVCaptureVideoDataOutput()
    private let frameQueue = DispatchQueue(label: "camera.frames")
    private let frames: CameraFrames

    init(frames: CameraFrames) {
        self.frames = frames
        super.init()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames.store(pixelBuffer)
    }

    func start(completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .high
                do {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                               for: .video, position: .back) else {
                        session.commitConfiguration()
                        completion("No back camera is available. Run SaySo on a real iPhone.")
                        return
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        completion("Unable to connect the camera. Try reopening SaySo.")
                        return
                    }
                    session.addInput(input)
                    videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferMetalCompatibilityKey as String: true
                    ]
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
                    guard session.canAddOutput(videoOutput) else {
                        session.removeInput(input)
                        session.commitConfiguration()
                        completion("Camera video output is unavailable.")
                        return
                    }
                    session.addOutput(videoOutput)
                    session.commitConfiguration()
                    configured = true
                } catch {
                    session.commitConfiguration()
                    completion("Camera setup failed: \(error.localizedDescription)")
                    return
                }
            }
            if !session.isRunning { session.startRunning() }
            completion(session.isRunning ? nil : "The camera could not start. Try reopening SaySo.")
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }
}

// Capture replaces one retained buffer; rendering never queues old frames.
nonisolated final class CameraFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func store(_ buffer: CVPixelBuffer) {
        lock.lock()
        latest = buffer
        lock.unlock()
    }

    func snapshot() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}
