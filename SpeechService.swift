import AVFoundation

struct SpeechService {
    static let synthesizer = AVSpeechSynthesizer()
    private static let session = AVAudioSession.sharedInstance()

    static func speak(word: String) {
        // Configure audio session for playback (ignores silent switch)
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
