import SwiftUI

extension View {
    /// Inline navigation title. `navigationBarTitleDisplayMode` exists only on iOS, so this is a no-op on macOS.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}
