import SwiftUI

struct HomeHubView: View {
    @State private var selectedKind: FeedKind = .recommend

    var body: some View {
        VStack(spacing: 0) {
            Picker("首页内容", selection: $selectedKind) {
                ForEach(FeedKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            VideoFeedView(kind: selectedKind)
                .id(selectedKind)
        }
        .navigationTitle("首页")
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
