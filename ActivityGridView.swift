import SwiftUI
import SwiftData

struct ActivityGridView: View {
    @Query(sort: \ActivityLog.date, order: .reverse) private var logs: [ActivityLog]

    private let spacing: CGFloat = 2
    private let blockLengthMonths = 6
    private let monthLabelHeight: CGFloat = 10
    private let dayLabelWidth: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity")
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let columnCount = weeks.count
                let squareSize = max(8, min(14, (totalWidth - dayLabelWidth - CGFloat(columnCount) * spacing) / CGFloat(columnCount)))

                VStack(spacing: spacing) {
                    // Row 0: Month labels
                    HStack(spacing: spacing) {
                        Color.clear.frame(width: dayLabelWidth, height: monthLabelHeight)
                        ForEach(0..<columnCount, id: \.self) { index in
                            Text(monthLabelForWeek(at: index))
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                                .frame(width: squareSize, height: monthLabelHeight, alignment: .leading)
                                .minimumScaleFactor(0.6)
                        }
                    }

                    // Rows 1‑7: Day labels + squares
                    ForEach(0..<7, id: \.self) { rowIndex in
                        HStack(spacing: spacing) {
                            Text(dayLabelForRow(rowIndex))
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                                .frame(width: dayLabelWidth, height: squareSize)

                            ForEach(0..<columnCount, id: \.self) { colIndex in
                                let week = weeks[colIndex]
                                if rowIndex < week.count {
                                    let cell = week[rowIndex]
                                    Rectangle()
                                        .fill(color(for: cell.count))
                                        .frame(width: squareSize, height: squareSize)
                                        .cornerRadius(1.5)
                                } else {
                                    Color.clear.frame(width: squareSize, height: squareSize)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: monthLabelHeight + 7 * 14 + 6 * spacing + 4)
        }
    }

    // MARK: - Helpers

    private func monthLabelForWeek(at index: Int) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        guard index >= 0, index < weeks.count else { return "" }
        let week = weeks[index]
        guard let realDay = week.first(where: { $0.date > Date.distantPast })?.date else { return "" }

        if index == 0 { return formatter.string(from: realDay) }

        let previousWeek = weeks[index - 1]
        guard let prevRealDay = previousWeek.first(where: { $0.date > Date.distantPast })?.date else {
            return formatter.string(from: realDay)
        }
        let currentMonth = calendar.component(.month, from: realDay)
        let previousMonth = calendar.component(.month, from: prevRealDay)
        return currentMonth != previousMonth ? formatter.string(from: realDay) : ""
    }

    private var blockStart: Date {
        let calendar = Calendar.current
        let today = Date()

        let firstActivityMonth: Date
        if let firstLog = logs.min(by: { $0.date < $1.date }) {
            firstActivityMonth = calendar.dateInterval(of: .month, for: firstLog.date)?.start ?? today
        } else {
            firstActivityMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        }

        var start = firstActivityMonth
        while true {
            guard let blockEndMonth = calendar.date(byAdding: .month, value: blockLengthMonths - 1, to: start),
                  let endOfBlock = calendar.dateInterval(of: .month, for: blockEndMonth)?.end else { break }
            if today > endOfBlock {
                guard let newStart = calendar.dateInterval(of: .month, for: blockEndMonth)?.start else { break }
                start = newStart
            } else {
                break
            }
        }
        return start
    }

    private var weeks: [[GridCell]] {
        let calendar = Calendar.current
        let startDate = blockStart

        guard let blockEndMonth = calendar.date(byAdding: .month, value: blockLengthMonths - 1, to: startDate),
              let endDate = calendar.dateInterval(of: .month, for: blockEndMonth)?.end else { return [] }

        var allCells = [GridCell]()
        var current = startDate
        while current < endDate {
            let log = logs.first { calendar.isDate($0.date, inSameDayAs: current) }
            let count = (log?.wordsAdded ?? 0) + (log?.reviewsCompleted ?? 0)
            allCells.append(GridCell(date: current, count: count))
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        // Pad start to Monday
        let firstWeekday = calendar.component(.weekday, from: allCells.first?.date ?? Date())
        let paddingDays = (firstWeekday + 5) % 7
        for _ in 0..<paddingDays {
            allCells.insert(GridCell(date: Date.distantPast, count: 0), at: 0)
        }

        var weeksArray = stride(from: 0, to: allCells.count, by: 7).map {
            Array(allCells[$0..<min($0+7, allCells.count)])
        }
        // Pad last week to exactly 7 cells (no missing rows)
        if let lastWeek = weeksArray.last, lastWeek.count < 7 {
            var padded = lastWeek
            for _ in padded.count..<7 {
                padded.append(GridCell(date: Date.distantPast, count: 0))
            }
            weeksArray[weeksArray.count - 1] = padded
        }
        return weeksArray
    }

    private func dayLabelForRow(_ row: Int) -> String {
        switch row {
        case 0: return "M"
        case 2: return "W"
        case 4: return "F"
        default: return ""
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.1)
        case 1: return .green.opacity(0.3)
        case 2: return .green.opacity(0.5)
        case 3: return .green.opacity(0.7)
        default: return .green
        }
    }

    struct GridCell: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let count: Int
    }
}
