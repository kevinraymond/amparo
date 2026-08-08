import SwiftUI

@main
struct AmparoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        model.enteredBackground()
                    case .active:
                        Task { await model.becameActive() }
                    default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            ProgressView()
        case .enrollment:
            EnrollmentView()
        case .locked:
            LockedView()
        case .home(let tiles):
            MemberHomeView(tiles: tiles)
        case .callCaregiver:
            CallCaregiverView()
        }
    }
}
