import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabCard.nextReviewDate) private var allCards: [VocabCard]
    @State private var currentCardIndex = 0
    @State private var step: Step = .definition
    @State private var sessionCompleted = false
    @State private var reviewedCount = 0

    enum Step {
        case definition   // show definition, tap for hint
        case hint         // show blanked sentence, tap for answer
        case answer       // show word + translation, then rate
    }

    private var dueCards: [VocabCard] {
        allCards.filter { $0.nextReviewDate <= Date() }
    }

    var body: some View {
        Group {
            if dueCards.isEmpty {
                ContentUnavailableView(
                    "All caught up! 🎉",
                    systemImage: "checkmark.rectangle.stack",
                    description: Text("No cards to review right now.")
                )
            } else if sessionCompleted {
                VStack(spacing: 20) {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    Text("Session Complete")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("You reviewed \(reviewedCount) card(s).")
                        .foregroundColor(.secondary)
                }
            } else if currentCardIndex < dueCards.count {
                let card = dueCards[currentCardIndex]
                VStack(spacing: 24) {
                    // Progress bar
                    ProgressView(value: Double(currentCardIndex), total: Double(dueCards.count))
                        .padding(.horizontal)

                    Spacer()

                    // Card content based on step
                    switch step {
                    case .definition:
                        VStack(spacing: 16) {
                            Text("Definition")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(displayedDefinition(card.definition))
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button("Show Hint") {
                                withAnimation { step = .hint }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                    case .hint:
                        VStack(spacing: 16) {
                            Text("Hint: Example Sentence")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(blankSentence(card.contextSentence, word: card.word))
                                .font(.title2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            Button("Show Answer") {
                                withAnimation { step = .answer }
                            }
                            .buttonStyle(.borderedProminent)
                        }

                    case .answer:
                        VStack(spacing: 16) {
                            // Word and translation
                            VStack(spacing: 6) {
                                Text(card.word)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.accentColor)

                                Text(card.translation)
                                    .font(.title3)
                                    .foregroundColor(.primary)
                            }
                            .padding(.bottom, 8)

                            // Optionally show full example sentence again
                            Text(card.contextSentence)
                                .font(.callout)
                                .italic()
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            // Rating buttons
                            HStack(spacing: 12) {
                                ForEach(SM2Scheduler.Rating.allCases, id: \.rawValue) { rating in
                                    Button(rating.label) {
                                        rateCard(card, rating: rating)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(ratingColor(rating))
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    // MARK: - Helpers

    private func displayedDefinition(_ def: String?) -> String {
        guard let def = def, !def.isEmpty, def != "Definition not found." else {
            return "Definition not available."
        }
        return def
    }

    private func blankSentence(_ sentence: String, word: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return sentence
        }
        let range = NSRange(sentence.startIndex..., in: sentence)
        return regex.stringByReplacingMatches(in: sentence, range: range, withTemplate: "________")
    }

    private func rateCard(_ card: VocabCard, rating: SM2Scheduler.Rating) {
        SM2Scheduler.update(card: card, rating: rating)
        reviewedCount += 1

        ActivityLogger.logReviewCompleted(context: modelContext)   // ← added

        withAnimation {
            step = .definition
            if currentCardIndex + 1 < dueCards.count {
                currentCardIndex += 1
            } else {
                sessionCompleted = true
            }
        }

        try? modelContext.save()
    }

    private func ratingColor(_ rating: SM2Scheduler.Rating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }
}
