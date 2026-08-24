import SwiftUI
import FamilyControls
import ManagedSettings

/// Where you decide what counts. Add apps with Apple's picker, then toggle
/// each one on (tracked) or off (paused) without losing the list. Apps never
/// flagged here are completely invisible to NoiseGate — that's the whole
/// premise: NYT and FaceTime aren't noise; Hinge and the feeds might be.
struct NoiseView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var showNoisePicker = false
    @State private var showMessagesPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "What counts",
                    title: "NOISE.",
                    detail: "Only what's on these lists is ever tracked. Toggle anything off to pause it."
                )
                .padding(.top, 8)

                TrackListCard(
                    chip: "Noise", tint: NG.noise,
                    selection: model.noiseSelection,
                    muted: model.mutedNoise,
                    emptyHint: "Nothing flagged yet. Add the apps that add nothing — the feeds, the swiping, whatever your time disappears into.",
                    footnote: "The useful stuff — news, maps, notes, work — doesn't belong here, and NoiseGate will never see it.",
                    addApps: { showNoisePicker = true },
                    setApp: model.setNoiseApp,
                    setCategory: model.setNoiseCategory
                )

                TrackListCard(
                    chip: "Messages", tint: NG.msg,
                    selection: model.messagesSelection,
                    muted: model.mutedMessages,
                    emptyHint: "Add just the Messages app here to keep an eye on thread time.",
                    footnote: "Tracked separately, never judged harshly. Leave FaceTime and WhatsApp out — talking to real people isn't noise.",
                    addApps: { showMessagesPicker = true },
                    setApp: model.setMessagesApp,
                    setCategory: model.setMessagesCategory
                )

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

/// A category card with an "Add apps" button and a toggle row per selected
/// app/category. `Label(token)` renders the real app name and icon via the
/// system, so the list is readable even though the tokens stay opaque to us.
struct TrackListCard: View {
    let chip: String
    let tint: Color
    let selection: FamilyActivitySelection
    let muted: MutedTokens
    let emptyHint: String
    let footnote: String
    let addApps: () -> Void
    let setApp: (ApplicationToken, Bool) -> Void
    let setCategory: (ActivityCategoryToken, Bool) -> Void

    private var pausedCount: Int { muted.applications.count + muted.categories.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NGChip(text: chip, tint: tint)
                if pausedCount > 0 {
                    Text("\(pausedCount) paused")
                        .font(.ngLabel(10))
                        .tracking(1)
                        .foregroundStyle(NG.inkSoft)
                }
                Spacer()
                Button(action: addApps) {
                    Label("Add apps", systemImage: "plus")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if selection.isEmpty {
                Text(emptyHint)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(selection.categoryTokens), id: \.self) { token in
                        toggleRow(isOn: !muted.categories.contains(token)) {
                            setCategory(token, $0)
                        } label: {
                            Label(token)
                        }
                    }
                    ForEach(Array(selection.applicationTokens), id: \.self) { token in
                        toggleRow(isOn: !muted.applications.contains(token)) {
                            setApp(token, $0)
                        } label: {
                            Label(token)
                        }
                    }
                }
            }

            Text(footnote)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
    }

    private func toggleRow<L: View>(
        isOn: Bool,
        set: @escaping (Bool) -> Void,
        @ViewBuilder label: () -> L
    ) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            label()
                .labelStyle(.titleAndIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? NG.ink : NG.inkSoft)
                .opacity(isOn ? 1 : 0.55)
        }
        .tint(tint)
        .padding(.vertical, 6)
    }
}
