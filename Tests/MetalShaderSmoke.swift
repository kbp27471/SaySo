import Foundation
import Metal
let device = MTLCreateSystemDefaultDevice()!
let shaderURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("SaySo/CameraEffects.metal")
let source = try String(contentsOf: shaderURL, encoding: .utf8)
let library = try device.makeLibrary(source: source, options: nil)
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "cameraVertex")
descriptor.fragmentFunction = library.makeFunction(name: "cameraFragment")
descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
let queue = device.makeCommandQueue()!
let size = 64
func texture(_ usage: MTLTextureUsage) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    d.storageMode = .shared
    d.usage = usage
    return device.makeTexture(descriptor: d)!
}
let input = texture(.shaderRead)
let output = texture(.renderTarget)
var pixels = [UInt8](repeating: 0, count: size * size * 4)
for i in stride(from: 0, to: pixels.count, by: 4) {
    pixels[i] = 180; pixels[i+1] = 100; pixels[i+2] = 60; pixels[i+3] = 255
}
func upload() {
    pixels.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: size * 4) }
}
struct Uniforms { var crop = SIMD2<Float>(1,1); var effect: UInt32; var padding: Float = 0 }
func render(_ effect: UInt32) -> [UInt8] {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = output
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    let command = queue.makeCommandBuffer()!
    let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
    var uniforms = Uniforms(effect: effect)
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentTexture(input, index: 0)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.commit(); command.waitUntilCompleted()
    precondition(command.status == .completed, "GPU execution failed")
    var result = [UInt8](repeating: 0, count: pixels.count)
    result.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: size * 4, from: MTLRegionMake2D(0,0,size,size), mipmapLevel: 0) }
    return result
}
upload()
let normal = render(0)
precondition(normal == pixels, "Normal must preserve pixel values")
let gray = render(1)
precondition(gray[0] == gray[1] && gray[1] == gray[2], "Grayscale channels must match")
let tint = render(2)
precondition(tint[0] > normal[0] && tint[2] < normal[2], "Tint must warm the image")
let vignette = render(3)
let center = (32 * size + 32) * 4
precondition(vignette[center] == normal[center] && vignette[0] < normal[0], "Vignette must preserve center and darken edges")
precondition(render(0) == normal, "Reset must restore original")
// A source left/right split must become a top/bottom split after clockwise rotation.
for y in 0..<size { for x in 0..<size {
    let i = (y * size + x) * 4
    pixels[i] = x < 32 ? 255 : 0
    pixels[i+1] = 0
    pixels[i+2] = x < 32 ? 0 : 255
} }
upload()
let rotated = render(0)
precondition(rotated[(8 * size + 32)*4] == 255 && rotated[(56 * size + 32)*4+2] == 255, "Portrait rotation must be clockwise")
print("PASS: GPU normal, grayscale, warm tint, vignette, reset, portrait rotation")
