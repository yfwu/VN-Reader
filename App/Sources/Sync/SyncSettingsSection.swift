import SwiftUI

struct SyncSettingsSection: View {
    @ObservedObject var sync: CloudSyncCoordinator
    @State private var askEnable = false

    var body: some View {
        Section {
            Toggle(L10n.syncTitle, isOn: Binding(get: { sync.enabled }, set: { value in
                if value { askEnable = true } else { sync.setEnabled(false) }
            }))
            .accessibilityIdentifier("settings.sync.enabled")
            Text(sync.status).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.sync.status")
            if let fraction = sync.transferProgress { ProgressView(value: fraction) }
            if sync.enabled {
                Button(L10n.syncNow) { sync.synchronize() }
                    .disabled(sync.busy)
                    .accessibilityIdentifier("settings.sync.now")
            }
        } header: { Text(L10n.syncTitle) } footer: {
            Text(L10n.syncFooter)
        }
        .confirmationDialog(L10n.syncEnableTitle, isPresented: $askEnable, titleVisibility: .visible) {
            Button(L10n.syncEnable) { sync.setEnabled(true) }
            Button(L10n.cancel, role: .cancel) {}
        } message: { Text(L10n.syncEnableMessage) }
    }
}
