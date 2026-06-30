import Foundation

struct MerriamWebster {
    static let apiKey = "02a65e0d-aeb8-4576-972c-58d0fb4ea245"   // ← put your real key here
    
    // 👇 Updated to return multiple senses and global word properties
    struct DefinitionResult {
        let senses: [DictionarySense] // Contains multiple definitions, examples, wordTypes, etc.
        let pronunciation: String?    // Phonetic text applies to the whole word
        let origin: String?           // Origin applies to the whole word
    }
    
    /// Fetch definitions + examples + pronunciation from Merriam‑Webster Learner's Dictionary
    /// Fetch definitions + examples + pronunciation from Merriam‑Webster Learner's Dictionary
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
              !jsonArray.isEmpty else {
            return nil
        }
        
        // If MW returns strings, it means the word was not found and it's offering spelling suggestions
        if let suggestion = jsonArray.first as? String {
            throw NSError(domain: "MW", code: 404, userInfo: [NSLocalizedDescriptionKey: "Did you mean \(suggestion)?"])
        }
        
        // Use the first entry just for global word properties (Origin & Pronunciation)
        guard let firstEntryDict = jsonArray.first as? [String: Any] else { return nil }
        
        // 1. Extract Word-level properties (Origin)
        let origin: String? = {
            guard let et = firstEntryDict["et"] as? [[Any]] else { return nil }
            for part in et {
                if part.first as? String == "text", part.count > 1, let text = part[1] as? String {
                    return text
                }
            }
            return nil
        }()
        
        // 2. Pronunciation & Audio URL
        var pronunciation: String? = nil
        var audioURL: String? = nil
        if let hwi = firstEntryDict["hwi"] as? [String: Any], let prs = hwi["prs"] as? [[String: Any]] {
            pronunciation = (prs.first?["mw"] as? String) ?? (prs.first?["ipa"] as? String)
            if let sound = prs.first?["sound"] as? [String: Any], let audioKey = sound["audio"] as? String {
                let subdir: String
                let lowerKey = audioKey.lowercased()
                if lowerKey.hasPrefix("bix") { subdir = "bix" }
                else if lowerKey.hasPrefix("gg") { subdir = "gg" }
                else if let firstChar = lowerKey.first, firstChar.isNumber { subdir = "number" }
                else { subdir = String(lowerKey.prefix(1)) }
                audioURL = "https://media.merriam-webster.com/soundc11/\(subdir)/\(audioKey).wav"
            }
        }
        
        // 3. Extract multiple Senses (Loop through multiple Homographs in jsonArray!)
        var extractedSenses: [DictionarySense] = []
        
        for element in jsonArray {
            guard let entryDict = element as? [String: Any] else { continue }
            let wordType = entryDict["fl"] as? String
            
            if let defs = entryDict["def"] as? [[String: Any]] {
                for firstDef in defs {
                    guard let sseq = firstDef["sseq"] as? [[Any]] else { continue }
                    
                    for senseArray in sseq {
                        var currentDef = ""
                        var currentExample: String? = nil
                        var registerLabel: String? = nil
                        
                        for senseElement in senseArray {
                            var senseDict: [String: Any]?
                            if let arr = senseElement as? [Any], arr.count >= 2, let type = arr[0] as? String, type == "sense" || type == "sen" || type == "bs" {
                                senseDict = arr[1] as? [String: Any]
                            } else if let dict = senseElement as? [String: Any] {
                                senseDict = dict
                            }
                            
                            guard let senseData = senseDict else { continue }

                            registerLabel = (senseData["sls"] as? [String])?.first

                            // Helper to scan a dt array for both definition text and example sentences
                            func scanDtArray(_ dtArray: [[Any]]) {
                                for dt in dtArray {
                                    guard let first = dt.first as? String, dt.count > 1 else { continue }
                                    
                                    if first == "text", let defText = dt[1] as? String, currentDef.isEmpty {
                                        currentDef = defText
                                    }
                                    
                                    if first == "vis", let examples = dt[1] as? [Any], let firstObj = examples.first {
                                        if let s = firstObj as? String { currentExample = s }
                                        else if let dict = firstObj as? NSDictionary, let t = dict["t"] as? String { currentExample = t }
                                    }
                                }
                            }

                            // 1. Check the sense's top-level dt array
                            if let dtArray = senseData["dt"] as? [[Any]] {
                                scanDtArray(dtArray)
                            }

                            // 2. Some senses nest their actual content (including examples) under "sdsense"
                            //    (a divided/secondary sense block) rather than the top-level dt.
                            if currentExample == nil, let sdsense = senseData["sdsense"] as? [String: Any],
                               let sdDtArray = sdsense["dt"] as? [[Any]] {
                                scanDtArray(sdDtArray)
                            }
                        }
                        
                        // Clean up tags
                        if let regex = try? NSRegularExpression(pattern: "\\{[^}]+\\}", options: []) {
                            let defRange = NSRange(currentDef.startIndex..., in: currentDef)
                            currentDef = regex.stringByReplacingMatches(in: currentDef, range: defRange, withTemplate: "").trimmingCharacters(in: .whitespaces)
                            
                            if let ex = currentExample {
                                let exRange = NSRange(ex.startIndex..., in: ex)
                                currentExample = regex.stringByReplacingMatches(in: ex, range: exRange, withTemplate: "").trimmingCharacters(in: .whitespaces)
                            }
                        }
                        
                        if !currentDef.isEmpty && extractedSenses.count < 6 {
                            extractedSenses.append(DictionarySense(
                                definition: currentDef,
                                example: currentExample,
                                wordType: wordType,
                                registerLabel: registerLabel,
                                pronunciationAudioURL: audioURL
                            ))
                        }
                    }
                }
            }
            
            // Stop parsing if we have gathered plenty of senses
            if extractedSenses.count >= 6 { break }
        }
        
        // Fallback
        if extractedSenses.isEmpty, let shortDefs = firstEntryDict["shortdef"] as? [String] {
            let fallbackWordType = firstEntryDict["fl"] as? String
            for shortDef in shortDefs.prefix(3) {
                extractedSenses.append(DictionarySense(
                    definition: shortDef,
                    example: nil,
                    wordType: fallbackWordType,
                    registerLabel: nil,
                    pronunciationAudioURL: audioURL
                ))
            }
        }
        
        return DefinitionResult(
            senses: extractedSenses,
            pronunciation: pronunciation,
            origin: origin
        )
    }

}
