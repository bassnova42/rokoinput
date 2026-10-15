import Foundation

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let label: String
    static let standard = Shortcut(keyCode: 96, modifiers: 0, label: "F5")
    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: "shortcut"), let shortcut = try? JSONDecoder().decode(Self.self, from: data) else { return .standard }
        return shortcut
    }
    static func loadSwitch() -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: "switchShortcut") else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func saveSwitch() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "switchShortcut") }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "shortcut") }
}
