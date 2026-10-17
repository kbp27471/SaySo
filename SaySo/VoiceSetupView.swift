import SwiftUI

struct VoiceSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your ElevenLabs account") {
                    SecureField("API key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Link("Open ElevenLabs", destination: URL(string: "https://elevenlabs.io/app")!)
                    Text("For this personal demo, your key stays in this iPhone’s Keychain. It is never added to the project.")
                        .font(.footnote)
                }
                Section {
                    Text("When you tap Start listening, microphone audio is sent to ElevenLabs for transcription and uses your account’s credits. Tap Stop listening to end the session.")
                    Text("Say: black and white, tint, vignette, normal, or reset. Pause briefly between commands.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Save") {
                    do { try VoiceKeychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
                Button("Remove saved key", role: .destructive) {
                    do { try VoiceKeychain.save(""); key = ""; dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            .navigationTitle("Voice setup")
            .toolbar { Button("Done") { dismiss() } }
            .onAppear { key = VoiceKeychain.read() }
            .onDisappear { key = "" }
        }
    }
}
