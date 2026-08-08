import AmparoShared
import SwiftUI

/// §7.4 — the product. Big tiles, icon + name, nothing else. No settings,
/// no toolbars, no password-manager vocabulary. The hidden caregiver door
/// is a 5-second hold on the title.
struct MemberHomeView: View {
    @Environment(AppModel.self) private var model
    let tiles: [MemberTile]

    @State private var showCaregiverDoor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(tiles) { tile in
                        NavigationLink(value: tile) {
                            TileView(tile: tile)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tile.displayName)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Amparo")
                        .font(.title2.bold())
                        .onLongPressGesture(minimumDuration: 5) {
                            showCaregiverDoor = true
                        }
                        .accessibilityHidden(true)
                }
            }
            .navigationDestination(for: MemberTile.self) { tile in
                CredentialDetailView(tile: tile)
            }
            .sheet(isPresented: $showCaregiverDoor) {
                CaregiverDoorSheet()
            }
        }
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
    }
}

struct TileView: View {
    @Environment(AppModel.self) private var model
    let tile: MemberTile
    @State private var icon: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let icon {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(String(tile.displayName.prefix(1)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.gradient)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(tile.displayName)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .task {
            icon = await model.icon(for: tile.domain)
        }
    }
}

/// Retry surface after a cancelled Face ID — one giant button, nothing else.
struct LockedView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 72))
                .accessibilityHidden(true)
            Button {
                Task { await model.unlock() }
            } label: {
                Text(String(localized: "unlock.button"))
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Spacer()
        }
        .dynamicTypeSize(DynamicTypeSize.accessibility1...DynamicTypeSize.accessibility5)
    }
}

/// One sheet, two stages: PIN gate, then settings swap in-place. A
/// dismiss-then-present handoff between two sheets can drop the second
/// presentation mid-animation — this shape has no handoff to drop.
struct CaregiverDoorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var unlocked = false
    @State private var pin = ""
    @State private var failed = false

    var body: some View {
        if unlocked {
            CaregiverSettingsView()
        } else {
            NavigationStack {
                Form {
                    SecureField("Caregiver PIN", text: $pin)
                        .keyboardType(.numberPad)
                    if failed {
                        Text("Wrong PIN").foregroundStyle(.red)
                    }
                    Button("Open settings") {
                        Task {
                            if await model.vault.verifyCaregiverPIN(pin) {
                                unlocked = true
                            } else {
                                failed = true
                                pin = ""
                            }
                        }
                    }
                    .disabled(pin.count < 4)
                }
                .navigationTitle("Caregiver access")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}
