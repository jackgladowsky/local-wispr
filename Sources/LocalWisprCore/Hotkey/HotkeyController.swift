import Carbon
import Foundation

final class HotkeyController: @unchecked Sendable {
    private static let signature = OSType(
        UInt32(UInt8(ascii: "L")) << 24
            | UInt32(UInt8(ascii: "W")) << 16
            | UInt32(UInt8(ascii: "S")) << 8
            | UInt32(UInt8(ascii: "P"))
    )

    private let onStart: @Sendable () -> Void
    private let onStop: @Sendable () -> Void
    private let onCancel: @Sendable () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var isRecording = false

    init(
        onStart: @escaping @Sendable () -> Void,
        onStop: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) {
        self.onStart = onStart
        self.onStop = onStop
        self.onCancel = onCancel
    }

    func start() -> Bool {
        guard hotKeyRef == nil, eventHandlerRef == nil else { return true }

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            eventHandlerRef = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            stop()
            return false
        }

        return true
    }

    func stop() {
        if isRecording {
            isRecording = false
            DispatchQueue.main.async { [onCancel] in
                onCancel()
            }
        }

        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }

        hotKeyRef = nil
        eventHandlerRef = nil
    }

    private static let eventHandler: EventHandlerUPP = { _, eventRef, userData in
        guard let eventRef, let userData else {
            return noErr
        }

        let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
        controller.handleEvent(eventRef)
        return noErr
    }

    private func handleEvent(_ event: EventRef) {
        let eventClass = GetEventClass(event)
        let eventKind = GetEventKind(event)

        guard eventClass == OSType(kEventClassKeyboard) else { return }

        switch Int(eventKind) {
        case kEventHotKeyPressed:
            guard !isRecording else { return }
            isRecording = true
            DispatchQueue.main.async { [onStart] in
                onStart()
            }

        case kEventHotKeyReleased:
            guard isRecording else { return }
            isRecording = false
            DispatchQueue.main.async { [onStop] in
                onStop()
            }

        default:
            break
        }
    }
}
