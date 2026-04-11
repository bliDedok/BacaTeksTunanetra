import SwiftUI

@main
struct BacaTeksTunanetraApp: App {
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(viewModel)
                .onAppear {
                    viewModel.onAppLaunch()
                }
        }
    }
}
