import DeviceActivity
import Foundation

extension DeviceActivityName {
    static let daily = Self("daily")
}

/// Event names carry every value needed to interpret a delayed callback. The
/// monitor never has to infer a past threshold from today's mutable budget.
enum ThresholdEvent {
    static let schemaVersion = 3

    static func name(
        kind: String,
        percent: Int,
        generation: Int,
        budgetMinutes: Int
    ) -> DeviceActivityEvent.Name {
        let threshold = thresholdMinutes(budget: budgetMinutes, percent: percent)
        return DeviceActivityEvent.Name(
            "v\(schemaVersion).g\(generation).\(kind).b\(budgetMinutes).m\(threshold).p\(percent)"
        )
    }

    static func parse(
        _ name: DeviceActivityEvent.Name
    ) -> (
        generation: Int,
        kind: String,
        percent: Int,
        budgetMinutes: Int,
        thresholdMinutes: Int
    )? {
        let parts = name.rawValue.split(separator: ".")
        guard parts.count == 6,
              parts[0] == "v\(schemaVersion)",
              parts[1].first == "g",
              let generation = Int(parts[1].dropFirst()),
              generation > 0,
              parts[3].first == "b",
              let budgetMinutes = Int(parts[3].dropFirst()),
              (1...480).contains(budgetMinutes),
              parts[4].first == "m",
              let exactThreshold = Int(parts[4].dropFirst()),
              parts[5].first == "p",
              let percent = Int(parts[5].dropFirst()),
              (BudgetConfig.progressPercents + BudgetConfig.overtimePercents)
                .contains(percent) else { return nil }
        let kind = String(parts[2])
        guard kind == "distractions" || kind == "msg",
              exactThreshold == thresholdMinutes(
                budget: budgetMinutes,
                percent: percent
              ) else { return nil }
        return (generation, kind, percent, budgetMinutes, exactThreshold)
    }

    static func thresholdMinutes(budget: Int, percent: Int) -> Int {
        max(1, Int((Double(budget) * Double(percent) / 100).rounded(.up)))
    }
}
