import SwiftUI

/// The NoiseGate budget ring: heavy rounded numerals inside a thick arc with
/// a gradient stroke and an endpoint dot so it reads as a needle, not a
/// donut. Flips to alarm red when the budget is reached, and distinguishes
/// REACHED from genuinely OVER. Used by both apps and all widgets.
struct BudgetGauge: View {
    let title: String
    let minutes: Int
    let budgetMinutes: Int
    let tint: Color
    var isConfigured: Bool = true
    var isFloor: Bool = false
    var size: CGFloat = 108

    private var fraction: Double {
        guard isConfigured, budgetMinutes > 0 else { return 0 }
        return min(1, Double(minutes) / Double(budgetMinutes))
    }

    private var reachedBudget: Bool {
        isConfigured && minutes >= budgetMinutes && budgetMinutes > 0
    }
    private var overBudget: Bool {
        isConfigured && minutes > budgetMinutes && budgetMinutes > 0
    }
    private var ringColor: Color { reachedBudget ? NG.alarm : tint }
    private var stroke: CGFloat { max(8, size * 0.105) }

    private var primaryText: String {
        guard isConfigured else { return "—" }
        guard !isFloor || minutes > 0 else { return "—" }
        return isFloor ? "≥\(minutes.asHoursMinutes)" : minutes.asHoursMinutes
    }

    private var secondaryText: String {
        guard isConfigured else { return "NOT SET" }
        guard !isFloor || minutes > 0 else { return "NO CHECKPOINT" }
        return "OF \(budgetMinutes.asHoursMinutes)"
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.16),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [ringColor.opacity(0.55), ringColor],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if fraction > 0.03 {
                    Circle()
                        .fill(ringColor)
                        .frame(width: stroke * 0.5, height: stroke * 0.5)
                        .offset(y: -size / 2 + stroke / 2)
                        .rotationEffect(.degrees(360 * fraction))
                }

                VStack(spacing: 0) {
                    Text(primaryText)
                        .font(.ngNumber(size * 0.19))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(secondaryText)
                        .font(.ngLabel(max(8, size * 0.085)))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                .padding(stroke + 4)
            }
            .frame(width: size, height: size)

            if overBudget {
                Text("\(title.uppercased()) · OVER")
                    .font(.ngLabel(9.5))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(NG.alarm, in: Capsule())
            } else if reachedBudget {
                Text("\(title.uppercased()) · REACHED")
                    .font(.ngLabel(9.5))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(NG.alarm, in: Capsule())
            } else {
                Text(title.uppercased())
                    .font(.ngLabel(10))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard isConfigured else { return "Not configured" }
        if isFloor && minutes == 0 {
            return "No checkpoint reached yet"
        }
        let qualifier = isFloor ? "At least " : ""
        let state = overBudget ? ", over budget" : reachedBudget ? ", budget reached" : ""
        return "\(qualifier)\(minutes) minutes of a \(budgetMinutes) minute budget\(state)"
    }
}
