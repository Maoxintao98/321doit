import Foundation

struct ShootingDayRescheduleOutcome: Equatable {
    let selectedDayID: UUID
    let displacedDayID: UUID?
}

enum ShootingDayScheduling {
    /// Finds the first unoccupied calendar date on or after `date`. Shooting
    /// days are calendar-keyed in the planning UI, so duplicate dates would
    /// make one record appear to vanish behind another.
    static func nextAvailableDate(
        startingAt date: Date,
        days: [ShootingDay],
        calendar: Calendar = .current
    ) -> Date {
        var candidate = calendar.startOfDay(for: date)
        let occupied = Set(days.map { calendar.startOfDay(for: $0.date) })
        while occupied.contains(candidate) {
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return candidate
            }
            candidate = followingDay
        }
        return candidate
    }

    /// Moves a shooting-day record while preserving every record's stable ID
    /// and payload. Occupied destination dates are handled by exchanging the
    /// two dates, so the calendar never hides one record behind another.
    static func reschedule(
        days: inout [ShootingDay],
        dayID: UUID,
        to date: Date,
        calendar: Calendar = .current
    ) -> ShootingDayRescheduleOutcome? {
        guard let currentIndex = days.firstIndex(where: { $0.id == dayID }) else { return nil }
        let oldDate = calendar.startOfDay(for: days[currentIndex].date)
        let newDate = calendar.startOfDay(for: date)
        guard !calendar.isDate(oldDate, inSameDayAs: newDate) else {
            return ShootingDayRescheduleOutcome(selectedDayID: dayID, displacedDayID: nil)
        }

        var displacedDayID: UUID?
        if let occupiedIndex = days.firstIndex(where: {
            $0.id != dayID && calendar.isDate($0.date, inSameDayAs: newDate)
        }) {
            displacedDayID = days[occupiedIndex].id
            days[occupiedIndex].date = oldDate
            days[occupiedIndex].callSheet.sunriseTime = ""
            days[occupiedIndex].callSheet.sunsetTime = ""
            days[occupiedIndex].callSheet.updatedAt = Date()
        }

        days[currentIndex].date = newDate
        days[currentIndex].callSheet.sunriseTime = ""
        days[currentIndex].callSheet.sunsetTime = ""
        days[currentIndex].callSheet.updatedAt = Date()
        days.sort { $0.date < $1.date }
        return ShootingDayRescheduleOutcome(selectedDayID: dayID, displacedDayID: displacedDayID)
    }
}
