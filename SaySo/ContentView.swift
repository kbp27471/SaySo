import SwiftUI

struct ContentView: View {
    @StateObject private var voice = VoiceController()
    @State private var showVoiceSetup = false
    @State private var effect: CameraEffect = .normal
    @State private var rendererError: String?
    @StateObject private var camera = CameraManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalCameraView(frames: camera.frames, effect: effect,
                            active: scenePhase == .active, error: $rendererError)
                .ignoresSafeArea()
            if let message = rendererError ?? camera.message {
                VStack(spacing: 16) {
                    Text(message)
                        .multilineTextAlignment(.center)
                    if camera.needsSettings {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .foregroundStyle(.white)
                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
        .overlay(alignment: .top) {
            Text("SaySo • \(effect.title)")
                .multilineTextAlignment(.center)
                .font(.caption)
                .padding(10)
                .foregroundStyle(.white)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                VStack(spacing: 4) {
                    Text(voice.status).font(.caption)
                    if !voice.transcript.isEmpty { Text(voice.transcript).font(.callout).lineLimit(2) }
                    HStack {
                        Button(voice.active ? "Stop listening" : "Start listening") {
                            if voice.active { voice.stop() }
                            else if VoiceKeychain.read().isEmpty { showVoiceSetup = true }
                            else { voice.start(key: VoiceKeychain.read()) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Voice setup") { voice.stop(); showVoiceSetup = true }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .foregroundStyle(.white)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 8) {
                    ForEach(CameraEffect.allCases) { choice in
                        Button { effect = choice } label: {
                            Text(choice.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(effect == choice ? Color.white : Color.black.opacity(0.65),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(effect == choice ? .black : .white)
                        }
                        .accessibilityAddTraits(effect == choice ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showVoiceSetup) { VoiceSetupView() }
        .onChange(of: voice.commandVersion) { _, _ in
            if let id = voice.command, let selected = CameraEffect(rawValue: id) { effect = selected }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop(); voice.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { camera.start() }
            else if phase == .background { camera.stop(); voice.stop() }
        }
    }
}
