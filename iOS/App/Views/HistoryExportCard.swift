import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The rolling history as a CSV, wrapped so the share sheet offers a real
/// file with a sensible name rather than a wall of pasted text.
struct HistoryCSV: Transferable {
    let text: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { csv in
            Data(csv.text.utf8)
        }
        .suggestedFileName { $0.name }
    }
}

/// Export lives behind its own card because the caveat matters as much as the
/// button: iPhone rows are floors, Mac rows are exact, and the file says which
/// per row rather than leaving the reader to assume.
struct HistoryExportCard: View {
    /// Loaded off the view body — `SharedStore` takes a cross-process file
    /// lock, which has no business running during a render.
    @State private var records: [DayRecord] = []

    private var csv: HistoryCSV {
        HistoryCSV(
            text: HistoryExport.csv(records),
            name: HistoryExport.filename()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        NG.inkSoft,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Export history")
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(NG.ink)
                    Text(records.isEmpty
                            ? "No finished days recorded yet."
                            : "\(records.count) finished \(records.count == 1 ? "day" : "days") as CSV")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(NG.inkSoft)
                }
                Spacer()
                if !records.isEmpty {
                    ShareLink(
                        item: csv,
                        preview: SharePreview(HistoryExport.filename())
                    ) {
                        Text("Export")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(NG.distraction)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(NG.distraction.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Each row carries the budgets that applied that day, and whether its minutes are exact or a floor. iPhone records the highest checkpoint crossed, because exact Screen Time never leaves Apple's report extension.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
        .task { records = HistoryStore.lastDays(HistoryStore.maxDays) }
    }
}
