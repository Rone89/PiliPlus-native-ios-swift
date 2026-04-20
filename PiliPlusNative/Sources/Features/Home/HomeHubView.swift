import SwiftUI

struct HomeHubView: View {
    var body: some View {
        VideoFeedView()
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("首页推荐")
    }
}
