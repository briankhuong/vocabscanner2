//
//  ReviewSessionView.swift
//  VocabScanner
//
//  Created by brian.khuong on 28/6/26.
//

import Foundation
import SwiftUI
import SwiftData

struct ReviewSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VocabCard.nextReviewDate) private var allCards: [VocabCard]
    @State private var currentCardIndex = 0
    @State private var isShowingAnswer = false
    @State private var sessionCompleted = false
    @State private var reviewedCount = 0

    // Cards due today
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
                    // Progress
                    ProgressView(value: Double(currentCardIndex), total: Double(dueCards.count))
                        .padding(.horizontal)

                    Spacer()

                    // Blanked sentence
                    Text(blankSentence(card.contextSentence, word: card.word))
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if isShowingAnswer {
                        VStack(spacing: 8) {
                            Text(card.word)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)

                            Text(card.translation)
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }

                    Spacer()

                    if !isShowingAnswer {
                        Button("Show Answer") {
                            withAnimation {
                                isShowingAnswer = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
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
            }
        }
    }

    private func blankSentence(_ sentence: String, word: String) -> String {
        // Replace the target word (case-insensitive, whole word) with "..."
        // This is a simple replacement; for better results you might want
        // to create a regular expression with word boundaries.
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

        // Move to next card
        withAnimation {
            isShowingAnswer = false
            if currentCardIndex + 1 < dueCards.count {
                currentCardIndex += 1
            } else {
                sessionCompleted = true
            }
        }

        // Save context
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
