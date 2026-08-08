import SwiftUI

/// M3-T5 — the single member-facing error surface (principle 4). Calm copy,
/// one giant call button, no retry, no error codes, no technical text. The
/// app self-heals from transient arrivals on the next foreground; for
/// terminal ones, the caregiver's hidden door (5 s hold on the headline +
/// PIN) opens settings so re-enrollment never requires a reinstall (D19).
struct CallCaregiverView: View {
    @Environment(AppModel.self) private var model

    @State private var showCaregiverDoor = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(String(localized: "call.title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .onLongPressGesture(minimumDuration: 5) {
                    showCaregiverDoor = true
                }
            if let caregiver = model.caregiver {
                Text(String(format: String(localized: "call.body"), caregiver.name))
                    .font(.title2)
                    .multilineTextAlignment(.center)
                if let url = telURL(caregiver.phone) {
                    Link(destination: url) {
                        Text(String(format: String(localized: "call.button"), caregiver.name))
                            .font(.title.bold())
                            .frame(maxWidth: .infinity, minHeight: 88)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(String(format: String(localized: "call.button"), caregiver.name))
                }
            } else {
                Text(String(localized: "call.body.generic"))
                    .font(.title2)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
        .sheet(isPresented: $showCaregiverDoor) {
            CaregiverDoorSheet()
        }
    }

    private func telURL(_ phone: String) -> URL? {
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty else { return nil }
        return URL(string: "tel:\(dialable)")
    }
}
