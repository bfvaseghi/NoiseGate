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

/// Share a named CSV and identify checkpoint minimums before export.
struct HistoryExportCard: View {
    /// Loaded off the view body — `SharedStore` takes a cross-process file
    /// lock, which has no business running during a render.
    @State private var records: [DayRecord] = []

    private var csv: HistoryCSV {
        HistoryCSV(
            text: HistoryExport.csv(records, forceLowerBound: true),
            name: HistoryExport.filename()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export history").font(.subheadline.weight(.medium))
                    Text(records.isEmpty ? "No finished days yet" : "\(records.count) days · CSV")
                        .font(.caption).foregroundStyle(NG.inkSoft)
                }
                Spacer()
                if !records.isEmpty {
                    ShareLink(item: csv, preview: SharePreview(HistoryExport.filename())) {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Export history as CSV")
                    .tint(NG.distraction)
                }
            }
            Text("iPhone exports contain checkpoint minimums.")
                .font(.caption).foregroundStyle(NG.inkSoft)
        }
        .ngCard(padding: 17)
        .task {
            records = HistoryStore.lastDays(HistoryStore.maxDays)
                .filter { $0.dayKey < DayKey.today() }
        }
    }
}
