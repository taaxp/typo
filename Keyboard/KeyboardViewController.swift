import UIKit
import SwiftUI
import SwiftData

/// The Typo keyboard.
///
/// - **Typo** tab: your library. Tap a text snippet or link to type it into the
///   current field. Tap a photo, GIF or file to copy it, then paste.
/// - **ABC** tab: a basic QWERTY keyboard so you can stay in Typo while typing.
/// - **Polish**: rewrites the selected text (or the text before the cursor) with
///   on-device Apple Intelligence.
///
/// iOS does not give keyboards microphone access, so dictation lives in the app.
final class KeyboardViewController: UIInputViewController {
    private var host: UIHostingController<AnyView>?
    private let actions = KeyboardActions()
    private var container: ModelContainer?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        actions.controller = self
        let hosting = UIHostingController(rootView: AnyView(EmptyView()))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        host = hosting

        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    /// Rebuild the view with a fresh context so saves made in the app since the
    /// keyboard last appeared show up.
    private func reload() {
        actions.hasFullAccess = hasFullAccess
        actions.needsGlobe = needsInputModeSwitchKey
        actions.polishAvailability = TextPolisher.availability

        if container == nil, hasFullAccess {
            container = try? TypoStore.makeContainer(role: .readOnly)
        }
        let root = KeyboardRootView(actions: actions, libraryAvailable: container != nil)
        if let container {
            host?.rootView = AnyView(root.modelContainer(container).id(UUID()))
        } else {
            host?.rootView = AnyView(root)
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        actions.returnKeyType = textDocumentProxy.returnKeyType ?? .default
    }
}

/// Bridge from SwiftUI to the text document proxy.
@MainActor
@Observable
final class KeyboardActions {
    weak var controller: UIInputViewController?
    var hasFullAccess = false
    var needsGlobe = true
    var polishAvailability: PolishAvailability = .unavailable("")
    var returnKeyType: UIReturnKeyType = .default
    var banner: String?
    var isPolishing = false

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    func insert(_ text: String) { proxy?.insertText(text) }
    func deleteBackward() { proxy?.deleteBackward() }
    func nextKeyboard() { controller?.advanceToNextInputMode() }

    func show(_ message: String) {
        banner = message
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if banner == message { banner = nil }
        }
    }

    /// Text and links are typed straight in. Everything else goes on the clipboard.
    func use(_ item: TypoItem) {
        if item.kind.isInsertableAsText {
            insert(item.text)
            UIDevice.current.playInputClick()
        } else {
            copy(item)
        }
    }

    static let maxCopyBytes = 20 * 1024 * 1024

    func copy(_ item: TypoItem) {
        guard hasFullAccess else {
            show("Turn on Allow Full Access to copy photos and files")
            return
        }
        // Keyboards run with a small memory budget; very large files would get the keyboard terminated.
        guard item.byteCount <= Self.maxCopyBytes else {
            show("Too large to copy from the keyboard. Open Typo to copy it.")
            return
        }
        Clipboard.copy([item])
        show("Copied. Touch and hold the text field, then Paste.")
    }

    /// Polishes the selection if there is one, otherwise the text before the cursor.
    /// iOS only exposes nearby text to keyboards, so very long passages may be cut off.
    func polish(_ style: PolishStyle) async {
        guard let proxy, !isPolishing else { return }
        let selected = proxy.selectedText ?? ""
        let source = selected.isEmpty ? (proxy.documentContextBeforeInput ?? "") : selected
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            show("Type or select some text first")
            return
        }
        isPolishing = true
        defer { isPolishing = false }
        do {
            let result = try await TextPolisher.polish(source, style: style)
            if selected.isEmpty {
                for _ in 0..<source.count { proxy.deleteBackward() }
            }
            // With a selection, inserting replaces it.
            proxy.insertText(result)
        } catch {
            show("Couldn't polish that text")
        }
    }
}
