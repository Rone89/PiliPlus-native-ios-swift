import SwiftUI

struct DanmakuOverlayView: View {
    let items: [ActiveDanmakuItem]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(items) { activeItem in
                    DanmakuBullet(item: activeItem, containerWidth: proxy.size.width)
                        .offset(y: CGFloat(activeItem.lane) * 28 + 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}

private struct DanmakuBullet: View {
    let item: ActiveDanmakuItem
    let containerWidth: CGFloat

    @State private var xOffset: CGFloat = .zero

    var body: some View {
        Text(item.item.text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BiliFormat.color(from: item.item.colorValue))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .shadow(radius: 1)
            .offset(x: xOffset)
            .onAppear {
                xOffset = containerWidth + 120
                withAnimation(.linear(duration: 6)) {
                    xOffset = -containerWidth - 220
                }
            }
    }
}
