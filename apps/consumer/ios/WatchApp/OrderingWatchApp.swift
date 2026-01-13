import SwiftUI

@main
struct OrderingWatchApp: App {
  @StateObject private var viewModel = WatchOrdersViewModel()

  var body: some Scene {
    WindowGroup {
      WatchContentView(viewModel: viewModel)
    }
  }
}
