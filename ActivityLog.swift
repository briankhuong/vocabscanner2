import Foundation
import SwiftData

@Model
final class ActivityLog {
    @Attribute(.unique) var date: Date  // date normalized to midnight
    var wordsAdded: Int = 0
    var reviewsCompleted: Int = 0

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }
}
