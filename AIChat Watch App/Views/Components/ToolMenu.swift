//
//  ToolMenu.swift
//  AIChat Watch App
//
//  Sheet-presented menu for per-conversation runtime overrides:
//    • model picker (filtered by license mask if present)
//    • thinking intensity picker
//    • Google Search tool toggle
//    • Code Execution tool toggle
//    • shortcut to ConversationSettingsView for full editing
//
//  Reads/writes the conversation's `ConversationAIConfiguration`
//  through the supplied closure. The detail view's VM persists.
//

import SwiftUI

struct ToolMenu: View {
    let configuration: ConversationAIConfiguration
    let allowedModelIDs: Set<String>?
    let onUpdate: (ConversationAIConfiguration) -> Void
    let onOpenFullSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    Picker("Model", selection: Binding(
                        get: { configuration.model },
                        set: { newModel in
                            var updated = configuration
                            updated.model = newModel
                            updated.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
                                updated.thinkingIntensity,
                                for: newModel
                            )
                            onUpdate(updated)
                        }
                    )) {
                        ForEach(modelOptions, id: \.id) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                Section("Thinking") {
                    Picker("Thinking", selection: Binding(
                        get: { configuration.thinkingIntensity },
                        set: { newValue in
                            var updated = configuration
                            updated.thinkingIntensity = AIModelCatalog.normalizedThinkingIntensity(
                                newValue,
                                for: updated.model
                            )
                            onUpdate(updated)
                        }
                    )) {
                        ForEach(AIModelCatalog.availableThinkingIntensities(for: configuration.model)) { intensity in
                            Text(intensity.displayName).tag(intensity)
                        }
                    }
                }

                Section("Tools") {
                    Toggle("Google Search", isOn: Binding(
                        get: { configuration.usesGoogleSearch },
                        set: { newValue in
                            var updated = configuration
                            updated.usesGoogleSearch = newValue
                            onUpdate(updated)
                        }
                    ))
                    Toggle("Code Execution", isOn: Binding(
                        get: { configuration.usesCodeExecution },
                        set: { newValue in
                            var updated = configuration
                            updated.usesCodeExecution = newValue
                            onUpdate(updated)
                        }
                    ))
                }

                Section {
                    Button {
                        onOpenFullSettings()
                    } label: {
                        Label("More Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private var modelOptions: [AIModelOption] {
        AIModelCatalog.quickOptions(
            defaultModel: configuration.model,
            allowedModelIDs: allowedModelIDs
        )
    }
}
