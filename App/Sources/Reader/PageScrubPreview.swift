import SwiftUI

/// The preview shown while the page slider is dragged: a hand of pages fanned out
/// around the target page, dealt forward and back as the finger moves. Each page sits
/// on the side the book turns towards, so an RTL book fans the other way.
struct PageScrubPreview: View {
    @ObservedObject var model: ReaderViewModel
    let page: Int
    /// Horizontal position of the slider's thumb, in this view's coordinates.
    let thumbX: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pages shown on each side of the target.
    private static let reach = 2
    /// Width of the whole fan relative to the card height.
    private static let fanWidthRatio: CGFloat = 2
    /// Tilt per page away from the target, around a point below the cards.
    private static let tilt = 11.0
    private static let pivot = UnitPoint(x: 0.5, y: 1.9)

    private var pages: [Int] {
        Array(max(0, page - Self.reach)...min(model.pageCount - 1, page + Self.reach))
    }

    var body: some View {
        GeometryReader { geo in
            let height = min(geo.size.height * 0.52, 300)
            let margin = height * Self.fanWidthRatio / 2 + 12
            // Follows the thumb, but never leaves the screen.
            let x = geo.size.width > margin * 2
                ? min(max(thumbX, margin), geo.size.width - margin)
                : geo.size.width / 2

            VStack(spacing: 14) {
                ZStack {
                    ForEach(pages, id: \.self) { card($0, height: height) }
                }
                .frame(height: height)
                .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.84), value: page)

                Text(L10n.pageIndicator(page + 1, model.pageCount))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(x: x - geo.size.width / 2)
            .padding(.bottom, 14)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true) // VoiceOver reads the slider's value instead.
    }

    private func card(_ p: Int, height: CGFloat) -> some View {
        let offset = p - page
        let side = model.record.readingDirection == .leftToRight ? 1.0 : -1.0
        let distance = Double(abs(offset))
        return ScrubPageCard(model: model, page: p, height: height, isTarget: offset == 0)
            .overlay {
                RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.22 * distance))
            }
            .scaleEffect(1 - 0.05 * distance, anchor: .bottom)
            .rotationEffect(.degrees(side * Double(offset) * Self.tilt), anchor: Self.pivot)
            .zIndex(-distance)
            .transition(.opacity)
    }
}

private struct ScrubPageCard: View {
    @ObservedObject var model: ReaderViewModel
    let page: Int
    let height: CGFloat
    let isTarget: Bool
    @State private var image: UIImage?

    /// Wide images are double-page spreads; a stray extreme ratio must not break the fan.
    private var aspect: CGFloat {
        guard let s = image?.size, s.height > 0 else { return 0.7 }
        return min(max(s.width / s.height, 0.45), 1.5)
    }

    var body: some View {
        ZStack {
            Color(white: 0.2)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(verbatim: "\(page + 1)")
                    .font(.title.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: height * aspect, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) {
            if model.record.bookmarks.contains(page) {
                Image(systemName: "bookmark.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .shadow(radius: 2)
                    .padding(.trailing, 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .task(id: model.preparation) {
            guard image == nil, let thumbnails = model.thumbnails else { return }
            if let ready = thumbnails.cached(page) ?? model.loader?.cachedImage(page) {
                image = ready
                return
            }
            // The target goes first; neighbours are skipped when the finger moves on.
            if !isTarget {
                try? await Task.sleep(nanoseconds: 80_000_000)
                if Task.isCancelled { return }
            }
            if let loaded = await thumbnails.thumbnail(page) { image = loaded }
        }
    }
}
