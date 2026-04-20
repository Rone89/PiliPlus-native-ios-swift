import SwiftUI

struct HomeHubView: View {
    @State private var selectedKind: FeedKind = .recommend
    @State private var refreshSeed = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("首页内容", selection: $selectedKind) {
                ForEach(FeedKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            VideoFeedView(kind: selectedKind, externalRefreshToken: refreshSeed)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("首页")
        .refreshable {
            refreshSeed += 1
        }
    }
}
