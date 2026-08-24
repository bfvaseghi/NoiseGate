import SwiftUI
import FamilyControls

struct BlockingView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var showNoisePicker = false
    @State private var showMessagesPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "The wall",
                    title: "BLOCKING.",
                    detail: "Three ways up: right now, at 100%, or on a schedule."
                )
                .padding(.top, 8)

                FocusSlab(isOn: model.focusOn) { model.toggleFocus() }

                SelectionCard(
                    chip: "Noise", tint: NG.noise,
                    summary: model.noiseSelection.summary,
                    footnote: "Social media and anything else that adds no value. These get budgeted, nudged, and blocked."
                ) { showNoisePicker = true }

                SelectionCard(
                    chip: "Messages", tint: NG.msg,
                    summary: model.messagesSelection.summary,
                    footnote: "Messages, WhatsApp, etc. Tracked separately with their own budget — nudged when you're over, never blocked."
                ) { showMessagesPicker = true }

                Spacer(minLength: 96)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(NG.paper.ignoresSafeArea())
        .familyActivityPicker(isPresented: $showNoisePicker, selection: $model.noiseSelection)
        .familyActivityPicker(isPresented: $showMessagesPicker, selection: $model.messagesSelection)
        .onChange(of: showNoisePicker) { _, presented in
            if !presented { model.applyChanges() }
        }
        .onChange(of: showMessagesPicker) { _, presented in
            if !presented { model.applyChanges() }
        }
    }
}

/// The big one: a full-width slab that flips between "FOCUS NOW." on ink and
/// "FOCUSED." on indigo. This is the app's main physical control — it should
/// feel like slamming a switch, not flicking a toggle.
struct FocusSlab: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { action() }
        }) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isOn ? "FOCUSED." : "FOCUS NOW.")
                        .font(.ngDisplay(30))
                        .contentTransition(.opacity)
                    Text(isOn
                            ? "Noise is walled off. Tap to end it."
                            : "Wall off every noise app, immediately.")
                        .font(.system(size: 13.5, weight: .semibold))
                        .opacity(0.85)
                }
                Spacer()
                Image(systemName: isOn ? "moon.fill" : "moon")
                    .font(.system(size: 26, weight: .black))
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isOn {
                        NG.focusGradient
                        HazardStripes(opacity: 0.06)
                    } else {
                        NG.ink
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
            .shadow(color: (isOn ? NG.focus : NG.ink).opacity(0.3), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: isOn)
    }
}

struct SelectionCard: View {
    let chip: String
    let tint: Color
    let summary: String
    let footnote: String
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NGChip(text: chip, tint: tint)
                Spacer()
                Button(action: choose) {
                    Text("Choose apps")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Text(summary)
                .font(.ngNumber(21))
                .foregroundStyle(NG.ink)
            Text(footnote)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
    }
}
