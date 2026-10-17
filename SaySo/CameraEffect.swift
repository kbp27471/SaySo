import Foundation

enum CameraEffect: UInt32, CaseIterable, Identifiable {
    case normal, grayscale, tint, vignette
    var id: UInt32 { rawValue }
    var title: String {
        switch self {
        case .normal: "Normal"
        case .grayscale: "Black & White"
        case .tint: "Tint"
        case .vignette: "Vignette"
        }
    }
}

