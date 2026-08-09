import AmparoShared
import SwiftUI

/// Hidden behind the 5-second hold + PIN. Caregiver-facing: English,
/// technical detail allowed. "Atualizar" from the handoff = Sync now.
struct CaregiverSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String?
    @State private var lastSynced: Date?
    @State private var consent: ConsentRecord?
    @State private var syncResult: String?
    @State private var confirmReset = false
    @State private var showHelpPreview = false

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Server", value: serverURL ?? "—")
                    LabeledContent("Last sync", value: lastSynced?.formatted() ?? "never")
                    if let consent {
                        LabeledContent(
                            "Consent recorded",
                            value: "\(consent.caregiverName), \(consent.attestedAt.formatted(date: .abbreviated, time: .omitted))"
                        )
                    }
                }
                Section {
                    Button("Sync now") {
                        Task { await syncNow() }
                    }
                    if let syncResult {
                        Text(syncResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Preview member help screen") {
                        showHelpPreview = true
                    }
                } footer: {
                    Text("Shows exactly what the member sees when something goes wrong — check your name and that the call button dials the right number. Exit by holding the headline for 5 seconds.")
                }
                Section {
                    Button("Reset enrollment", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("Erases keys, tokens, and cached items from this device. Your contact card stays so the help screen keeps working.")
                }
            }
            .navigationTitle("Caregiver settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showHelpPreview) {
                CallCaregiverView(onExitPreview: { showHelpPreview = false })
            }
            .confirmationDialog(
                "Erase this device's enrollment? The member cannot use the app until you re-enroll.",
                isPresented: $confirmReset,
                titleVisibility: .visible
            ) {
                Button("Erase enrollment", role: .destructive) {
                    dismiss()
                    Task { await model.resetEnrollment() }
                }
            }
            .task { await loadStatus() }
        }
    }

    private func loadStatus() async {
        serverURL = await model.vault.serverURLString()
        lastSynced = (try? await model.vault.lastSnapshot())?.syncedAt
        consent = await model.vault.consentRecord()
    }

    private func syncNow() async {
        do {
            let snapshot = try await model.vault.syncNow()
            lastSynced = snapshot.syncedAt
            syncResult = "OK — \(snapshot.ciphers.count) items."
        } catch {
            syncResult = "Sync failed: \(error)"
        }
    }
}
