# SaySo

An iPhone camera demo built with SwiftUI, AVFoundation, and Metal.

## Run

Open `SaySo.xcodeproj`, select your signing team and physical iPhone, and press Run. Allow camera access. Keep iPhone Mirroring off while testing; camera blackouts were observed during mirroring in device testing.

The current demo uses portrait orientation. Tap Normal, Black & White, Tint (warm amber), or Vignette. Only one effect is active at a time; Normal resets it. Voice commands use ElevenLabs Scribe Realtime; see setup below.

## Camera pipeline

`AVCaptureVideoDataOutput` delivers BGRA pixel buffers. `CameraFrames` retains only the latest buffer under a lock. `MetalCameraView` uses `CVMetalTextureCache` to expose that buffer to the GPU, then renders it into an `MTKView`. `CameraEffects.metal` rotates the camera image for portrait, crops without stretching, and applies the selected effect. Buttons change a shader parameter without restarting capture.

The display requests 60 refreshes per second; actual camera and display rates depend on the device. GPU work is bounded to three frames in flight, with camera buffers retained until rendering completes. No per-frame SwiftUI images or CPU image conversions are used.

Xcode's Metal Toolchain component is required. If missing, install it with `xcodebuild -downloadComponent MetalToolchain`.

## Device checks

- Verify upright orientation, natural colors, and movement without a growing delay.
- Switch through all four effects, then Normal, while moving the phone.
- Background and reopen the app; confirm the camera resumes and the selected effect remains.
- Test denied camera permission and the Open Settings button.

## Shader verification

On a Metal-capable Mac, run `swift Tests/MetalShaderSmoke.swift` from the project root. This executes the shader on synthetic pixels and checks unchanged colors, grayscale, warm tint, vignette center/edges, reset, and clockwise portrait rotation. Device camera performance still needs testing on an iPhone.

## ElevenLabs voice setup (personal demo)

1. Create an ElevenLabs API key with access to speech-to-text in your ElevenLabs account. Never put it in source control or chat.
2. Run on your iPhone, tap **Voice setup**, enter the key, and Save. The key is stored in the device-only Keychain. Remove it using **Remove saved key**.
3. Tap **Start listening**, allow microphone access, and wait for **Listening…**.
4. Say **black and white**, **tint**, **vignette**, **normal**, or **reset**, with a short pause after each command. Partial text is displayed immediately; finalized phrases change the effect. Unknown speech leaves the effect unchanged. The last recognized keyword/phrase in an utterance wins. This is keyword matching, not semantic interpretation or negation handling.
5. Tap **Stop listening** to end audio transmission. Listening also stops on backgrounding or an audio interruption. Restart it manually when returning.

Microphone audio is sent to ElevenLabs over a secure WebSocket and uses your account's speech-to-text credits. Camera images are never sent. The app does not save audio or transcripts to disk. Provider retention is governed by your ElevenLabs account; this implementation does not request zero retention.

The microphone's supported native sample rate is used with mono signed 16-bit little-endian PCM. Uploads are ordered and bounded; a slow network stops the session instead of accumulating an unlimited audio queue. Permission refusal, connection timeout, service errors, and upload failure show a status message. No automatic reconnect incurs additional listening time.

This user-supplied Keychain key is for personal development. Before distributing an app with your own service credentials, replace it with an authenticated backend that issues ElevenLabs single-use realtime tokens; never bundle your key in a distributed app.

API reference: https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime

Command tests: `swiftc SaySo/VoiceCommand.swift Tests/VoiceCommandSmoke.swift -o /tmp/sayso-command-tests && /tmp/sayso-command-tests`.

Live verification still requires an account key and a physical iPhone: check the command sequence, stop/background behavior, denied permission, invalid key, and network loss while keeping the camera preview active.
