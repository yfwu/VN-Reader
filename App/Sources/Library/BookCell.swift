import SwiftUI
import ComicCore

struct CoverView: View {
    let book: BookRecord
    @EnvironmentObject private var library: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        // Fixed 2:3 frame; the cover fills and is cropped (tall strips no longer stretch the cell).
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(book.displayName.prefix(1)))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .task(id: book.id) {
            guard book.hasCover else { return }
            image = await CoverCache.shared.image(for: library.paths.coverFile(book.id))
        }
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let status: ReadingStatus
    var body: some View {
        switch status {
        case .unread:
            Text(L10n.statusUnread)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        case .finished:
            Label(L10n.statusFinished, systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())
        case .reading:
            EmptyView()
        }
    }
}

struct BookCell: View {
    let book: BookRecord
    let open: () -> Void
    let readFromStart: () -> Void
    let rename: () -> Void
    let reset: () -> Void
    let delete: () -> Void
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                CoverView(book: book)
                    .overlay(alignment: .topLeading) { StatusBadge(status: book.status).padding(6) }
                    .overlay(alignment: .topTrailing) {
                        if book.isFavorite {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
                                .padding(6).background(.thinMaterial, in: Circle()).padding(6)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if book.status == .reading {
                            ProgressView(value: book.progressFraction)
                                .progressViewStyle(.linear)
                                .padding(.horizontal, 8).padding(.bottom, 8)
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }
            .accessibilityLabel(accessibilitySummary)
            .accessibilityHint(L10n.menuOpen)
            .accessibilityIdentifier("book.\(book.displayName)")

            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.menuMore + "：" + book.displayName)
                .accessibilityIdentifier("book.menu.\(book.displayName)")
                .padding(.trailing, -10)
                .padding(.top, -10)
            }
        }
    }

    private var subtitle: String {
        switch book.status {
        case .unread: return L10n.pageCount(book.pageCount)
        case .reading: return L10n.pagesProgress(book.progress.currentPage + 1, book.pageCount)
        case .finished: return L10n.statusFinished + " · " + L10n.pageCount(book.pageCount)
        }
    }

    private var accessibilitySummary: String {
        let status: String
        switch book.status {
        case .unread: status = L10n.statusUnread
        case .reading: status = L10n.statusReading + "，" + L10n.pagesProgress(book.progress.currentPage + 1, book.pageCount)
        case .finished: status = L10n.statusFinished
        }
        return "\(book.displayName)，\(status)"
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(action: open) { Label(book.status == .reading ? L10n.continueReading : L10n.menuOpen, systemImage: "book") }
        if book.status != .unread {
            Button(action: readFromStart) { Label(L10n.menuReadFromStart, systemImage: "arrow.counterclockwise") }
        }
        Button(action: rename) { Label(L10n.menuRename, systemImage: "pencil") }
        Button { library.toggleFavorite(book.id) } label: {
            Label(book.isFavorite ? L10n.menuUnfavorite : L10n.menuFavorite, systemImage: book.isFavorite ? "heart.slash" : "heart")
        }
        if book.status != .finished {
            Button { library.markFinished(book.id) } label: { Label(L10n.menuMarkFinished, systemImage: "checkmark.circle") }
        }
        if book.status != .unread {
            Button(action: reset) { Label(L10n.menuResetProgress, systemImage: "arrow.uturn.backward") }
        }
        Divider()
        Button(role: .destructive, action: delete) { Label(L10n.menuDelete, systemImage: "trash") }
    }
}

struct ContinueReadingCard: View {
    let book: BookRecord
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                CoverView(book: book).frame(width: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.continueReading).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                    Text(book.displayName).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text(L10n.pagesProgress(book.progress.currentPage + 1, book.pageCount))
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    ProgressView(value: book.progressFraction).frame(maxWidth: 260)
                }
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.continueReading + "：" + book.displayName + "，" + L10n.pagesProgress(book.progress.currentPage + 1, book.pageCount))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library.continue")
    }
}
