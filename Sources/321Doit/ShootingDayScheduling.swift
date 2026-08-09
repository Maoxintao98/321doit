import Foundation

struct ShootingDayRescheduleOutcome: Equatable {
    let selectedDayID: UUID
    let displacedDayID: UUID?
}

enum ShootingDayScheduling {
    /// Upper bound for the day-by-day scan. A corrupt or pathological set of
    /// occupied dates should degrade to a bounded scan instead of spinning.
    static let maxScanDays = 3_660

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
        var scanned = 0
        while occupied.contains(candidate), scanned < maxScanDays {
            guard let followingDay = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return candidate
            }
            candidate = followingDay
            scanned += 1
        }
        return candidate
    }

    /// Repairs legacy projects that could still hold more than one shooting day
    /// on the same calendar date. Later duplicates are moved to the next free
    /// date while preserving every record's ID and payload. Returns how many
    /// records were moved.
    static func repairDuplicateDates(
        days: inout [ShootingDay],
        calendar: Calendar = .current
    ) -> Int {
        var occupied = Set<Date>()
        var moved = 0
        for index in days.indices {
            let dayDate = calendar.startOfDay(for: days[index].date)
            if occupied.contains(dayDate) {
                let next = nextAvailableDate(startingAt: days[index].date, days: days, calendar: calendar)
                days[index].date = next
                days[index].callSheet.sunriseTime = ""
                days[index].callSheet.sunsetTime = ""
                days[index].callSheet.updatedAt = Date()
                moved += 1
            }
            occupied.insert(calendar.startOfDay(for: days[index].date))
        }
        days.sort { calendar.startOfDay(for: $0.date) < calendar.startOfDay(for: $1.date) }
        return moved
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
