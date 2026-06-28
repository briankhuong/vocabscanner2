import Foundation

struct SM2Scheduler {

    enum Rating: Int, CaseIterable {
        case again = 0
        case hard = 2
        case good = 3
        case easy = 5

        var label: String {
            switch self {
            case .again: return "Again"
            case .hard:  return "Hard"
            case .good:  return "Good"
            case .easy:  return "Easy"
            }
        }
    }

    static func update(card: VocabCard, rating: Rating) {
        let q = rating.rawValue

        switch rating {
        case .again:
            // Full reset
            card.repetitions = 0
            card.interval = 1

        case .hard:
            // Pass with difficulty — shorter interval
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 3        // half of the normal 6
            } else {
                // Grow by 20% instead of full ease factor
                card.interval = max(1, Int(Double(card.interval) * 1.2))
            }
            card.repetitions += 1

        case .good:
            // Standard SM‑2 progression
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(Double(card.interval) * card.easeFactor)
            }
            card.repetitions += 1

        case .easy:
            // Pass with ease — same interval progression as Good,
            // but the ease factor receives a larger boost below
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(Double(card.interval) * card.easeFactor)
            }
            card.repetitions += 1
        }

        // Update ease factor (same formula for all ratings)
        // Again: q=0  → ease drops a lot
        // Hard: q=2  → ease drops moderately
        // Good: q=3  → ease drops slightly
        // Easy: q=5  → ease increases
        card.easeFactor = max(
            1.3,
            card.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02))
        )

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: card.interval,
            to: Date()
        ) ?? Date()
    }
}
