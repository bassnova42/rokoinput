import Foundation

struct HoldKey {
    static let minimumDuration: TimeInterval = 0.5
    private(set) var isHeld = false
    private var pressedAt: TimeInterval?
    private(set) var lastDuration: TimeInterval?
    var wasShortPress: Bool { lastDuration.map { $0 < Self.minimumDuration } ?? false }
    // Repeated key-downs must never turn recording off or create another session.
    mutating func update(pressed: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard pressed != isHeld else { return false }
        if pressed {
            pressedAt = now
            lastDuration = nil
        } else {
            lastDuration = pressedAt.map { max(0, now - $0) }
            pressedAt = nil
        }
        isHeld = pressed
        return true
    }
}
