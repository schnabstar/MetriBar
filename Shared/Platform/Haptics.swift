import SwiftUI

extension View {
    @ViewBuilder
    func sensoryHaptic(_ feedback: SensoryFeedback, trigger: some Equatable) -> some View {
        #if os(iOS)
        self.sensoryFeedback(feedback, trigger: trigger)
        #else
        self
        #endif
    }
}
