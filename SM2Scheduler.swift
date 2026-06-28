//
//  SM2Scheduler.swift
//  VocabScanner
//
//  Created by brian.khuong on 28/6/26.
//

import Foundation
import Foundation

struct SM2Scheduler {

    /// Rating values that match Anki's buttons
    enum Rating: Int, CaseIterable {
        case again = 0
        case hard = 2
        case good = 3
        case easy = 5

        var label: String {
            switch self {
            case .again: return "Again"
            case .hard: return "Hard"
            case .good: return "Good"
            case .easy: return "Easy"
            }
        }
    }

    /// Update the card's SRS fields based on the given rating
    static func update(card: VocabCard, rating: Rating) {
        let q = rating.rawValue

        if q < 3 {
            // Failed
            card.repetitions = 0
            card.interval = 1 // show again tomorrow (or same day? Anki shows again after a step)
        } else {
            // Passed
            if card.repetitions == 0 {
                card.interval = 1
            } else if card.repetitions == 1 {
                card.interval = 6
            } else {
                card.interval = Int(Double(card.interval) * card.easeFactor)
            }
            card.repetitions += 1
        }

        // Update ease factor (minimum 1.3)
        card.easeFactor = max(1.3, card.easeFactor + (0.1 - Double(5 - q) * (0.08 + Double(5 - q) * 0.02)))

        // Schedule next review
        card.nextReviewDate = Calendar.current.date(byAdding: .day, value: card.interval, to: Date()) ?? Date()
    }
}
