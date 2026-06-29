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

        if let suggestion = firstElement as? String {
            throw NSError(domain: "MW", code: 404, userInfo: [NSLocalizedDescriptionKey: "Did you mean \(suggestion)?"])
        }

        guard let entryDict = firstElement as? [String: Any] else { return nil }

        // Definition
        let shortDefs = entryDict["shortdef"] as? [String]
        let definition = shortDefs?.first ?? ""

        var example: String? = nil
        print("[MW Debug] Starting example extraction")
        if let defs = entryDict["def"] as? [[String: Any]],
           let firstDef = defs.first,
           let sseq = firstDef["sseq"] as? [[Any]] {
            print("[MW Debug] sseq count: \(sseq.count)")
            for senseArray in sseq {
                for senseElement in senseArray {
                    // senseElement can be:
                    //   - a 2-element array ["sense", {dt: ...}] or ["sen", ...] or ["bs", ...]
                    //   - directly a dictionary (less common)
                    var senseDict: [String: Any]?
                    if let arr = senseElement as? [Any], arr.count >= 2, let type = arr[0] as? String, type == "sense" || type == "sen" || type == "bs" {
                        senseDict = arr[1] as? [String: Any]
                    } else if let dict = senseElement as? [String: Any] {
                        senseDict = dict
                    }
                    
                    guard let senseDict = senseDict,
                          let dtArray = senseDict["dt"] as? [[Any]] else { continue }
                    
                    print("[MW Debug] dtArray count: \(dtArray.count)")
                    for dt in dtArray {
                        if let first = dt.first as? String, first == "vis", dt.count > 1,
                           let examples = dt[1] as? [Any], let firstObj = examples.first {
                            print("[MW Debug] vis example type: \(type(of: firstObj)) value: \(firstObj)")
                            if let s = firstObj as? String {
                                example = s
                            } else if let dict = firstObj as? NSDictionary, let t = dict["t"] as? String {
                                example = t
                            }
                            break  // take first example from this vis
                        }
                    }
                }
            }
        } else {
            print("[MW Debug] Could not extract def/sseq")
        }
        
        // Clean up all formatting tokens (e.g., {it}, {/it}, {phrase}, {/phrase}, {wi}, etc.)
        if let ex = example {
            if let regex = try? NSRegularExpression(pattern: "\\{[^}]+\\}", options: []) {
                let range = NSRange(ex.startIndex..., in: ex)
                example = regex.stringByReplacingMatches(in: ex, range: range, withTemplate: "")
            }
        }
        print("[MW Example] parsed example = \(example ?? "nil")")
        // Pronunciation
        var pronunciation: String? = nil
        if let hwi = entryDict["hwi"] as? [String: Any],
           let prs = hwi["prs"] as? [[String: Any]],
           let mw = prs.first?["mw"] as? String {
            pronunciation = mw
        }

        // Build audio URL
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
