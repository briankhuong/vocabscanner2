import AVFoundation

struct SpeechService {
    private static let synthesizer = AVSpeechSynthesizer()
    private static var audioPlayer: AVAudioPlayer?
    private static let cacheDirectory: URL = {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }()

    static func pronounce(word: String, audioURL: String?) {
        guard let urlString = audioURL, let remoteURL = URL(string: urlString) else {
            print("[Speech] No remote URL – using TTS")
            speakWithTTS(word: word)
            return
        }

        let localFile = cacheDirectory.appendingPathComponent(remoteURL.lastPathComponent)
        print("[Speech] Remote URL: \(remoteURL)")

        if FileManager.default.fileExists(atPath: localFile.path) {
            print("[Speech] Cached file exists, playing local")
            playLocalFile(localFile, fallbackWord: word)
            return
        }

        print("[Speech] Downloading audio file...")
        URLSession.shared.dataTask(with: remoteURL) { data, _, error in
            if let error = error {
                print("[Speech] Download error: \(error.localizedDescription) – falling back to TTS")
                DispatchQueue.main.async { speakWithTTS(word: word) }
                return
            }
            guard let data = data, !data.isEmpty else {
                print("[Speech] Downloaded data is empty – falling back to TTS")
                DispatchQueue.main.async { speakWithTTS(word: word) }
                return
            }
            do {
                try data.write(to: localFile)
                print("[Speech] Saved to \(localFile.path)")
                DispatchQueue.main.async {
                    playLocalFile(localFile, fallbackWord: word)
                }
            } catch {
                print("[Speech] Write error: \(error.localizedDescription) – falling back to TTS")
                DispatchQueue.main.async { speakWithTTS(word: word) }
            }
        }.resume()
    }

    private static func playLocalFile(_ url: URL, fallbackWord: String) {
        // Ensure audio session is configured for playback (works even in silent mode)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("[Speech] Audio session error: \(error)")
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            if audioPlayer?.play() == false {
                print("[Speech] AVAudioPlayer.play() returned false – falling back to TTS")
                speakWithTTS(word: fallbackWord)
            } else {
                print("[Speech] Playing audio file successfully")
            }
        } catch {
            print("[Speech] AVAudioPlayer init error: \(error.localizedDescription) – falling back to TTS")
            speakWithTTS(word: fallbackWord)
        }
    }

    private static func speakWithTTS(word: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        }
    /// Pre‑download an audio file to the cache without playing it.
    static func preloadAudio(from urlString: String?) {
        guard let urlString = urlString, let remoteURL = URL(string: urlString) else { return }
        let localFile = cacheDirectory.appendingPathComponent(remoteURL.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: localFile.path) else { return }

        URLSession.shared.dataTask(with: remoteURL) { data, _, _ in
            guard let data = data else { return }
            try? data.write(to: localFile)
        }.resume()
    }
    /// Speak any English text using on‑device TTS
    static func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
    
}
