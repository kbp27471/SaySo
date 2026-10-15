import SwiftUI

struct ContentView: View {
    private let camera = CameraManager()
    
    var body: some View {
        CameraPreview(session: camera.captureSession)
            .ignoresSafeArea()
            .onAppear { camera.start() }
    }
}
