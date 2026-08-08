import AmparoShared
import SwiftUI

/// §7.2 — caregiver-performed, on the member's device. Deliberately
/// English-only and technical: the member never sees this screen (it is
/// reachable later only via the hidden gesture + PIN).
struct EnrollmentView: View {
    @Environment(AppModel.self) private var model

    @State private var serverURL = ""
    @State private var email = ""
    @State private var masterPassword = ""
    @State private var caregiverName = ""
    @State private var caregiverPhone = ""
    @State private var pin = ""
    @State private var consentGiven = false
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var showWalkthrough = false

    private var isValid: Bool {
        URL(string: serverURL)?.scheme?.hasPrefix("http") == true
            && email.contains("@")
            && !masterPassword.isEmpty
            && !caregiverName.isEmpty
            && !caregiverPhone.isEmpty
            && pin.count >= 4
            && consentGiven
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("https://vault.example.ts.net", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Member account") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Master password", text: $masterPassword)
                    Text("The master password is used once to enroll and never stored on this device. Keep it in your own vault.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Caregiver (you)") {
                    TextField("Your name", text: $caregiverName)
                    TextField("Your phone (for the help screen)", text: $caregiverPhone)
                        .keyboardType(.phonePad)
                    SecureField("Settings PIN (4+ digits)", text: $pin)
                        .keyboardType(.numberPad)
                    Text("Settings reopen later by pressing and holding the home screen title for 5 seconds, then entering this PIN.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle(isOn: $consentGiven) {
                        Text("I confirm I am setting up this app with the knowledge, consent, and authorization of the account holder, and that I act on their behalf at their direction.")
                            .font(.footnote)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
                Section {
                    Button {
                        Task { await enroll() }
                    } label: {
                        if isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Enroll this device").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!isValid || isWorking)
                }
            }
            .navigationTitle("Amparo setup")
            .navigationDestination(isPresented: $showWalkthrough) {
                AutofillWalkthroughView()
            }
        }
    }

    private func enroll() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await model.vault.enroll(EnrollmentRequest(
                serverURL: URL(string: serverURL)!,
                email: email,
                masterPassword: masterPassword,
                caregiver: CaregiverProfile(name: caregiverName, phone: caregiverPhone),
                pin: pin,
                consent: ConsentRecord(caregiverName: caregiverName, attestedAt: Date())
            ))
            masterPassword = ""
            showWalkthrough = true
        } catch {
            // Caregiver-facing and technical on purpose — never member-visible.
            errorText = "Enrollment failed: \(error)"
        }
    }
}

/// §7.2 step 4: walk the caregiver through enabling autofill, then hand
/// the device over. (The autofill extension itself lands in M4 — the
/// setting appears once the extension target ships.)
struct AutofillWalkthroughView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Enable AutoFill (after the M4 update)") {
                Text("1. Open Settings → General → AutoFill & Passwords.")
                Text("2. Under \"AutoFill from\", enable Amparo.")
                Text("3. Turn off other password sources to avoid confusing suggestions.")
            }
            Section("Before handing the device over") {
                Text("Open a saved site once and confirm the password fills after Face ID.")
                Text("The member never needs this screen: everything below is automatic.")
            }
            Section {
                Button {
                    Task { await model.completeEnrollment() }
                } label: {
                    Text("Done — hand device to member").frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Final steps")
        .navigationBarBackButtonHidden()
    }
}
