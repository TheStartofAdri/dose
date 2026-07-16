import XCTest
@testable import Dose

/// v10: editing a medicine's dose times must NOT inject phantom misses on past days (adherence) or
/// break the streak via those phantom misses. `scheduleChangedAt` gates reconstructed misses before the
/// edit — pre-edit days are scored from the real take/skip logs only, since the old schedule is unknown.
/// Fail-before: without the gate, the NEW-schedule slot reconstructed on a past day is scored as a miss.
final class ScheduleChangeTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    /// A real take at the OLD 08:00 slot on a pre-edit day still counts, and the NEW 09:00 slot
    /// reconstructed on that day is NOT a phantom miss.
    func testScheduleEditDoesNotInjectPhantomMissInAdherence() {
        let id = UUID()
        let now = at(2026, 7, 13, 12)
        let med = MedicineSnapshot(id: id, name: "Aspirin", dosage: nil,
                                   rules: [DoseSlotRule(hour: 9, minute: 0)],           // edited FROM 08:00
                                   createdAt: at(2026, 7, 1), scheduleChangedAt: at(2026, 7, 13, 9))
        let takenOldSlot = DoseLogSnapshot(medicineID: id, scheduledFor: at(2026, 7, 5, 8),
                                           action: .taken, actionedAt: at(2026, 7, 5, 8))
        let days = AdherenceCalculator.days(medicines: [med], logs: [takenOldSlot],
                                            from: at(2026, 7, 5), to: at(2026, 7, 5), now: now, calendar: cal)
        let jul5 = days.first { cal.isDate($0.date, inSameDayAs: at(2026, 7, 5)) }!
        XCTAssertEqual(jul5.taken, 1, "the real take at the old slot still counts (orphan)")
        XCTAssertEqual(jul5.missed, 0, "no phantom miss for the reconstructed NEW 09:00 slot on a pre-edit day")
    }

    /// With a second (never-edited) medicine taken every day, the edited medicine's phantom misses must
    /// not break the streak. The gate is observable here: without it, the edited med's reconstructed
    /// pre-edit misses break the chain; with it, the streak runs through days the other med covers.
    func testScheduleEditPhantomMissesDoNotBreakStreak() {
        let a = UUID(), b = UUID()
        let now = at(2026, 7, 13, 12)
        let medA = MedicineSnapshot(id: a, name: "A", dosage: nil, rules: [DoseSlotRule(hour: 9, minute: 0)],
                                    createdAt: at(2026, 7, 1), scheduleChangedAt: at(2026, 7, 13, 6))  // edited today
        let medB = MedicineSnapshot(id: b, name: "B", dosage: nil, rules: [DoseSlotRule(hour: 10, minute: 0)],
                                    createdAt: at(2026, 7, 1))                                          // never edited
        var logs: [DoseLogSnapshot] = []
        for d in [10, 11, 12, 13] {
            // A was taken at the OLD 08:00 slot on the pre-edit days, at the new 09:00 today.
            logs.append(DoseLogSnapshot(medicineID: a, scheduledFor: at(2026, 7, d, d == 13 ? 9 : 8),
                                        action: .taken, actionedAt: at(2026, 7, d, 9)))
            logs.append(DoseLogSnapshot(medicineID: b, scheduledFor: at(2026, 7, d, 10),
                                        action: .taken, actionedAt: at(2026, 7, d, 10)))
        }
        let streak = StreakCalculator.currentStreak(medicines: [medA, medB], logs: logs, now: now, calendar: cal)
        XCTAssertEqual(streak, 4, "A's schedule-edit phantom misses must not break a fully-adherent 4-day streak")
    }

    /// Guard: an UN-edited medicine (scheduleChangedAt == nil) is scored exactly as before — a real
    /// past miss still counts. (Proves the gate only changes edited medicines.)
    func testUneditedMedicineStillCountsRealMiss() {
        let id = UUID()
        let now = at(2026, 7, 13, 12)
        let med = MedicineSnapshot(id: id, name: "Aspirin", dosage: nil, rules: [DoseSlotRule(hour: 9, minute: 0)],
                                   createdAt: at(2026, 7, 1), scheduleChangedAt: nil)
        let days = AdherenceCalculator.days(medicines: [med], logs: [],
                                            from: at(2026, 7, 5), to: at(2026, 7, 5), now: now, calendar: cal)
        XCTAssertEqual(days.first?.missed, 1, "an un-edited med's genuinely-missed past slot still counts")
    }

    /// `missedEvents` (History "Missed" list / Week "missed this week") must apply the SAME gate as the
    /// count — no phantom pre-edit missed rows. Fail-before: the gate was only on the count, not the list.
    func testMissedEventsExcludesPreEditPhantomMisses() {
        let id = UUID()
        let now = at(2026, 7, 13, 12)
        let med = MedicineSnapshot(id: id, name: "Aspirin", dosage: nil, rules: [DoseSlotRule(hour: 9, minute: 0)],
                                   createdAt: at(2026, 7, 1), scheduleChangedAt: at(2026, 7, 13, 9))
        let events = AdherenceCalculator.missedEvents(medicines: [med], logs: [],
                                                      from: at(2026, 7, 5), to: at(2026, 7, 5), now: now, calendar: cal)
        XCTAssertTrue(events.isEmpty, "no phantom missed EVENT for a pre-edit reconstructed slot")
    }

    /// The locked parity invariant (missedEvents.count == missedCount(days)) must hold for an EDITED med.
    /// Fail-before: the list counted pre-edit slots the count suppressed → a "0 missed" tile beside N rows.
    func testMissedEventsParityHoldsForEditedMedicine() {
        let id = UUID()
        let now = at(2026, 7, 13, 12)
        let med = MedicineSnapshot(id: id, name: "Aspirin", dosage: nil, rules: [DoseSlotRule(hour: 9, minute: 0)],
                                   createdAt: at(2026, 7, 1), scheduleChangedAt: at(2026, 7, 10, 9))
        let from = at(2026, 7, 5), to = at(2026, 7, 12)
        let count = AdherenceCalculator.missedCount(
            AdherenceCalculator.days(medicines: [med], logs: [], from: from, to: to, now: now, calendar: cal))
        let events = AdherenceCalculator.missedEvents(medicines: [med], logs: [], from: from, to: to,
                                                      now: now, calendar: cal).count
        XCTAssertEqual(events, count, "missedEvents count must equal missedCount even after a schedule edit")
        XCTAssertEqual(count, 3, "only the 3 post-edit days (Jul 10–12) are missed")
    }
}
