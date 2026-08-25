import Foundation

/// Turns the rolling day history into a CSV the owner can keep.
///
/// The file has to be honest about something the app cannot hide: on iPhone a
/// day's minutes are threshold *floors* — the highest checkpoint crossed —
/// because Apple keeps exact Screen Time inside the report extension. On Mac
/// they are exact, because the Mac tracks foreground time itself. Mixing the
/// two without saying so would produce a spreadsheet that quietly lies, so
/// every row carries its own `accuracy`.
enum HistoryExport {
    static let header = "date,distraction_minutes,distraction_budget,"
        + "messages_minutes,messages_budget,accuracy"

    /// RFC 4180: quote a field and double any quote inside it. None of the
    /// values here can contain a comma today, but a format that only works
    /// for today's values is a trap for the next one.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func row(_ record: DayRecord) -> String {
        [
            field(record.dayKey),
            String(record.distractionMinutes),
            String(record.distractionBudgetMinutes),
            String(record.messagesMinutes),
            String(record.messagesBudgetMinutes),
            record.isFloor ? "at_least" : "exact",
        ].joined(separator: ",")
    }

    /// Oldest day first, so the file reads in the direction time runs.
    static func csv(_ records: [DayRecord]) -> String {
        ([header] + HistoryStore.canonicalized(records).map(row))
            .joined(separator: "\n") + "\n"
    }

    /// A stable, sortable filename. Two exports on the same day overwrite
    /// rather than accumulating near-identical files.
    static func filename(today: String = DayKey.today()) -> String {
        "NoiseGate-\(today).csv"
    }
}
