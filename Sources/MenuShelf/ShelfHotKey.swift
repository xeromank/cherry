import Carbon
import Dispatch

@MainActor
final class ShelfHotKey {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let action: () -> Void

    init?(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let target = GetApplicationEventTarget()
        let handlerResult = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var eventID = EventHotKeyID()
            let result = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID
            )
            guard result == noErr, eventID.signature == 0x4D53484C, eventID.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let owner = Unmanaged<ShelfHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { [weak owner] in owner?.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerResult == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: 0x4D53484C, id: 1)
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | shiftKey), hotKeyID, target, 0, &hotKey)
        guard result == noErr else { return nil }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
