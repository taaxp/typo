import UIKit
import SwiftUI
import SwiftData

/// "Share to Typo" from any app. Classifies what was shared, lets you tag it,
/// and drops it in the App Group inbox for the app to import.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let view = ShareView(providers: providers,
                             existingTags: ShareData.existingTags(),
                             existingCollections: ShareData.existingCollections(),
                             finish: { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) },
                             cancel: { [weak self] in
                                 self?.extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
                             })
        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
