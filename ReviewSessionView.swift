import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabCard.nextReviewDate) private var allCards: [VocabCard]
    @AppStorage("maxDailyReviews") private var maxDailyReviews = 20
    @AppStorage("learningStyle") private var learningStyle = LearningStyle.definitionFirst.rawValue
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
        let allDue = allCards.filter { $0.nextReviewDate <= Date() }
        if maxDailyReviews > 0 {
            return Array(allDue.prefix(maxDailyReviews))
        } else {
            return allDue
        }
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
                let currentStyle = LearningStyle(rawValue: learningStyle) ?? .definitionFirst

                VStack(spacing: 24) {
                    // Progress bar
                    ProgressView(value: Double(currentCardIndex), total: Double(dueCards.count))
                        .padding(.horizontal)

                    Spacer()

                    // Card content based on learning style
                    // Card content based on learning style
                    switch currentStyle {
                    case .definitionFirst:
                        Group {
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
                                answerView(for: card)
                            }
                        }
                        .id(card.id)
                        .transition(.opacity)

                    case .wordFirst:
                        Group {
                            switch step {
                            case .definition:
                                VStack(spacing: 16) {
                                    Text(card.word)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)

                                    Button("Show Definition") {
                                        withAnimation { step = .hint }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                            case .hint:
                                VStack(spacing: 16) {
                                    Text(card.word)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)

                                    if let def = card.definition, !def.isEmpty, def != "Definition not found." {
                                        VStack(spacing: 8) {
                                            Text("Definition")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(def)
                                                .font(.title3)
                                                .multilineTextAlignment(.center)
                                        }
                                    } else {
                                        Text("Definition not available.")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                    }

                                    Button("Show Example & Translation") {
                                        withAnimation { step = .answer }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                            case .answer:
                                VStack(spacing: 16) {
                                    Text(card.word)
                                        .font(.largeTitle)
                                        .fontWeight(.bold)

                                    VStack(spacing: 8) {
                                        if !card.translation.isEmpty && card.translation != "Translation unavailable" {
                                            Text(card.translation)
                                                .font(.title3)
                                                .foregroundColor(.green)
                                        }
                                        Text(card.contextSentence)
                                            .font(.callout)
                                            .italic()
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .id(card.id)
                        .transition(.opacity)

                    case .cloze:
                        Group {
                            switch step {
                            case .definition:
                                VStack(spacing: 16) {
                                    Text(blankSentence(card.contextSentence, word: card.word))
                                        .font(.title2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)

                                    Button("Show Hint") {
                                        withAnimation { step = .hint }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                            case .hint:
                                VStack(spacing: 16) {
                                    Text(blankSentence(card.contextSentence, word: card.word))
                                        .font(.title2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)

                                    if let def = card.definition, !def.isEmpty, def != "Definition not found." {
                                        VStack(spacing: 8) {
                                            Text("Definition")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(def)
                                                .font(.title3)
                                                .multilineTextAlignment(.center)
                                        }
                                    } else {
                                        Text("Definition not available.")
                                            .font(.callout)
                                            .foregroundColor(.secondary)
                                    }

                                    Button("Show Answer") {
                                        withAnimation { step = .answer }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }

                            case .answer:
                                VStack(spacing: 16) {
                                    VStack(spacing: 6) {
                                        Text(card.word)
                                            .font(.largeTitle)
                                            .fontWeight(.bold)
                                            .foregroundColor(.accentColor)
                                        if !card.translation.isEmpty && card.translation != "Translation unavailable" {
                                            Text(card.translation)
                                                .font(.title3)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding(.bottom, 8)

                                    Text(card.contextSentence)
                                        .font(.callout)
                                        .italic()
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .id(card.id)
                        .transition(.opacity)
                    }

                    Spacer()

                    // Rating buttons (only after answer is revealed)
                    if step == .answer {
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
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }
    @ViewBuilder
    private func answerView(for card: VocabCard) -> some View {
        VStack(spacing: 16) {
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

            Text(card.contextSentence)
                .font(.callout)
                .italic()
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
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
