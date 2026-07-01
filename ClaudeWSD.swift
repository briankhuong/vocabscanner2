import Foundation

struct LLMWSD {
    // ── Read credentials from Secrets.plist ───────────────────────────────────
    private static var secrets: [String: Any] = {
        guard let url  = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any]
        else {
            fatalError("[LLMWSD] Secrets.plist not found in bundle. " +
                       "Add it to the target and ensure it is included in Copy Bundle Resources.")
        }
        return dict
    }()

    private static var apiKey: String = {
        guard let key = secrets["LLM_API_KEY"] as? String, !key.isEmpty else {
            fatalError("[LLMWSD] 'LLM_API_KEY' missing or empty in Secrets.plist.")
        }
        return key
    }()

    private static var baseURL: String = {
        guard let url = secrets["LLM_BASE_URL"] as? String, !url.isEmpty else {
            fatalError("[LLMWSD] 'LLM_BASE_URL' missing or empty in Secrets.plist.")
        }
        return url
    }()

    private static var model: String = {
        guard let model = secrets["LLM_MODEL"] as? String, !model.isEmpty else {
            fatalError("[LLMWSD] 'LLM_MODEL' missing or empty in Secrets.plist.")
        }
        return model
    }()
    // ──────────────────────────────────────────────────────────────────────────

    struct WSDResult {
        let bestIndex: Int      // 0-based into the senses array
        let confidence: Double  // 0.0 – 1.0
    }

    static func selectBestSense(
        word: String,
        sentence: String,
        senses: [DictionarySense]
    ) async -> WSDResult? {
        guard !senses.isEmpty else { return nil }

        let definitionList = senses.enumerated().map { i, sense -> String in
            let pos     = sense.wordType.map { "[\($0)] " } ?? ""
            let example = sense.example.map { " | e.g. \($0)" } ?? ""
            return "\(i + 1). \(pos)\(sense.definition)\(example)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a dictionary sense selector.
        Given a target word, the sentence it appears in, and a numbered list of \
        dictionary definitions, you return ONLY a JSON object with two fields:
          bestDefinition  – the number (1-based) of the best-matching definition
          confidence      – your confidence as a float between 0.0 and 1.0
        No explanation. No markdown. No extra keys. Just the JSON object.
        """

        let userPrompt = """
        Word: \(word)
        Sentence: \(sentence)

        Definitions:
        \(definitionList)
        """

        guard let url = URL(string: baseURL) else {
            print("[LLMWSD] Invalid base URL: \(baseURL)")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 64,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userPrompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return nil }
            guard http.statusCode == 200 else {
                let raw = String(data: data, encoding: .utf8) ?? "?"
                print("[LLMWSD] HTTP \(http.statusCode): \(raw)")
                return nil
            }

            guard
                let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let text    = message["content"] as? String
            else { return nil }

            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```",     with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let resultData = cleaned.data(using: .utf8),
                let result     = try? JSONSerialization.jsonObject(with: resultData) as? [String: Any],
                let bestDef    = result["bestDefinition"] as? Int,
                let confidence = result["confidence"]     as? Double
            else {
                print("[LLMWSD] Failed to parse response: \(text)")
                return nil
            }

            let zeroIndex = bestDef - 1
            guard senses.indices.contains(zeroIndex) else { return nil }

            print("[LLMWSD] Selected sense \(bestDef) with confidence \(confidence)")
            return WSDResult(bestIndex: zeroIndex, confidence: confidence)

        } catch {
            print("[LLMWSD] Request error: \(error)")
            return nil
        }
    }
}
