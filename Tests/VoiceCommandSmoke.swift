import Foundation

@main struct VoiceCommandSmoke {
    static func main() {
        let cases: [(String, UInt32?)] = [
            ("Black and white!", 1), ("black & white", 1), ("Please use grayscale", 1),
            ("greyscale", 1), ("tint", 2), ("vignette.", 3), ("normal", 0), ("reset", 0),
            ("black and white then normal", 0), ("normal then vignette", 3),
            ("abnormal", nil), ("tinted", nil), ("hello there", nil), ("", nil)
        ]
        for (text, expected) in cases {
            precondition(VoiceCommand.effectID(in: text) == expected, "Incorrect command: \(text)")
        }
        print("PASS: \(cases.count) command cases, including reset, punctuation, unknown speech, and last-command precedence")
    }
}
