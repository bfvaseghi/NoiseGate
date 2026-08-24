import SwiftUI

/// Circular budget ring used by the iOS and macOS widgets and the apps.
struct BudgetGauge: View {
    let title: String
    let minutes: Int
    let budgetMinutes: Int
    let tint: Color
    var isFloor: Bool = false

    private var fraction: Double {
        guard budgetMinutes > 0 else { return 0 }
        return min(1, Double(minutes) / Double(budgetMinutes))
    }

    private var overBudget: Bool { minutes >= budgetMinutes && budgetMinutes > 0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        overBudget ? Color.red : tint,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(isFloor && minutes > 0 ? "≥\(minutes.asHoursMinutes)" : minutes.asHoursMinutes)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("of \(budgetMinutes.asHoursMinutes)")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
