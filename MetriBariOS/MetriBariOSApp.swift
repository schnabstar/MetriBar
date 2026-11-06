import MetriBarKit
import SwiftUI

@main
struct MetriBariOSApp: App {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView()
                .environment(model)
                .onOpenURL { url in
                    model.open(url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.center.handle(.didWake)
            case .background:
                model.center.handle(.willSleep)
            default:
                break
            }
        }
    }
}
