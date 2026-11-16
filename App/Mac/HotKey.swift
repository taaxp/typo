#if os(macOS)
import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut using Carbon's RegisterEventHotKey. It works in
/// the App Sandbox and needs no Accessibility permission.
final class HotKey {
    struct Combo: Hashable, Identifiable {
        let keyCode: UInt32
        let modifiers: UInt32
        let title: String
        var id: String { title }

        static let optionSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), title: "⌥ Space")
        static let commandShiftSpace = Combo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey), title: "⇧⌘ Space")
        static let optionCommandV = Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), title: "⌥⌘ V")
        static let controlOptionT = Combo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), title: "⌃⌥ T")
        static let all = [optionSpace, commandShiftSpace, optionCommandV, controlOptionT]
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(_ combo: Combo, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x5459_504F), id: 1)   // 'TYPO'
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
#endif
