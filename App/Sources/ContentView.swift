import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Hermes",
                systemImage: "bubble.left.and.text.bubble.right",
                description: Text("Aucune instance configurée.")
            )
        }
    }
}

#Preview {
    ContentView()
}
