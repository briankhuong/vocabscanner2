import Foundation
import SwiftUI

final class APIWarmup {

    static let shared = APIWarmup()
    private init() {}

    // Call this from the app's foreground lifecycle event
    func warmUpAll() {
        Task.detached(priority: .background) {
            async let groq = Self.pingGroq()
            async let mw   = Self.pingMerriamWebster()
            _ = await (groq, mw)   // fire both concurrently
        }
    }

    // ── Groq / Llama ──────────────────────────────────────────────────────────
    private static func pingGroq() async {
        // Read credentials the same way LLMWSD does
        guard
            let url  = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: url) as? [String: Any],
            let apiKey  = dict["LLM_API_KEY"]  as? String, !apiKey.isEmpty,
            let baseURL = dict["LLM_BASE_URL"] as? String, !baseURL.isEmpty,
            let model   = dict["LLM_MODEL"]    as? String, !model.isEmpty,
            let endpoint = URL(string: baseURL)
        else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8

        // Minimal 1-token request — just enough to wake the model
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1,
            "temperature": 0,
            "messages": [["role": "user", "content": "hi"]]
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = httpBody

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Warmup] Groq ping status: \(status)")
        } catch {
            print("[Warmup] Groq ping failed: \(error.localizedDescription)")
        }
    }

    // ── Merriam-Webster ───────────────────────────────────────────────────────
    private static func pingMerriamWebster() async {
        // Ping with a guaranteed common word — just verifies the connection
        let word = "run"
        guard let url = URL(string:
            "https://www.dictionaryapi.com/api/v3/references/learners/json/\(word)?key=\(MerriamWebster.apiKey)")
        else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Warmup] MW ping status: \(status)")
        } catch {
            print("[Warmup] MW ping failed: \(error.localizedDescription)")
        }
    }
}
