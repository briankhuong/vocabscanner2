import Foundation

struct PronunciationService {
    static var subscriptionKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let key = dict["AzureSpeechKey"] as? String else {
            fatalError("CRITICAL: Missing Secrets.plist or AzureSpeechKey. Please create it.")
        }
        return key
    }

    static let region = "eastus"

    struct AssessmentResult {
        let overallScore: Double
        let wordResults: [WordResult]
    }

    struct WordResult {
        let word: String
        let accuracyScore: Double
        let phonemes: [PhonemeResult]
    }

    // 👈 Made Identifiable so SwiftUI doesn't complain
    struct PhonemeResult: Identifiable {
        let id = UUID()
        let text: String
        let accuracyScore: Double
    }

    static func assessPronunciation(audioData: Data, expectedText: String) async throws -> AssessmentResult {
        let tempDir = FileManager.default.temporaryDirectory
        let wavURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
        try writeStandardWAV(data: audioData, to: wavURL)

        // Added format=detailed for deep phoneme breakdowns
        let endpoint = "https://\(region).stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed"
        guard let url = URL(string: endpoint) else { throw NSError(domain: "Invalid URL", code: 0) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("audio/wav; codecs=audio/pcm; samplerate=16000", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")

        let assessmentParameters: [String: Any] = [
            "ReferenceText": expectedText.trimmingCharacters(in: .punctuationCharacters),
            "GradingSystem": "HundredMark",
            "Granularity": "Phoneme",
            "PhonemeAlphabet": "IPA" // 👈 Requesting IPA symbols!
        ]

        guard let paramData = try? JSONSerialization.data(withJSONObject: assessmentParameters) else {
            throw NSError(domain: "InvalidAssessmentJSON", code: 0)
        }
        
        let base64ParamString = paramData.base64EncodedString()
        request.setValue(base64ParamString, forHTTPHeaderField: "Pronunciation-Assessment")

        let fileData = try Data(contentsOf: wavURL)
        request.httpBody = fileData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "NoResponse", code: 0)
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        print("[Pronunciation] Status: \(httpResponse.statusCode)")
        print("[Pronunciation] Body: \(body)")

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "Assessment failed", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nBest = json["NBest"] as? [[String: Any]],
              let firstResult = nBest.first,
              let words = firstResult["Words"] as? [[String: Any]] else {
            throw NSError(domain: "InvalidResponse", code: 0)
        }

        let overallScore = firstResult["AccuracyScore"] as? Double ?? 0

        var wordResults = [WordResult]()
        for w in words {
            guard let wordText = w["Word"] as? String else { continue }
            let wordScore = w["AccuracyScore"] as? Double ?? 0
            
            var phonemes = [PhonemeResult]()
            if let phs = w["Phonemes"] as? [[String: Any]] {
                for ph in phs {
                    if let phonemeText = ph["Phoneme"] as? String,
                       let phonemeScore = ph["AccuracyScore"] as? Double {
                        phonemes.append(PhonemeResult(text: phonemeText, accuracyScore: phonemeScore))
                    }
                }
            }
            wordResults.append(WordResult(word: wordText, accuracyScore: wordScore, phonemes: phonemes))
        }

        return AssessmentResult(overallScore: overallScore, wordResults: wordResults)
    }

    private static func writeStandardWAV(data: Data, to url: URL) throws {
        let sampleRate: UInt32 = 16000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(data.count)

        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian, Array.init))
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        var wavData = header
        wavData.append(data)
        try wavData.write(to: url)
    }
}
