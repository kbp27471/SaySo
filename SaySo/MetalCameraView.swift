import SwiftUI
import MetalKit
import CoreVideo


struct MetalCameraView: UIViewRepresentable {
    let frames: CameraFrames
    let effect: CameraEffect
    let active: Bool
    @Binding var error: String?

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { fileprivate var renderer: CameraRenderer? }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.preferredFramesPerSecond = 60
        view.isPaused = !active
        do {
            let renderer = try CameraRenderer(view: view, frames: frames)
            renderer.effect = effect
            context.coordinator.renderer = renderer
            view.delegate = renderer
        } catch {
            let message = error.localizedDescription
            let binding = $error
            Task { @MainActor in binding.wrappedValue = message }
        }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderer?.effect = effect
        view.isPaused = !active
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
    }
}

@MainActor
private final class CameraRenderer: NSObject, MTKViewDelegate {
    var effect: CameraEffect = .normal
    private let frames: CameraFrames
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let cache: CVMetalTextureCache
    private let inFlight = DispatchSemaphore(value: 3)

    private struct Uniforms {
        var crop: SIMD2<Float>
        var effect: UInt32
        var padding: Float = 0
    }

    init(view: MTKView, frames: CameraFrames) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "cameraVertex"),
              let fragment = library.makeFunction(name: "cameraFragment") else {
            throw NSError(domain: "SaySo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to load the Metal camera renderer."])
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        var createdCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &createdCache) == kCVReturnSuccess,
              let createdCache else {
            throw NSError(domain: "SaySo", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create camera textures."])
        }
        cache = createdCache
        self.queue = queue
        self.frames = frames
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let buffer = frames.snapshot(), inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        var wrapped: CVMetalTexture?
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                       width, height, 0, &wrapped) == kCVReturnSuccess,
              let wrapped, let texture = CVMetalTextureGetTexture(wrapped),
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let imageAspect = Float(height) / Float(width)
        let viewAspect = Float(view.drawableSize.width / view.drawableSize.height)
        let crop = viewAspect > imageAspect
            ? SIMD2<Float>(1, imageAspect / viewAspect)
            : SIMD2<Float>(viewAspect / imageAspect, 1)
        var uniforms = Uniforms(crop: crop, effect: effect.rawValue)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        // Keep the camera buffer and its texture wrapper alive until the GPU finishes.
        let retained = GPUFrame(buffer: buffer, texture: wrapped)
        let semaphore = inFlight
        command.addCompletedHandler { _ in
            withExtendedLifetime(retained) {}
            semaphore.signal()
        }
        submitted = true
        command.commit()
    }
}

nonisolated private final class GPUFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let texture: CVMetalTexture
    init(buffer: CVPixelBuffer, texture: CVMetalTexture) {
        self.buffer = buffer
        self.texture = texture
    }
}
