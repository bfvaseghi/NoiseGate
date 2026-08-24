import SwiftUI
import FamilyControls

struct BlockingView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var showNoisePicker = false
    @State private var showMessagesPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.focusOn },
                        set: { _ in model.toggleFocus() }
                    )) {
                        Label("Focus now", systemImage: "moon.fill")
                    }
                    .tint(.indigo)
                } footer: {
                    Text("Blocks all noise apps immediately, until you switch it off.")
                }

                Section {
                    Button {
                        showNoisePicker = true
                    } label: {
                        LabeledContent("Choose apps") {
                            Text(model.noiseSelection.summary)
                        }
                    }
                } header: {
                    Text("Noise apps")
                } footer: {
                    Text("Social media and anything else that adds no value. These get budgeted, nudged, and blocked.")
                }

                Section {
                    Button {
                        showMessagesPicker = true
                    } label: {
                        LabeledContent("Choose apps") {
                            Text(model.messagesSelection.summary)
                        }
                    }
                } header: {
                    Text("Messaging apps")
                } footer: {
                    Text("Messages, WhatsApp, etc. Tracked separately with their own budget — nudged when you're over, but never blocked.")
                }
            }
            .navigationTitle("Blocking")
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
}
