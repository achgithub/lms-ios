import SwiftUI
import UIKit

/// Wraps a set of file URLs for `.sheet(item:)` — SwiftUI needs an `Identifiable`
/// to drive the sheet's presented/dismissed state from one optional binding.
struct ExportShareItem: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined() }
}

/// Thin `UIViewControllerRepresentable` around `UIActivityViewController`, so the
/// system share sheet can be triggered after an async file-prep step rather than
/// from a `ShareLink` (which needs its items ready synchronously on tap).
struct ActivityShareView: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
