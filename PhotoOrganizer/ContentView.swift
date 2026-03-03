import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        Group {
            if appState.sourceURL != nil {
                LibraryView()
            } else {
                WelcomeView()
            }
        }
        .environment(appState)
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { SessionStore.restore(into: appState) }
    }
}

#Preview {
    ContentView()
}
