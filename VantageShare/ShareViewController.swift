import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Extension entry point — the OS instantiates this directly (see `NSExtensionPrincipalClass`
/// in Info.plist), no storyboard involved. Pulls the shared image out of the
/// `NSExtensionItem` the OS hands us, then embeds a SwiftUI view for the rest of the UI,
/// same pattern as CameraCaptureView bridges UIKit into the main app.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedImage()
    }

    private func loadSharedImage() {
        guard
            let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.noImage)
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, error == nil else {
                    self.extensionContext?.cancelRequest(withError: error ?? ShareExtensionError.noImage)
                    return
                }
                self.embedShareUI(imageData: data)
            }
        }
    }

    private func embedShareUI(imageData: Data) {
        let rootView = ShareExtensionRootView(
            imageData: imageData,
            onComplete: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
            onCancel: { [weak self] in self?.extensionContext?.cancelRequest(withError: ShareExtensionError.cancelled) }
        )
        let hosting = UIHostingController(rootView: rootView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }
}

private enum ShareExtensionError: Error {
    case noImage
    case cancelled
}
