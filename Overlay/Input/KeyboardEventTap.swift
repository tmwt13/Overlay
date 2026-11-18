import CoreGraphics
import Darwin
import Foundation

final class KeyboardEventTap {
    enum StartResult {
        case started
        case alreadyRunning
        case unavailable
    }

    private var lock: Int32 = -1
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var receive: ((CGEventType, CGEvent) -> Bool)?

    var isRunning: Bool { port != nil }

    func start(receive: @escaping (CGEventType, CGEvent) -> Bool) -> StartResult {
        guard !isRunning else { return .started }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("devplaceholder.L3SW7CHG.Overlay.keyboard.lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return .unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let blocked = errno == EWOULDBLOCK
            close(fd)
            return blocked ? .alreadyRunning : .unavailable
        }
        let events: [CGEventType] = [
            .flagsChanged, .keyDown, .keyUp, .leftMouseDown,
            .rightMouseDown, .otherMouseDown, .scrollWheel
        ]
        let mask = events.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let tap = Unmanaged<KeyboardEventTap>.fromOpaque(context).takeUnretainedValue()
                    return tap.handle(type, event: event) ? nil : Unmanaged.passUnretained(event)
                }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            close(fd)
            return .unavailable
        }

        lock = fd
        self.port = port
        self.source = source
        self.receive = receive
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return .started
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        if lock >= 0 { close(lock) }
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput), let port {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return receive?(type, event) ?? false
    }
}
