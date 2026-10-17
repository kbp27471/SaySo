import AVFoundation
import Combine

@MainActor
final class VoiceController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Voice off"
    @Published private(set) var transcript = ""
    @Published private(set) var command: UInt32?
    @Published private(set) var commandVersion = 0
    private var engine: AVAudioEngine?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var generation = UUID()
    private var tapInstalled = false
    private var interruption: AnyCancellable?

    init() {
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.active else { return }
                    self.stop(message: "Microphone interrupted. Tap Start listening to resume.")
                }
            }
    }

    func start(key: String) {
        guard !active else { return }
        guard !key.isEmpty else { status = "Add your ElevenLabs API key in Voice setup."; return }
        generation = UUID()
        let id = generation
        active = true
        transcript = ""
        status = "Requesting microphone access…"
        receiveTask = Task { [weak self] in
            guard let self else { return }
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard self.generation == id, !Task.isCancelled else { return }
            guard allowed else { self.stop(message: "Microphone access denied. Enable it in iPhone Settings → SaySo."); return }
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.record, mode: .measurement)
                try audio.setActive(true)
                let engine = AVAudioEngine()
                self.engine = engine
                let format = engine.inputNode.outputFormat(forBus: 0)
                let rate = Int(format.sampleRate)
                guard [8000, 16000, 22050, 24000, 44100, 48000].contains(rate),
                      format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
                    throw VoiceFailure("This microphone format is unsupported. Try the built-in microphone.")
                }
                var url = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
                url.queryItems = [URLQueryItem(name: "model_id", value: "scribe_v2_realtime"),
                    URLQueryItem(name: "audio_format", value: "pcm_\(rate)"),
                    URLQueryItem(name: "language_code", value: "en"),
                    URLQueryItem(name: "commit_strategy", value: "vad")]
                var request = URLRequest(url: url.url!)
                request.timeoutInterval = 20
                request.setValue(key, forHTTPHeaderField: "xi-api-key")
                let socket = URLSession.shared.webSocketTask(with: request)
                self.socket = socket
                self.status = "Connecting to ElevenLabs…"
                socket.resume()
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(20))
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    self.stop(message: "Connection timed out. Check your network and API key.")
                }
                while !Task.isCancelled, self.generation == id {
                    let message = try await socket.receive()
                    guard self.generation == id else { return }
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = event["message_type"] as? String else { continue }
                    if type == "session_started" {
                        self.timeoutTask?.cancel()
                        guard !self.tapInstalled else { continue }
                        try self.beginAudio(engine: engine, format: format, socket: socket, id: id)
                        self.status = "Listening…"
                    } else if type == "partial_transcript" {
                        if let text = event["text"] as? String, !text.isEmpty { self.transcript = text }
                    } else if type == "committed_transcript" {
                        let text = event["text"] as? String ?? ""
                        guard !text.isEmpty else { continue }
                        self.transcript = text
                        if let effect = VoiceCommand.effectID(in: text) {
                            self.command = effect
                            self.commandVersion += 1
                            self.status = "Listening…"
                        } else { self.status = "Try black and white, tint, vignette, or normal." }
                    } else if event["error"] != nil || type.contains("error") || type == "rate_limited" {
                        // Never display raw server payloads, which may contain request details.
                        throw VoiceFailure("ElevenLabs: \(type.replacingOccurrences(of: "_", with: " ")). Check your key, speech-to-text access, and credits.")
                    }
                }
            } catch {
                guard self.generation == id else { return }
                self.stop(message: (error as? VoiceFailure)?.message ?? "Voice connection failed. Check your network and ElevenLabs key, then retry.")
            }
        }
    }

    private func beginAudio(engine: AVAudioEngine, format: AVAudioFormat,
                            socket: URLSessionWebSocketTask, id: UUID) throws {
        let (stream, sink) = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(12))
        continuation = sink
        try engine.inputNode.installAudioTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.1), format: format) { buffer, _ in
            guard case .float(let samples) = buffer.channelData(0) else { return }
            let count = Int(buffer.frameLength)
            var pcm = [Int16](repeating: 0, count: count)
            for i in 0..<count {
                let value = samples[i * buffer.stride]
                pcm[i] = Int16((max(-1, min(1, value.isFinite ? value : 0)) * 32767).rounded()).littleEndian
            }
            let data = pcm.withUnsafeBytes { Data($0) }
            if case .dropped = sink.yield(data) {
                sink.finish(throwing: VoiceFailure("The network is too slow for live audio. Tap Start listening to retry."))
            }
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
        sendTask = Task { [weak self] in
            do {
                for try await audio in stream {
                    try Task.checkCancellation()
                    let data = try JSONSerialization.data(withJSONObject: [
                        "message_type": "input_audio_chunk", "audio_base_64": audio.base64EncodedString(),
                        "sample_rate": Int(format.sampleRate)
                    ])
                    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                }
            } catch {
                guard let self, self.generation == id else { return }
                self.stop(message: (error as? VoiceFailure)?.message ?? "Audio upload failed. Check your connection and retry.")
            }
        }
    }

    func stop(message: String = "Voice off") {
        generation = UUID()
        active = false
        status = message
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine?.stop()
        engine = nil
        continuation?.finish()
        continuation = nil
        sendTask?.cancel(); sendTask = nil
        receiveTask?.cancel(); receiveTask = nil
        timeoutTask?.cancel(); timeoutTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

nonisolated private struct VoiceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
