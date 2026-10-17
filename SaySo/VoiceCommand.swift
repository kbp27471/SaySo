import Foundation

// Whole words/phrases only. The last recognized command in an utterance wins.
nonisolated enum VoiceCommand {
    static func effectID(in transcript: String) -> UInt32? {
        let words = transcript.lowercased().replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let phrases: [([String], UInt32)] = [
            (["black", "and", "white"], 1), (["grayscale"], 1), (["greyscale"], 1),
            (["tint"], 2), (["vignette"], 3), (["normal"], 0), (["reset"], 0)
        ]
        var result: UInt32?
        for index in words.indices {
            for (phrase, effect) in phrases where index + phrase.count <= words.count {
                if Array(words[index..<(index + phrase.count)]) == phrase { result = effect }
            }
        }
        return result
    }
}
