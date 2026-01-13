import SwiftUI

struct WatchContentView: View {
  @ObservedObject var viewModel: WatchOrdersViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Ordering")
        .font(.headline)
      if viewModel.isLoading {
        ProgressView()
      }
      if let status = viewModel.status, !status.isEmpty {
        Text(status)
          .font(.footnote)
      }
      List {
        ForEach(viewModel.orders) { order in
          Button {
            viewModel.handleOrderTap(order)
          } label: {
            VStack(alignment: .leading) {
              Text(order.title.isEmpty ? "Reorder" : order.title)
                .font(.body)
              if !order.storeName.isEmpty {
                Text(order.storeName)
                  .font(.footnote)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }
    }
    .onAppear { viewModel.refresh() }
  }
}
