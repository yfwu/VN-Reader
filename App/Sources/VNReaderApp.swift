import SwiftUI
import ComicCore

@main
struct VNReaderApp: App {
    var body: some Scene {
        WindowGroup {
            Text("VN Reader — unrar \(RarArchive.unrarVersion)")
        }
    }
}
