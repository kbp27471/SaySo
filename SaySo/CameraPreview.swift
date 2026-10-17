import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    @Binding var isPreviewReady: Bool

    final class PreviewView: UIView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }

    final class Coordinator {
        var observation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        let ready = $isPreviewReady
        context.coordinator.observation = view.previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { layer, _ in
            let value = layer.isPreviewing
            Task { @MainActor in ready.wrappedValue = value }
        }
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PreviewView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}
