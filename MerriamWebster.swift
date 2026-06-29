import Foundation

struct MerriamWebster {
    static let apiKey = "02a65e0d-aeb8-4576-972c-58d0fb4ea245"   // ← put your real key here

    struct DefinitionResult {
        let definition: String
        let example: String?
        let pronunciation: String?
        let audioURL: String?        // remote audio file for perfect pronunciation
    }

    /// Fetch definition + example + pronunciation from Merriam‑Webster Learner's Dictionary
    static func lookup(word: String) async throws -> DefinitionResult? {
        let trimmed = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.dictionaryapi.com/api/v3/references/learners/json/\(encoded)?key=\(apiKey)") else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let firstElement = jsonArray.first else {
            return nil
        }

        // If the first element is a string, it's a suggestion (word not found)
        if let suggestion = firstElement as? String {
            throw NSError(domain: "MW", code: 404, userInfo: [NSLocalizedDescriptionKey: "Did you mean \(suggestion)?"])
        }

        // Now it must be a dictionary
        guard let entryDict = firstElement as? [String: Any] else { return nil }

        // Definition
        let shortDefs = entryDict["shortdef"] as? [String]
        let definition = shortDefs?.first ?? ""

        // Example sentence – drill into "def" -> "sseq" -> sense -> "dt" with "vis"
        var example: String? = nil
        if let defs = entryDict["def"] as? [[String: Any]],
           let firstDef = defs.first,
           let sseq = firstDef["sseq"] as? [[Any]] {
            for senseArray in sseq {
                for senseElement in senseArray {
                    if let senseDict = senseElement as? [String: Any],
                       let dtArray = senseDict["dt"] as? [[Any]],
                       let dt = dtArray.first(where: { ($0.first as? String) == "vis" }) {
                        // dt format: ["vis", ["{it}word", "Example sentence"]]
                        if dt.count > 1, let examples = dt[1] as? [Any], let firstExample = examples.first as? String {
                            example = firstExample
                                .replacingOccurrences(of: "{it}", with: "")
                                .replacingOccurrences(of: "{/it}", with: "")
                                .replacingOccurrences(of: "{bc}", with: "")
                                .replacingOccurrences(of: "{sc}", with: "")
                                .replacingOccurrences(of: "{/sc}", with: "")
                            break
                        }
                    }
                }
            }
        }

        // Pronunciation
        var pronunciation: String? = nil
        if let hwi = entryDict["hwi"] as? [String: Any],
           let prs = hwi["prs"] as? [[String: Any]],
           let mw = prs.first?["mw"] as? String {
            pronunciation = mw   // e.g., "ˈhe-lō"
        }

        // Build audio URL from the first "prs" entry
        var audioURL: String? = nil
        if let hwi = entryDict["hwi"] as? [String: Any],
           let prs = hwi["prs"] as? [[String: Any]],
           let sound = prs.first?["sound"] as? [String: Any],
           let audioKey = sound["audio"] as? String {
            let subdir: String
            let lowerKey = audioKey.lowercased()
            if lowerKey.hasPrefix("bix") { subdir = "bix" }
            else if lowerKey.hasPrefix("gg") { subdir = "gg" }
            else if let firstChar = lowerKey.first, firstChar.isNumber { subdir = "number" }
            else { subdir = String(lowerKey.prefix(1)) }
            audioURL = "https://media.merriam-webster.com/soundc11/\(subdir)/\(audioKey).wav"
            print("[MW Audio] key=\(audioKey) -> URL=\(audioURL ?? "nil")")
        } else {
            print("[MW Audio] No audio key found in response")
        }

        return DefinitionResult(definition: definition, example: example, pronunciation: pronunciation, audioURL: audioURL)
    }
}
