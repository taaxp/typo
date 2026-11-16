import AppKit
import SwiftUI

/// "Share to Typo" on the Mac (Safari, Finder, Photos and any app with a Share menu).
final class MacShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let root = ShareView(providers: providers,
                             existingTags: ShareData.existingTags(),
                             existingCollections: ShareData.existingCollections(),
                             finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                             cancel: { [weak self] in
                                 self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                             })
            .frame(width: 420, height: 520)
        view = NSHostingView(rootView: root)
    }
}
