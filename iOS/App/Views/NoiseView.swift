import FamilyControls
import ManagedSettings
import SwiftUI

/// The two explicit ledgers. Anything not listed here is the "noise" that
/// NoiseGate removes from the user's Screen Time picture.
struct NoiseView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showDistractionPicker = false
    @State private var showMessagesPicker = false
    @State private var distractionBeforePicker: FamilyActivitySelection?
    @State private var messagesBeforePicker: FamilyActivitySelection?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "Signal only",
                    title: "APPS.",
                    detail: "Only the apps listed here are counted. Everything else stays untracked."
                )
                .padding(.top, 8)

                TrackListCard(
                    chip: "Distractions",
                    tint: NG.distraction,
                    selection: model.distractionSelection,
                    paused: model.pausedDistractions,
                    excludedApps: model.messagesSelection.applicationTokens,
                    emptyHint: "No distractions selected. Add only the feeds, swiping, and other apps you want this total to mean.",
                    footnote: "Messages selected below are automatically excluded. Whole categories are rejected so useful activity cannot leak into this total.",
                    actionTitle: "Add apps",
                    addApps: {
                        distractionBeforePicker = model.distractionSelection
                        showDistractionPicker = true
                    },
                    setApp: { model.setDistractionApp($0, tracked: $1, for: $2) },
                    setWebDomain: { model.setDistractionWebDomain($0, tracked: $1, for: $2) }
                )

                TrackListCard(
                    chip: "Messages",
                    tint: NG.msg,
                    selection: model.messagesSelection,
                    paused: model.pausedMessages,
                    emptyHint: "Add the Messages app to keep conversation time on its own line.",
                    footnote: "Messages is app-only. FaceTime and WhatsApp stay invisible unless you deliberately choose them here.",
                    actionTitle: "Add Messages",
                    addApps: {
                        messagesBeforePicker = model.messagesSelection
                        showMessagesPicker = true
                    },
                    setApp: { model.setMessagesApp($0, tracked: $1, for: $2) },
                    setWebDomain: { _, _, _ in }
                )

                Spacer(minLength: 96)
            }
            .ngReadingWidth(sizeClass)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(NG.paper.ignoresSafeArea())
        .familyActivityPicker(
            isPresented: $showDistractionPicker,
            selection: $model.distractionSelection
        )
        .familyActivityPicker(
            isPresented: $showMessagesPicker,
            selection: $model.messagesSelection
        )
        .onChange(of: showDistractionPicker) { _, presented in
            guard !presented, let before = distractionBeforePicker else { return }
            distractionBeforePicker = nil
            if !SelectionStore.hasSameTokens(before, model.distractionSelection) {
                model.applyTrackingChanges()
            }
        }
        .onChange(of: showMessagesPicker) { _, presented in
            guard !presented, let before = messagesBeforePicker else { return }
            messagesBeforePicker = nil
            if !SelectionStore.hasSameTokens(before, model.messagesSelection) {
                model.applyTrackingChanges()
            }
        }
    }
}

struct TrackListCard: View {
    let chip: String
    let tint: Color
    let selection: FamilyActivitySelection
    let paused: PausedTokens
    var excludedApps: Set<ApplicationToken> = []
    let emptyHint: String
    let footnote: String
    let actionTitle: String
    let addApps: () -> Void
    let setApp: (ApplicationToken, Bool, PausedTokens.Duration) -> Void
    let setWebDomain: (WebDomainToken, Bool, PausedTokens.Duration) -> Void

    /// A pause that is waiting for a duration choice. Turning a row off asks
    /// how long, so "just for today" cannot quietly become permanent.
    @State private var pending: PendingPause?

    private struct PendingPause {
        let apply: (PausedTokens.Duration) -> Void
    }

    private var pausedCount: Int {
        paused.applications.count + paused.webDomains.count
    }

    /// "Paused until tomorrow" is worth saying; an indefinite pause is
    /// already obvious from the switch.
    private func pauseNote(_ end: Date?) -> String? {
        guard let end else { return nil }
        return "Paused until \(end.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

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
                    Label(actionTitle, systemImage: "plus")
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
                    ForEach(Array(selection.applicationTokens), id: \.self) { token in
                        let isExcluded = excludedApps.contains(token)
                        let isPaused = paused.applications.contains(token)
                        toggleRow(
                            isOn: !isPaused && !isExcluded,
                            enabled: !isExcluded,
                            note: isExcluded
                                ? "Reserved for Messages"
                                : (isPaused ? pauseNote(paused.expiry(forApplication: token)) : nil),
                            set: { tracked in
                                if tracked { setApp(token, true, .indefinitely) }
                                else {
                                    pending = PendingPause { setApp(token, false, $0) }
                                }
                            }
                        ) {
                            Label(token)
                        }
                    }
                    ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                        toggleRow(
                            isOn: !paused.webDomains.contains(token),
                            enabled: true,
                            note: nil,
                            set: { tracked in
                                if tracked { setWebDomain(token, true, .indefinitely) }
                                else {
                                    pending = PendingPause { setWebDomain(token, false, $0) }
                                }
                            }
                        ) {
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
        .confirmationDialog(
            "Stop counting this for how long?",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(PausedTokens.Duration.allCases) { duration in
                Button(duration.title) {
                    pending?.apply(duration)
                    pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("It stays in your list either way. Paused time is not counted and not blocked.")
        }
    }

    private func toggleRow<L: View>(
        isOn: Bool,
        enabled: Bool,
        note: String?,
        set: @escaping (Bool) -> Void,
        @ViewBuilder label: () -> L
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { isOn }, set: set)) {
                label()
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? NG.ink : NG.inkSoft)
                    .opacity(isOn ? 1 : 0.55)
            }
            .tint(tint)
            .disabled(!enabled)

            if let note {
                Text(note)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
    }
}
