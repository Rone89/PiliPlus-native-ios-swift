import SwiftUI

struct HomeHubView: View {
    @State private var refreshSeed = 0

    var body: some View {
        VideoFeedView(externalRefreshToken: refreshSeed)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("首页推荐")
            .refreshable {
                refreshSeed += 1
            }
    }
}
