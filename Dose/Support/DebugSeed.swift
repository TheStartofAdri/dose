#if DEBUG
import Foundation
import SwiftData

/// DEBUG-only sample data (excluded from Release) so the Today card and History dashboard can be
/// exercised/screenshotted against a realistic MIX — taken, past-due-untaken (missed), upcoming,
/// and explicitly skipped — not the all-taken data that hid the past-due bug. Triggered by the
/// `-seedHistoryDemo` launch argument.
enum DebugSeed {
    @MainActor
    static func seedHistoryDemo(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        // MARK: Med 1 — Vitamin D: 20 days, daily 08:00. Mostly taken, a couple of past-due misses,
        // and today left untaken (a past-due "Take" card once 08:00 passes; upcoming before then).
        let vitD = Medicine(name: "Vitamin D", dosage: "1000 IU", form: "tablet",
                            trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -20, to: today)!,
                            iconName: "drop.fill", colorHex: "#FF9F0A", instructions: "Take with breakfast")
        let vitDTime = DoseTime(hour: 8, minute: 0)
        vitD.doseTimes = [vitDTime]
        context.insert(vitD); context.insert(vitDTime)
        for ago in 1...20 where ago != 3 && ago != 10 {        // ago 3 & 10 missed; today untaken
            log(context, vitD, daysAgo: ago, hour: 8, today: today, calendar: calendar, action: .taken)
        }

        // MARK: Med 2 — a LONG name to prove the card keeps the name readable beside a compact Take.
        // Two daily times: 08:00 taken (incl. today → Undo) and 21:00 (today unsettled → compact Take).
        let mag = Medicine(name: "Sustained-Release Magnesium", dosage: "400 mg", form: "capsule",
                           trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -6, to: today)!,
                           iconName: "capsule.fill", colorHex: "#5E5CE6")
        let magMorning = DoseTime(hour: 8, minute: 0)
        let magEvening = DoseTime(hour: 21, minute: 0)
        mag.doseTimes = [magMorning, magEvening]
        context.insert(mag); context.insert(magMorning); context.insert(magEvening)
        for ago in 0...6 {                                     // mornings taken every day incl. today
            log(context, mag, daysAgo: ago, hour: 8, today: today, calendar: calendar, action: .taken)
        }
        for ago in 2...6 {                                     // evenings taken except 1 day ago (a miss)
            log(context, mag, daysAgo: ago, hour: 21, today: today, calendar: calendar, action: .taken)
        }
        // 1 day ago 21:00 → missed; today 21:00 → upcoming/unsettled (a compact Take on a long name).

        // MARK: Med 3 — Amoxicillin: 4 days, daily 09:00. Taken, then explicitly SKIPPED today
        // (neutral in adherence; shows the grey Undo card and a grey bar in the chart).
        // A finite course (ends in a few days) to exercise treatment-duration + instructions.
        let amox = Medicine(name: "Amoxicillin", dosage: "500 mg", form: "capsule",
                            trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -4, to: today)!,
                            iconName: "cross.vial.fill", colorHex: "#FF375F",
                            endDate: calendar.date(byAdding: .day, value: 3, to: today),
                            instructions: "Finish the whole course")
        let amoxTime = DoseTime(hour: 9, minute: 0)
        amox.doseTimes = [amoxTime]
        context.insert(amox); context.insert(amoxTime)
        for ago in 1...3 {
            log(context, amox, daysAgo: ago, hour: 9, today: today, calendar: calendar, action: .taken)
        }
        log(context, amox, daysAgo: 0, hour: 9, today: today, calendar: calendar, action: .skipped)

        // MARK: Med 4 — created THIS AFTERNOON (14:00) with a dose already taken this MORNING (08:00).
        // Exercises the pre-createdAt-take fix: the old calculator zeroed this (08:00 < 14:00 createdAt),
        // so History under-counted it; now it correctly shows 100% for today.
        let created14 = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let lisin = Medicine(name: "Lisinopril", dosage: "10 mg", form: "tablet",
                             trustState: .confirmed, createdAt: created14,
                             iconName: "heart.fill", colorHex: "#FF375F")
        let lisinTime = DoseTime(hour: 8, minute: 0)
        lisin.doseTimes = [lisinTime]
        context.insert(lisin); context.insert(lisinTime)
        log(context, lisin, daysAgo: 0, hour: 8, today: today, calendar: calendar, action: .taken)

        // A sample note for the Notes tab (analysis is always explicit / user-initiated).
        context.insert(Note(text: "Doctor suggested ibuprofen 200 mg twice a day for the next week if the pain continues.",
                            createdAt: calendar.date(byAdding: .day, value: -1, to: today) ?? today))

        try? context.save()
    }

    /// Seeds the three instruction cases the Today card must handle, so the glance surface stays compact
    /// whatever the instruction length:
    ///   • Aspirin — a truncatable name + "2 pills" + a SHORT instruction ("With food") that fits one
    ///     line and is shown in full (also the name-readable / controls-aligned regression shape).
    ///   • Ibuprofen — a LONG paragraph instruction that wouldn't fit one line, so the card collapses it
    ///     to a compact "Instructions" indicator (the full text lives on the detail screen) and does NOT
    ///     grow the card.
    ///   • Metformin — NO instruction (no indicator, no empty gap).
    /// All three are scheduled before `now` so they render overdue regardless of run time (clamped to
    /// today near midnight). Triggered by `-seedCardLayoutDemo`.
    @MainActor
    static func seedCardLayoutDemo(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        // A time `minutesBack` before `now`, pinned inside today so the slot is in the past (overdue)
        // for any daytime run; near midnight it clamps to 00:30 today rather than wrap to yesterday's
        // hour (which would read as a future slot today).
        func overdueTime(minutesBack: Int) -> DoseTime {
            let target = calendar.date(byAdding: .minute, value: -minutesBack, to: now) ?? now
            if target < today { return DoseTime(hour: 0, minute: 30) }
            return DoseTime(hour: calendar.component(.hour, from: target),
                            minute: calendar.component(.minute, from: target))
        }

        // Aspirin — truncatable name, a dosage, and a SHORT instruction that fits one line → shown in full.
        let aspirin = Medicine(name: "Aspirin", dosage: "2 pills", form: "tablet",
                               trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -3, to: today)!,
                               iconName: "pills.fill", colorHex: "#FF375F",
                               instructions: "Take before breakfast")
        let aspirinTime = overdueTime(minutesBack: 180)
        aspirin.doseTimes = [aspirinTime]
        context.insert(aspirin); context.insert(aspirinTime)

        // Ibuprofen — a LONG paragraph instruction that can't fit one line → collapses to the compact
        // "Instructions" indicator; the card must stay the same height as the short-instruction card.
        let ibuprofen = Medicine(name: "Ibuprofen", dosage: "1 tablet", form: "tablet",
                                 trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -3, to: today)!,
                                 iconName: "cross.vial.fill", colorHex: "#BF5AF2",
                                 instructions: "Take one tablet by mouth every six hours as needed for pain. Do not exceed four tablets in twenty-four hours. Take with food or milk to avoid stomach upset.")
        let ibuprofenTime = overdueTime(minutesBack: 150)
        ibuprofen.doseTimes = [ibuprofenTime]
        context.insert(ibuprofen); context.insert(ibuprofenTime)

        // Metformin — NO instruction: no indicator, no empty gap.
        let metformin = Medicine(name: "Metformin", dosage: "500 mg", form: "tablet",
                                 trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -3, to: today)!,
                                 iconName: "capsule.fill", colorHex: "#0A84FF")
        let metforminTime = overdueTime(minutesBack: 120)
        metformin.doseTimes = [metforminTime]
        context.insert(metformin); context.insert(metforminTime)

        try? context.save()
    }

    /// Seeds one card per time-color state so a UI test can assert the top-right time renders RED for an
    /// overdue dose (`.missed`/`.due` — the "you're late" cue) and neutral GRAY otherwise (`.upcoming`,
    /// `.taken`). Times are relative to `now` and clamped into today, so the overdue/due cards are always
    /// past (red) and the taken card always carries its log (gray); the upcoming card is `now`+90min
    /// clamped to 23:59 (a future-today slot — only the final minute before midnight could make it due).
    /// Triggered by `-seedTimeColorDemo`.
    @MainActor
    static func seedTimeColorDemo(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let dayStart = today.addingTimeInterval(60)                       // 00:01
        let dayEnd = today.addingTimeInterval(23 * 3600 + 59 * 60)        // 23:59

        // A DoseTime + its today slot for `target`, clamped inside today so the slot is always present.
        func slot(_ target: Date) -> (DoseTime, Date) {
            let clamped = min(max(target, dayStart), dayEnd)
            let h = calendar.component(.hour, from: clamped)
            let m = calendar.component(.minute, from: clamped)
            let scheduled = calendar.date(bySettingHour: h, minute: m, second: 0, of: today) ?? clamped
            return (DoseTime(hour: h, minute: m), scheduled)
        }

        func add(_ name: String, colorHex: String, target: Date, taken: Bool) {
            let (dt, scheduled) = slot(target)
            let med = Medicine(name: name, dosage: "1 pill", form: "tablet",
                               trustState: .confirmed, createdAt: calendar.date(byAdding: .day, value: -1, to: today)!,
                               iconName: "pills.fill", colorHex: colorHex)
            med.doseTimes = [dt]
            context.insert(med); context.insert(dt)
            if taken {
                context.insert(DoseLog(medicineID: med.id, medicineName: med.name, dosage: med.dosage,
                                       scheduledFor: scheduled, action: .taken,
                                       actionedAt: scheduled.addingTimeInterval(60)))
            }
        }

        add("Overdue Med",  colorHex: "#8E8E93", target: now.addingTimeInterval(-180 * 60), taken: false)  // → .missed → RED
        add("Due Med",      colorHex: "#8E8E93", target: now.addingTimeInterval(-20 * 60),  taken: false)  // → .due → RED
        add("Upcoming Med", colorHex: "#8E8E93", target: now.addingTimeInterval(90 * 60),   taken: false)  // → .upcoming → GRAY
        add("Taken Med",    colorHex: "#8E8E93", target: now.addingTimeInterval(-180 * 60), taken: true)   // → .taken → GRAY

        try? context.save()
    }

    /// Seeds the "This week" screenshot: a mix that deterministically leaves a gap day regardless of
    /// the run date. Iron is daily but ends in 2 days (covers days 0–2); B12 is every-3-days from today
    /// (days 0, 3, 6) — so days 4 and 5 have nothing scheduled ("Nothing scheduled"). Triggered by
    /// `-seedWeekDemo`.
    @MainActor
    static func seedWeekDemo(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)

        let iron = Medicine(name: "Iron", dosage: "65 mg", form: "tablet",
                            trustState: .confirmed, createdAt: today,
                            iconName: "drop.fill", colorHex: "#FF9F0A",
                            endDate: calendar.date(byAdding: .day, value: 2, to: today))
        let ironTime = DoseTime(hour: 8, minute: 0)
        iron.doseTimes = [ironTime]
        context.insert(iron); context.insert(ironTime)

        let b12 = Medicine(name: "Vitamin B12", dosage: "1000 mcg", form: "tablet",
                           trustState: .confirmed, createdAt: today,
                           iconName: "pills.fill", colorHex: "#5E5CE6")
        let b12Time = DoseTime(hour: 9, minute: 0, intervalDays: 3, anchorDate: today)
        b12.doseTimes = [b12Time]
        context.insert(b12); context.insert(b12Time)

        try? context.save()
    }

    @MainActor
    private static func log(_ context: ModelContext, _ med: Medicine, daysAgo: Int, hour: Int,
                            today: Date, calendar: Calendar, action: DoseAction) {
        guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
              let slot = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return }
        context.insert(DoseLog(medicineID: med.id, medicineName: med.name, dosage: med.dosage,
                               scheduledFor: slot, action: action, actionedAt: slot.addingTimeInterval(120)))
    }
}
#endif
