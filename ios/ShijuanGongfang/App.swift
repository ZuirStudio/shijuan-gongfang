import SwiftUI

@main
struct ShijuanGongfangApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var store = Store()

    var body: some View {
        NavigationStack {
            JobListView()
        }
        .environmentObject(store)
        .task { await store.refreshJobs() }
    }
}
