import SwiftUI
import ComicCore

/// In-flight and failed imports. These are deliberately styled differently from
/// books and are never openable, so a failed import can't look like a book.
struct ImportJobsSection: View {
    @EnvironmentObject private var importer: ImportCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.importSectionTitle).font(.headline)
                Spacer()
                if importer.jobs.contains(where: { !$0.isActive }) {
                    Button(L10n.importDismiss) { importer.dismissFinished() }.font(.subheadline)
                }
            }
            ForEach(importer.jobs) { job in
                ImportJobRow(job: job)
            }
        }
        .accessibilityIdentifier("library.imports")
    }
}

struct ImportJobRow: View {
    @ObservedObject var job: ImportJob
    @EnvironmentObject private var importer: ImportCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.fileName).font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                detail
            }
            Spacer(minLength: 8)
            if job.isActive {
                Button(L10n.importCancelAction) { importer.cancel(job) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("import.cancel")
            } else {
                Button { importer.dismiss(job) } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.importDismiss)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: job.isActive ? [5] : [])).foregroundStyle(borderColor))
        .accessibilityElement(children: .contain)
    }

    private var borderColor: Color {
        if case .failed = job.state { return .orange }
        return .secondary.opacity(0.5)
    }

    @ViewBuilder private var icon: some View {
        switch job.state {
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .duplicate: Image(systemName: "doc.on.doc").foregroundStyle(.secondary)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        default: ProgressView()
        }
    }

    @ViewBuilder private var detail: some View {
        switch job.state {
        case .waiting:
            Text(L10n.importWaiting).font(.caption).foregroundStyle(.secondary)
        case .downloading:
            Text(L10n.importDownloading).font(.caption).foregroundStyle(.secondary)
        case .working(let p):
            VStack(alignment: .leading, spacing: 4) {
                Text(phaseText(p.phase)).font(.caption).foregroundStyle(.secondary)
                if let f = p.fraction {
                    ProgressView(value: f).frame(maxWidth: 280)
                }
            }
        case .failed(let e):
            Text(e.title).font(.caption.weight(.semibold)).foregroundStyle(.orange)
            Text(e.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .duplicate(let name):
            Text(L10n.importDuplicate(name)).font(.caption).foregroundStyle(.secondary)
        case .finished:
            EmptyView()
        }
    }

    private func phaseText(_ p: ImportProgress.Phase) -> String {
        switch p {
        case .copying: return L10n.importCopying
        case .inspecting: return L10n.importInspecting
        case .generatingCover: return L10n.importCover
        case .finishing: return L10n.importFinishing
        }
    }
}
