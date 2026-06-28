import Foundation
import SwiftData

struct ActivityLogger {
    /// Increments wordsAdded for today by 1. Creates today's log if needed.
    static func logWordAdded(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.date == today }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.wordsAdded += 1
        } else {
            let log = ActivityLog(date: today)
            log.wordsAdded = 1
            context.insert(log)
        }
        try? context.save()
    }

    /// Increments reviewsCompleted for today by 1. Creates today's log if needed.
    static func logReviewCompleted(context: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<ActivityLog>(
            predicate: #Predicate { $0.date == today }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.reviewsCompleted += 1
        } else {
            let log = ActivityLog(date: today)
            log.reviewsCompleted = 1
            context.insert(log)
        }
        try? context.save()
    }
}
